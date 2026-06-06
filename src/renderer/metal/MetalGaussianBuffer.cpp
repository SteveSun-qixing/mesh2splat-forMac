#include "MetalGaussianBuffer.hpp"

#include "MetalBuffer.hpp"
#include "MetalDeviceContext.hpp"
#include "MetalResourceUploader.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <sstream>
#include <string>
#include <type_traits>
#include <utility>

namespace mesh2splat::metal {
namespace {

static_assert(
    std::is_standard_layout<core::GaussianRecord>::value,
    "GaussianRecord must remain standard-layout for byte-for-byte Metal uploads.");
static_assert(sizeof(core::GaussianRecord) == sizeof(float) * 4 * 6, "GaussianRecord must remain six float4 slots.");
static_assert(offsetof(core::GaussianRecord, position) == 0, "Gaussian position must start at float4 slot 0.");
static_assert(
    offsetof(core::GaussianRecord, color) == sizeof(float) * 4,
    "Gaussian color must start at float4 slot 1.");
static_assert(
    offsetof(core::GaussianRecord, scale) == sizeof(float) * 4 * 2,
    "Gaussian scale must start at float4 slot 2.");
static_assert(
    offsetof(core::GaussianRecord, normal) == sizeof(float) * 4 * 3,
    "Gaussian normal must start at float4 slot 3.");
static_assert(
    offsetof(core::GaussianRecord, rotation) == sizeof(float) * 4 * 4,
    "Gaussian rotation must start at float4 slot 4.");
static_assert(
    offsetof(core::GaussianRecord, pbr) == sizeof(float) * 4 * 5,
    "Gaussian pbr must start at float4 slot 5.");

std::size_t saturatedAdd(std::size_t lhs, std::size_t rhs)
{
    if (rhs > std::numeric_limits<std::size_t>::max() - lhs) {
        return std::numeric_limits<std::size_t>::max();
    }

    return lhs + rhs;
}

std::size_t clampedCapacityGrowth(std::size_t currentCapacity, std::size_t requestedCapacity)
{
    if (requestedCapacity <= currentCapacity) {
        return currentCapacity;
    }

    const std::size_t maxCapacity = static_cast<std::size_t>(std::numeric_limits<uint32_t>::max());
    const std::size_t growth = currentCapacity / 2;
    if (growth == 0 || currentCapacity > maxCapacity - growth) {
        return requestedCapacity;
    }

    return std::max(requestedCapacity, currentCapacity + growth);
}

std::size_t bufferSize(const std::unique_ptr<MetalBuffer>& buffer)
{
    return buffer == nullptr ? 0 : buffer->size();
}

MetalGaussianBounds calculateBounds(const core::GaussianRecord* gaussians, std::size_t count)
{
    MetalGaussianBounds bounds;
    if (gaussians == nullptr || count == 0) {
        return bounds;
    }

    std::array<float, 3> minPosition = {
        gaussians[0].position[0],
        gaussians[0].position[1],
        gaussians[0].position[2],
    };
    std::array<float, 3> maxPosition = minPosition;
    bool hasFinitePosition = core::isFiniteFloatArray(gaussians[0].position, 3);

    if (!hasFinitePosition) {
        minPosition = {0.0f, 0.0f, 0.0f};
        maxPosition = minPosition;
    }

    for (std::size_t index = hasFinitePosition ? 1 : 0; index < count; ++index) {
        const core::GaussianRecord& gaussian = gaussians[index];
        if (!core::isFiniteFloatArray(gaussian.position, 3)) {
            continue;
        }

        if (!hasFinitePosition) {
            minPosition = {gaussian.position[0], gaussian.position[1], gaussian.position[2]};
            maxPosition = minPosition;
            hasFinitePosition = true;
            continue;
        }

        for (std::size_t axis = 0; axis < 3; ++axis) {
            minPosition[axis] = std::min(minPosition[axis], gaussian.position[axis]);
            maxPosition[axis] = std::max(maxPosition[axis], gaussian.position[axis]);
        }
    }

    if (!hasFinitePosition) {
        return bounds;
    }

    bounds.min = minPosition;
    bounds.max = maxPosition;
    for (std::size_t axis = 0; axis < 3; ++axis) {
        bounds.center[axis] = (bounds.min[axis] + bounds.max[axis]) * 0.5f;
    }

    const float extentX = bounds.max[0] - bounds.center[0];
    const float extentY = bounds.max[1] - bounds.center[1];
    const float extentZ = bounds.max[2] - bounds.center[2];
    bounds.radius = std::sqrt(extentX * extentX + extentY * extentY + extentZ * extentZ);
    bounds.valid = true;
    return bounds;
}

MetalGaussianVisibilityStats calculateVisibilityStats(const core::GaussianRecord* gaussians, std::size_t count)
{
    MetalGaussianVisibilityStats stats;
    stats.inputCount = count;
    if (gaussians == nullptr) {
        stats.invalidRecordCount = count;
        return stats;
    }

    for (std::size_t index = 0; index < count; ++index) {
        const core::GaussianRecord& gaussian = gaussians[index];
        if (!core::isFiniteGaussianRecord(gaussian) || !core::hasNormalizedGaussianAlpha(gaussian)) {
            ++stats.invalidRecordCount;
            continue;
        }

        ++stats.validRecordCount;
        if (gaussian.color[3] <= 0.0f) {
            ++stats.alphaZeroCount;
            continue;
        }

        if (!core::hasUsableGaussianScale(gaussian) ||
            gaussian.scale[0] < core::kGaussianMinimumAxisScale ||
            gaussian.scale[1] < core::kGaussianMinimumAxisScale ||
            gaussian.scale[2] < core::kGaussianMinimumAxisScale) {
            ++stats.degenerateScaleCount;
            continue;
        }

        ++stats.visibleCount;
    }

    return stats;
}

} // namespace

struct MetalGaussianBuffer::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    std::unique_ptr<MetalBuffer> buffer;
    std::unique_ptr<MetalBuffer> counterBuffer;
    std::unique_ptr<MetalBuffer> counterReadbackBuffer;
    std::size_t capacity = 0;
    uint32_t count = 0;
    MetalGaussianBounds bounds;
    MetalGaussianVisibilityStats visibilityStats;
    std::string lastErrorMessage;

    void clearError()
    {
        lastErrorMessage.clear();
    }

    bool fail(std::string message)
    {
        lastErrorMessage = std::move(message);
        return false;
    }

    void clearMetadata()
    {
        bounds = {};
        visibilityStats = {};
    }

    void updateMetadata(const core::GaussianRecord* gaussians, std::size_t gaussianCount)
    {
        bounds = calculateBounds(gaussians, gaussianCount);
        visibilityStats = calculateVisibilityStats(gaussians, gaussianCount);
    }
};

MetalGaussianBuffer::MetalGaussianBuffer(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = &deviceContext;
}

MetalGaussianBuffer::~MetalGaussianBuffer() = default;

MetalGaussianBuffer::MetalGaussianBuffer(MetalGaussianBuffer&&) noexcept = default;

MetalGaussianBuffer& MetalGaussianBuffer::operator=(MetalGaussianBuffer&&) noexcept = default;

bool MetalGaussianBuffer::create(std::size_t capacity, const char* label)
{
    if (m_impl->deviceContext == nullptr) {
        return m_impl->fail("Metal gaussian buffer creation failed: device context is unavailable.");
    }
    if (capacity == 0) {
        return m_impl->fail("Metal gaussian buffer creation failed: capacity must be greater than zero.");
    }
    if (!core::gaussianCountFitsBuffer(capacity)) {
        return m_impl->fail("Metal gaussian buffer creation failed: capacity exceeds GaussianRecord buffer limits.");
    }

    const std::string baseLabel = label != nullptr ? label : "Metal Gaussian Buffer";
    auto buffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto counterBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto counterReadbackBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    const uint32_t initialCount = 0;
    MetalResourceUploadBatch uploadBatch(
        m_impl->deviceContext->nativeDevice(),
        m_impl->deviceContext->nativeCommandQueue(),
        "Mesh2Splat Gaussian Counter Upload",
        "Mesh2Splat Gaussian Counter Upload Blit");
    if (!buffer->createPrivate(core::gaussianBufferByteSize(capacity), baseLabel.c_str())) {
        return m_impl->fail("Metal gaussian buffer creation failed: data buffer allocation failed.");
    }
    if (!counterBuffer->createPrivateWithData(
            sizeof(initialCount),
            &initialCount,
            uploadBatch,
            (baseLabel + " Count").c_str())) {
        return m_impl->fail("Metal gaussian buffer creation failed: GPU counter allocation/upload failed.");
    }
    if (!counterReadbackBuffer->createShared(
            sizeof(initialCount),
            &initialCount,
            (baseLabel + " Count Readback").c_str())) {
        return m_impl->fail("Metal gaussian buffer creation failed: counter readback allocation failed.");
    }
    if (!uploadBatch.commitAndWait()) {
        return m_impl->fail("Metal gaussian buffer creation failed: counter upload command did not complete.");
    }

    m_impl->buffer = std::move(buffer);
    m_impl->counterBuffer = std::move(counterBuffer);
    m_impl->counterReadbackBuffer = std::move(counterReadbackBuffer);
    m_impl->capacity = capacity;
    m_impl->count = 0;
    m_impl->clearMetadata();
    m_impl->clearError();
    return true;
}

bool MetalGaussianBuffer::resize(std::size_t capacity, const char* label)
{
    return create(capacity, label);
}

bool MetalGaussianBuffer::ensureCapacity(std::size_t capacity, const char* label)
{
    if (capacity == 0) {
        m_impl->count = 0;
        m_impl->clearMetadata();
        m_impl->clearError();
        return true;
    }

    if (hasCapacityFor(capacity)) {
        m_impl->clearError();
        return true;
    }

    if (!core::gaussianCountFitsBuffer(capacity)) {
        return m_impl->fail("Metal gaussian ensureCapacity failed: requested capacity exceeds buffer limits.");
    }

    const std::size_t targetCapacity =
        isValid() ? clampedCapacityGrowth(m_impl->capacity, capacity) : capacity;
    if (create(targetCapacity, label)) {
        return true;
    }

    return targetCapacity == capacity ? false : create(capacity, label);
}

bool MetalGaussianBuffer::upload(const std::vector<core::GaussianRecord>& gaussians, const char* label)
{
    if (m_impl->deviceContext == nullptr) {
        reset();
        return m_impl->fail("Metal gaussian upload failed: device context is unavailable.");
    }
    if (gaussians.empty()) {
        reset();
        return m_impl->fail("Metal gaussian upload failed: gaussian list is empty.");
    }
    if (!core::gaussianCountFitsBuffer(gaussians.size())) {
        reset();
        return m_impl->fail("Metal gaussian upload failed: gaussian count exceeds buffer limits.");
    }

    const std::string baseLabel = label != nullptr ? label : "Metal Gaussian Buffer";
    auto buffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto counterBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto counterReadbackBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    const uint32_t initialCount = static_cast<uint32_t>(gaussians.size());
    MetalResourceUploadBatch uploadBatch(
        m_impl->deviceContext->nativeDevice(),
        m_impl->deviceContext->nativeCommandQueue(),
        "Mesh2Splat Gaussian Buffer Upload",
        "Mesh2Splat Gaussian Buffer Upload Blit");
    if (!buffer->createPrivateWithData(
            core::gaussianBufferByteSize(gaussians.size()),
            gaussians.data(),
            uploadBatch,
            baseLabel.c_str())) {
        reset();
        return m_impl->fail("Metal gaussian upload failed: data buffer allocation/upload failed.");
    }
    if (!counterBuffer->createPrivateWithData(
            sizeof(initialCount),
            &initialCount,
            uploadBatch,
            (baseLabel + " Count").c_str())) {
        reset();
        return m_impl->fail("Metal gaussian upload failed: GPU counter allocation/upload failed.");
    }
    if (!counterReadbackBuffer->createShared(
            sizeof(initialCount),
            &initialCount,
            (baseLabel + " Count Readback").c_str())) {
        reset();
        return m_impl->fail("Metal gaussian upload failed: counter readback allocation failed.");
    }
    if (!uploadBatch.commitAndWait()) {
        reset();
        return m_impl->fail("Metal gaussian upload failed: upload command did not complete.");
    }

    m_impl->buffer = std::move(buffer);
    m_impl->counterBuffer = std::move(counterBuffer);
    m_impl->counterReadbackBuffer = std::move(counterReadbackBuffer);
    m_impl->capacity = gaussians.size();
    m_impl->count = initialCount;
    m_impl->updateMetadata(gaussians.data(), gaussians.size());
    m_impl->clearError();
    return true;
}

bool MetalGaussianBuffer::setCount(uint32_t count)
{
    if (count > m_impl->capacity) {
        return m_impl->fail("Metal gaussian count update failed: count exceeds capacity.");
    }
    if (m_impl->deviceContext == nullptr) {
        return m_impl->fail("Metal gaussian count update failed: device context is unavailable.");
    }
    if (m_impl->buffer == nullptr || !m_impl->buffer->isValid() ||
        m_impl->counterBuffer == nullptr || !m_impl->counterBuffer->isValid() ||
        m_impl->counterReadbackBuffer == nullptr || !m_impl->counterReadbackBuffer->isValid()) {
        return m_impl->fail("Metal gaussian count update failed: gaussian buffers are not allocated.");
    }
    if (!m_impl->counterReadbackBuffer->isCpuAccessible()) {
        return m_impl->fail("Metal gaussian count update failed: counter readback buffer is not CPU accessible.");
    }

    MetalResourceUploader uploader(
        m_impl->deviceContext->nativeDevice(),
        m_impl->deviceContext->nativeCommandQueue());
    if (!uploader.uploadBufferToPrivate(
            &count,
            sizeof(count),
            m_impl->counterBuffer->nativeBuffer(),
            "Mesh2Splat Gaussian Count")) {
        return m_impl->fail("Metal gaussian count update failed: GPU counter upload did not complete.");
    }

    if (!m_impl->counterReadbackBuffer->update(&count, sizeof(count))) {
        return m_impl->fail("Metal gaussian count update failed: counter readback update failed.");
    }

    m_impl->count = count;
    m_impl->clearError();
    return true;
}

bool MetalGaussianBuffer::encodeResetGpuCounter(void* commandBuffer)
{
    const uint32_t count = 0;
    if (commandBuffer == nullptr) {
        return m_impl->fail("Metal gaussian counter reset failed: command buffer is null.");
    }
    if (m_impl->counterBuffer == nullptr || !m_impl->counterBuffer->isValid() ||
        m_impl->counterReadbackBuffer == nullptr || !m_impl->counterReadbackBuffer->isValid()) {
        return m_impl->fail("Metal gaussian counter reset failed: counter buffers are not allocated.");
    }
    if (!m_impl->counterBuffer->encodeFill(commandBuffer, 0, 0, sizeof(count))) {
        return m_impl->fail("Metal gaussian counter reset failed: fill command could not be encoded.");
    }
    if (!m_impl->counterReadbackBuffer->update(&count, sizeof(count))) {
        return m_impl->fail("Metal gaussian counter reset failed: readback mirror could not be reset.");
    }

    m_impl->count = 0;
    m_impl->visibilityStats.visibleCount = 0;
    m_impl->clearError();
    return true;
}

bool MetalGaussianBuffer::encodeReadbackGpuCounter(void* commandBuffer)
{
    if (commandBuffer == nullptr) {
        return m_impl->fail("Metal gaussian counter readback failed: command buffer is null.");
    }
    if (m_impl->counterBuffer == nullptr || !m_impl->counterBuffer->isValid() ||
        m_impl->counterReadbackBuffer == nullptr || !m_impl->counterReadbackBuffer->isValid()) {
        return m_impl->fail("Metal gaussian counter readback failed: counter buffers are not allocated.");
    }
    if (!m_impl->counterBuffer->encodeCopyTo(
            commandBuffer,
            *m_impl->counterReadbackBuffer,
            sizeof(uint32_t))) {
        return m_impl->fail("Metal gaussian counter readback failed: copy command could not be encoded.");
    }

    m_impl->clearError();
    return true;
}

bool MetalGaussianBuffer::readGpuCounter()
{
    uint32_t count = 0;
    if (m_impl->counterReadbackBuffer == nullptr || !m_impl->counterReadbackBuffer->isValid()) {
        return m_impl->fail("Metal gaussian counter read failed: counter readback buffer is not allocated.");
    }
    if (!m_impl->counterReadbackBuffer->isCpuAccessible()) {
        return m_impl->fail("Metal gaussian counter read failed: counter readback buffer is not CPU accessible.");
    }
    if (!m_impl->counterReadbackBuffer->read(&count, sizeof(count))) {
        return m_impl->fail("Metal gaussian counter read failed: counter readback copy failed.");
    }
    if (count > m_impl->capacity) {
        return m_impl->fail("Metal gaussian counter read failed: GPU count exceeds gaussian capacity.");
    }

    m_impl->count = count;
    m_impl->clearError();
    return true;
}

void MetalGaussianBuffer::reset()
{
    m_impl->buffer.reset();
    m_impl->counterBuffer.reset();
    m_impl->counterReadbackBuffer.reset();
    m_impl->capacity = 0;
    m_impl->count = 0;
    m_impl->clearMetadata();
    m_impl->clearError();
}

bool MetalGaussianBuffer::isValid() const
{
    return m_impl->buffer != nullptr && m_impl->buffer->isValid() &&
        m_impl->counterBuffer != nullptr && m_impl->counterBuffer->isValid() &&
        m_impl->counterReadbackBuffer != nullptr && m_impl->counterReadbackBuffer->isValid() &&
        m_impl->counterReadbackBuffer->isCpuAccessible() &&
        m_impl->capacity > 0 &&
        m_impl->count <= m_impl->capacity &&
        core::gaussianCountFitsBuffer(m_impl->capacity) &&
        m_impl->buffer->size() >= core::gaussianBufferByteSize(m_impl->capacity) &&
        m_impl->counterBuffer->size() >= sizeof(uint32_t) &&
        m_impl->counterReadbackBuffer->size() >= sizeof(uint32_t);
}

bool MetalGaussianBuffer::hasCapacityFor(std::size_t count) const
{
    return isValid() &&
        core::gaussianCountFitsBuffer(count) &&
        count <= m_impl->capacity;
}

std::size_t MetalGaussianBuffer::capacity() const
{
    return m_impl->capacity;
}

uint32_t MetalGaussianBuffer::count() const
{
    return m_impl->count;
}

const std::string& MetalGaussianBuffer::lastErrorMessage() const
{
    return m_impl->lastErrorMessage;
}

std::size_t MetalGaussianBuffer::sizeBytes() const
{
    return m_impl->buffer == nullptr ? 0 : m_impl->buffer->size();
}

std::size_t MetalGaussianBuffer::totalSizeBytes() const
{
    return resourceStats().totalBytes;
}

MetalGaussianBufferResourceStats MetalGaussianBuffer::resourceStats() const
{
    MetalGaussianBufferResourceStats stats;
    stats.capacity = m_impl->capacity;
    stats.count = m_impl->count;
    stats.recordStrideBytes = sizeof(core::GaussianRecord);
    stats.dataBytes = bufferSize(m_impl->buffer);
    stats.counterBytes = bufferSize(m_impl->counterBuffer);
    stats.counterReadbackBytes = bufferSize(m_impl->counterReadbackBuffer);
    stats.totalBytes = saturatedAdd(saturatedAdd(stats.dataBytes, stats.counterBytes), stats.counterReadbackBytes);
    return stats;
}

MetalGaussianBounds MetalGaussianBuffer::bounds() const
{
    return m_impl->bounds;
}

const MetalGaussianVisibilityStats& MetalGaussianBuffer::visibilityStats() const
{
    return m_impl->visibilityStats;
}

MetalGaussianBufferDiagnostics MetalGaussianBuffer::diagnostics() const
{
    MetalGaussianBufferDiagnostics diagnostics;
    diagnostics.valid = isValid();
    diagnostics.capacity = m_impl->capacity;
    diagnostics.count = m_impl->count;
    diagnostics.sizeBytes = sizeBytes();
    diagnostics.totalSizeBytes = totalSizeBytes();
    diagnostics.bounds = m_impl->bounds;
    diagnostics.visibility = m_impl->visibilityStats;
    diagnostics.lastErrorMessage = m_impl->lastErrorMessage;
    return diagnostics;
}

std::string MetalGaussianBuffer::diagnosticSummary() const
{
    const MetalGaussianBufferResourceStats stats = resourceStats();
    std::ostringstream stream;
    stream << "MetalGaussianBuffer(valid=" << (isValid() ? "true" : "false")
           << ", count=" << stats.count
           << ", capacity=" << stats.capacity
           << ", recordStrideBytes=" << stats.recordStrideBytes
           << ", dataBytes=" << stats.dataBytes
           << ", counterBytes=" << stats.counterBytes
           << ", counterReadbackBytes=" << stats.counterReadbackBytes
           << ", totalBytes=" << stats.totalBytes
           << ", visible=" << m_impl->visibilityStats.visibleCount
           << ", rejected=" << m_impl->visibilityStats.rejectedCount()
           << ", boundsValid=" << (m_impl->bounds.valid ? "true" : "false");
    if (!m_impl->lastErrorMessage.empty()) {
        stream << ", lastError=\"" << m_impl->lastErrorMessage << "\"";
    }
    stream << ")";
    return stream.str();
}

void* MetalGaussianBuffer::nativeBuffer() const
{
    return m_impl->buffer == nullptr ? nullptr : m_impl->buffer->nativeBuffer();
}

void* MetalGaussianBuffer::nativeCounterBuffer() const
{
    return m_impl->counterBuffer == nullptr ? nullptr : m_impl->counterBuffer->nativeBuffer();
}

void* MetalGaussianBuffer::nativeCounterReadbackBuffer() const
{
    return m_impl->counterReadbackBuffer == nullptr ? nullptr : m_impl->counterReadbackBuffer->nativeBuffer();
}

} // namespace mesh2splat::metal
