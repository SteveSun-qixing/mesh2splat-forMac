#include "MetalGaussianBuffer.hpp"

#include "MetalBuffer.hpp"
#include "MetalDeviceContext.hpp"
#include "MetalResourceUploader.hpp"

#include <string>

namespace mesh2splat::metal {

struct MetalGaussianBuffer::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    std::unique_ptr<MetalBuffer> buffer;
    std::unique_ptr<MetalBuffer> counterBuffer;
    std::unique_ptr<MetalBuffer> counterReadbackBuffer;
    std::size_t capacity = 0;
    uint32_t count = 0;
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
    if (m_impl->deviceContext == nullptr || capacity == 0 || !core::gaussianCountFitsBuffer(capacity)) {
        return false;
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
    if (!buffer->createPrivate(core::gaussianBufferByteSize(capacity), baseLabel.c_str()) ||
        !counterBuffer->createPrivateWithData(
            sizeof(initialCount),
            &initialCount,
            uploadBatch,
            (baseLabel + " Count").c_str()) ||
        !counterReadbackBuffer->createShared(
            sizeof(initialCount),
            &initialCount,
            (baseLabel + " Count Readback").c_str()) ||
        !uploadBatch.commitAndWait()) {
        return false;
    }

    m_impl->buffer = std::move(buffer);
    m_impl->counterBuffer = std::move(counterBuffer);
    m_impl->counterReadbackBuffer = std::move(counterReadbackBuffer);
    m_impl->capacity = capacity;
    m_impl->count = 0;
    return true;
}

bool MetalGaussianBuffer::upload(const std::vector<core::GaussianRecord>& gaussians, const char* label)
{
    if (m_impl->deviceContext == nullptr || gaussians.empty() || !core::gaussianCountFitsBuffer(gaussians.size())) {
        reset();
        return false;
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
            baseLabel.c_str()) ||
        !counterBuffer->createPrivateWithData(
            sizeof(initialCount),
            &initialCount,
            uploadBatch,
            (baseLabel + " Count").c_str()) ||
        !counterReadbackBuffer->createShared(
            sizeof(initialCount),
            &initialCount,
            (baseLabel + " Count Readback").c_str()) ||
        !uploadBatch.commitAndWait()) {
        reset();
        return false;
    }

    m_impl->buffer = std::move(buffer);
    m_impl->counterBuffer = std::move(counterBuffer);
    m_impl->counterReadbackBuffer = std::move(counterReadbackBuffer);
    m_impl->capacity = gaussians.size();
    m_impl->count = initialCount;
    return true;
}

bool MetalGaussianBuffer::setCount(uint32_t count)
{
    if (count > m_impl->capacity) {
        return false;
    }

    m_impl->count = count;
    return m_impl->counterReadbackBuffer == nullptr ||
        m_impl->counterReadbackBuffer->update(&count, sizeof(count));
}

bool MetalGaussianBuffer::encodeResetGpuCounter(void* commandBuffer)
{
    const uint32_t count = 0;
    if (m_impl->counterBuffer == nullptr || m_impl->counterReadbackBuffer == nullptr ||
        !m_impl->counterBuffer->encodeFill(commandBuffer, 0, 0, sizeof(count)) ||
        !m_impl->counterReadbackBuffer->update(&count, sizeof(count))) {
        return false;
    }

    m_impl->count = 0;
    return true;
}

bool MetalGaussianBuffer::encodeReadbackGpuCounter(void* commandBuffer)
{
    return m_impl->counterBuffer != nullptr && m_impl->counterReadbackBuffer != nullptr &&
        m_impl->counterBuffer->encodeCopyTo(
            commandBuffer,
            *m_impl->counterReadbackBuffer,
            sizeof(uint32_t));
}

bool MetalGaussianBuffer::readGpuCounter()
{
    uint32_t count = 0;
    if (m_impl->counterReadbackBuffer == nullptr ||
        !m_impl->counterReadbackBuffer->read(&count, sizeof(count)) ||
        count > m_impl->capacity) {
        return false;
    }

    m_impl->count = count;
    return true;
}

void MetalGaussianBuffer::reset()
{
    m_impl->buffer.reset();
    m_impl->counterBuffer.reset();
    m_impl->counterReadbackBuffer.reset();
    m_impl->capacity = 0;
    m_impl->count = 0;
}

bool MetalGaussianBuffer::isValid() const
{
    return m_impl->buffer != nullptr && m_impl->buffer->isValid() &&
        m_impl->counterBuffer != nullptr && m_impl->counterBuffer->isValid() &&
        m_impl->counterReadbackBuffer != nullptr && m_impl->counterReadbackBuffer->isValid() &&
        m_impl->capacity > 0;
}

std::size_t MetalGaussianBuffer::capacity() const
{
    return m_impl->capacity;
}

uint32_t MetalGaussianBuffer::count() const
{
    return m_impl->count;
}

std::size_t MetalGaussianBuffer::sizeBytes() const
{
    return m_impl->buffer == nullptr ? 0 : m_impl->buffer->size();
}

void* MetalGaussianBuffer::nativeBuffer() const
{
    return m_impl->buffer == nullptr ? nullptr : m_impl->buffer->nativeBuffer();
}

void* MetalGaussianBuffer::nativeCounterBuffer() const
{
    return m_impl->counterBuffer == nullptr ? nullptr : m_impl->counterBuffer->nativeBuffer();
}

} // namespace mesh2splat::metal
