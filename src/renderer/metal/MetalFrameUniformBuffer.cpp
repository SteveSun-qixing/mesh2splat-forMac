#include "MetalFrameUniformBuffer.hpp"

#include "MetalBuffer.hpp"
#include "MetalDeviceContext.hpp"

#include <algorithm>
#include <limits>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::metal {

struct MetalFrameUniformBuffer::Impl {
    struct FrameState {
        uint64_t uploadSerial = 0;
        uint64_t submissionSerial = 0;
        uint64_t completionSerial = 0;
        bool isInFlight = false;
        bool hasUpload = false;
        std::string debugLabel;
    };

    MetalDeviceContext* deviceContext = nullptr;
    std::vector<std::unique_ptr<MetalBuffer>> buffers;
    std::vector<FrameState> frames;
    uint32_t frameCount = 0;
    uint64_t uploadSerial = 0;
    uint64_t submissionSerial = 0;
    uint64_t completionSerial = 0;
    std::size_t overwrittenInFlightFrameCount = 0;
    MetalFrameUniformBuffer::FrameBinding lastBinding;
    std::string debugLabel;
    std::string lastDiagnostic;
};

MetalFrameUniformBuffer::MetalFrameUniformBuffer(MetalDeviceContext& deviceContext, uint32_t frameCount)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = &deviceContext;
    m_impl->frameCount = std::max<uint32_t>(frameCount, 1);
    m_impl->debugLabel = "MetalFrameUniformBuffer";
    m_impl->lastDiagnostic = "MetalFrameUniformBuffer is not initialized.";
}

MetalFrameUniformBuffer::~MetalFrameUniformBuffer() = default;

MetalFrameUniformBuffer::MetalFrameUniformBuffer(MetalFrameUniformBuffer&&) noexcept = default;

MetalFrameUniformBuffer& MetalFrameUniformBuffer::operator=(MetalFrameUniformBuffer&&) noexcept = default;

bool MetalFrameUniformBuffer::initialize(const char* label)
{
    if (m_impl->deviceContext == nullptr) {
        m_impl->lastDiagnostic = "MetalFrameUniformBuffer initialization failed: device context is null.";
        return false;
    }

    m_impl->debugLabel = label != nullptr ? label : "Frame Uniforms";

    std::vector<std::unique_ptr<MetalBuffer>> buffers;
    buffers.reserve(m_impl->frameCount);
    std::vector<Impl::FrameState> frames;
    frames.reserve(m_impl->frameCount);

    const core::FrameUniforms defaults = core::makeDefaultFrameUniforms(0, 0);

    for (uint32_t frameIndex = 0; frameIndex < m_impl->frameCount; ++frameIndex) {
        auto buffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
        const std::string bufferLabel = m_impl->debugLabel + " " + std::to_string(frameIndex);
        if (!buffer->createSharedWriteCombined(uniformSize(), &defaults, bufferLabel.c_str())) {
            std::ostringstream stream;
            stream << "MetalFrameUniformBuffer initialization failed: frameIndex=" << frameIndex
                   << " size=" << uniformSize()
                   << " label='" << bufferLabel << "'";
            m_impl->lastDiagnostic = stream.str();
            return false;
        }
        buffers.push_back(std::move(buffer));

        Impl::FrameState frame;
        frame.debugLabel = bufferLabel;
        frames.push_back(std::move(frame));
    }

    m_impl->buffers = std::move(buffers);
    m_impl->frames = std::move(frames);
    m_impl->uploadSerial = 0;
    m_impl->submissionSerial = 0;
    m_impl->completionSerial = 0;
    m_impl->overwrittenInFlightFrameCount = 0;
    m_impl->lastBinding = {};
    std::ostringstream stream;
    stream << m_impl->debugLabel
           << " initialized: frameCount=" << m_impl->frameCount
           << " uniformSize=" << uniformSize()
           << " uniformAlignment=" << uniformAlignment()
           << " frameStride=" << frameStride()
           << " totalSize=" << sizeBytes();
    m_impl->lastDiagnostic = stream.str();
    return true;
}

bool MetalFrameUniformBuffer::update(uint32_t frameIndex, const core::FrameUniforms& uniforms)
{
    return update(frameIndex, uniforms, nullptr);
}

bool MetalFrameUniformBuffer::update(uint32_t frameIndex, const core::FrameUniforms& uniforms, const char* debugLabel)
{
    if (m_impl->buffers.empty()) {
        m_impl->lastDiagnostic = "MetalFrameUniformBuffer update rejected: buffers are not initialized.";
        return false;
    }

    const FrameBinding binding = frameBinding(frameIndex);
    MetalBuffer* target = m_impl->buffers[binding.frameIndex].get();
    const bool updated =
        target != nullptr && target->update(&uniforms, uniformSize(), binding.offset);

    if (updated && binding.frameIndex < m_impl->frames.size()) {
        Impl::FrameState& frame = m_impl->frames[binding.frameIndex];
        if (frame.isInFlight) {
            ++m_impl->overwrittenInFlightFrameCount;
        }
        frame.uploadSerial = ++m_impl->uploadSerial;
        frame.hasUpload = true;
        frame.isInFlight = false;
        frame.submissionSerial = 0;
        frame.completionSerial = 0;
        if (debugLabel != nullptr) {
            frame.debugLabel = debugLabel;
        }
    }

    m_impl->lastBinding = frameBinding(frameIndex);
    std::ostringstream stream;
    stream << m_impl->debugLabel
           << " update " << (updated ? "ok" : "failed")
           << ": requestedFrameIndex=" << frameIndex
           << " frameIndex=" << m_impl->lastBinding.frameIndex
           << " wrapped=" << (m_impl->lastBinding.isWrapped ? "yes" : "no")
           << " offset=" << m_impl->lastBinding.offset
           << " size=" << m_impl->lastBinding.size
           << " stride=" << frameStride()
           << " frameCount=" << m_impl->frameCount
           << " uploadSerial=" << m_impl->lastBinding.uploadSerial
           << " overwrittenInFlightFrames=" << m_impl->overwrittenInFlightFrameCount;
    m_impl->lastDiagnostic = stream.str();
    return updated;
}

bool MetalFrameUniformBuffer::updateViewport(
    uint32_t frameIndex,
    const core::FrameUniforms& cameraUniforms,
    const core::ViewportState& viewport)
{
    return updateViewport(frameIndex, cameraUniforms, viewport, nullptr);
}

bool MetalFrameUniformBuffer::updateViewport(
    uint32_t frameIndex,
    const core::FrameUniforms& cameraUniforms,
    const core::ViewportState& viewport,
    const char* debugLabel)
{
    core::FrameUniforms uniforms = cameraUniforms;
    core::applyViewportState(uniforms, viewport);
    uniforms.frameIndex = normalizeFrameIndex(frameIndex);
    return update(frameIndex, uniforms, debugLabel);
}

bool MetalFrameUniformBuffer::updateSnapshot(
    uint32_t frameIndex,
    const core::FrameUniforms& cameraUniforms,
    const core::FrameInputSnapshot& snapshot)
{
    return updateSnapshot(frameIndex, cameraUniforms, snapshot, nullptr);
}

bool MetalFrameUniformBuffer::updateSnapshot(
    uint32_t frameIndex,
    const core::FrameUniforms& cameraUniforms,
    const core::FrameInputSnapshot& snapshot,
    const char* debugLabel)
{
    core::FrameUniforms uniforms = cameraUniforms;
    core::applyFrameInputSnapshot(uniforms, snapshot);
    uniforms.frameIndex = normalizeFrameIndex(frameIndex);
    return update(frameIndex, uniforms, debugLabel);
}

void MetalFrameUniformBuffer::markFrameSubmitted(uint32_t frameIndex, uint64_t submissionSerial)
{
    if (m_impl->frames.empty()) {
        m_impl->lastDiagnostic = "MetalFrameUniformBuffer submit ignored: buffers are not initialized.";
        return;
    }

    const uint32_t normalizedFrameIndex = normalizeFrameIndex(frameIndex);
    Impl::FrameState& frame = m_impl->frames[normalizedFrameIndex];
    const uint64_t resolvedSerial = submissionSerial == 0 ? ++m_impl->submissionSerial : submissionSerial;
    m_impl->submissionSerial = std::max(m_impl->submissionSerial, resolvedSerial);
    frame.submissionSerial = resolvedSerial;
    frame.completionSerial = 0;
    frame.isInFlight = true;
    m_impl->lastBinding = frameBinding(normalizedFrameIndex);
    m_impl->lastDiagnostic = describeFrame(normalizedFrameIndex);
}

void MetalFrameUniformBuffer::markFrameCompleted(uint32_t frameIndex, uint64_t completionSerial)
{
    if (m_impl->frames.empty()) {
        m_impl->lastDiagnostic = "MetalFrameUniformBuffer completion ignored: buffers are not initialized.";
        return;
    }

    const uint32_t normalizedFrameIndex = normalizeFrameIndex(frameIndex);
    Impl::FrameState& frame = m_impl->frames[normalizedFrameIndex];
    const uint64_t nextCompletionSerial = m_impl->completionSerial == std::numeric_limits<uint64_t>::max() ?
        m_impl->completionSerial :
        m_impl->completionSerial + 1;
    const uint64_t resolvedSerial = completionSerial == 0 ?
        std::max(frame.submissionSerial, std::max(m_impl->submissionSerial, nextCompletionSerial)) :
        completionSerial;
    m_impl->completionSerial = std::max(m_impl->completionSerial, resolvedSerial);
    frame.completionSerial = resolvedSerial;
    frame.isInFlight = false;
    m_impl->lastBinding = frameBinding(normalizedFrameIndex);
    m_impl->lastDiagnostic = describeFrame(normalizedFrameIndex);
}

void MetalFrameUniformBuffer::resetFrame(uint32_t frameIndex)
{
    if (m_impl->frames.empty()) {
        m_impl->lastDiagnostic = "MetalFrameUniformBuffer reset ignored: buffers are not initialized.";
        return;
    }

    const uint32_t normalizedFrameIndex = normalizeFrameIndex(frameIndex);
    Impl::FrameState& frame = m_impl->frames[normalizedFrameIndex];
    frame.uploadSerial = 0;
    frame.submissionSerial = 0;
    frame.completionSerial = 0;
    frame.isInFlight = false;
    frame.hasUpload = false;
    frame.debugLabel = m_impl->debugLabel.empty() ?
        std::string{} :
        m_impl->debugLabel + " " + std::to_string(normalizedFrameIndex);
    m_impl->lastBinding = frameBinding(normalizedFrameIndex);
    m_impl->lastDiagnostic = describeFrame(normalizedFrameIndex);
}

bool MetalFrameUniformBuffer::isValid() const
{
    if (m_impl->buffers.size() != m_impl->frameCount || m_impl->frames.size() != m_impl->frameCount) {
        return false;
    }

    for (const std::unique_ptr<MetalBuffer>& buffer : m_impl->buffers) {
        if (buffer == nullptr || !buffer->isValid() || buffer->size() < uniformSize()) {
            return false;
        }
    }

    return true;
}

MetalFrameUniformBuffer::FrameBinding MetalFrameUniformBuffer::frameBinding(uint32_t frameIndex) const
{
    FrameBinding binding;
    binding.requestedFrameIndex = frameIndex;
    binding.size = uniformSize();
    binding.stride = frameStride();
    binding.alignment = uniformAlignment();

    if (m_impl->buffers.empty()) {
        return binding;
    }

    const uint32_t normalizedFrameIndex = normalizeFrameIndex(frameIndex);
    const std::unique_ptr<MetalBuffer>& target = m_impl->buffers[normalizedFrameIndex];
    const Impl::FrameState* frameState =
        normalizedFrameIndex < m_impl->frames.size() ? &m_impl->frames[normalizedFrameIndex] : nullptr;
    const std::size_t targetSize = target == nullptr ? 0 : target->size();
    binding.frameIndex = normalizedFrameIndex;
    binding.nativeBuffer = target == nullptr ? nullptr : target->nativeBuffer();
    binding.offset = 0;
    binding.isValid = target != nullptr && target->isValid() && targetSize >= uniformSize();
    binding.isWrapped = normalizedFrameIndex != frameIndex;
    binding.bufferSize = targetSize;
    binding.uploadSerial = frameState == nullptr ? 0 : frameState->uploadSerial;
    binding.submissionSerial = frameState == nullptr ? 0 : frameState->submissionSerial;
    binding.completionSerial = frameState == nullptr ? 0 : frameState->completionSerial;
    binding.isInFlight = frameState != nullptr && frameState->isInFlight;
    binding.hasUpload = frameState != nullptr && frameState->hasUpload;
    binding.debugLabel = frameState == nullptr ? std::string{} : frameState->debugLabel;
    return binding;
}

uint32_t MetalFrameUniformBuffer::normalizeFrameIndex(uint32_t frameIndex) const
{
    return m_impl->buffers.empty() ? 0 : static_cast<uint32_t>(frameIndex % m_impl->buffers.size());
}

bool MetalFrameUniformBuffer::isValidFrameIndex(uint32_t frameIndex) const
{
    return frameIndex < m_impl->frameCount;
}

bool MetalFrameUniformBuffer::isFrameInFlight(uint32_t frameIndex) const
{
    if (m_impl->frames.empty()) {
        return false;
    }

    return m_impl->frames[normalizeFrameIndex(frameIndex)].isInFlight;
}

std::size_t MetalFrameUniformBuffer::inFlightFrameCount() const
{
    std::size_t count = 0;
    for (const Impl::FrameState& frame : m_impl->frames) {
        if (frame.isInFlight) {
            ++count;
        }
    }
    return count;
}

uint32_t MetalFrameUniformBuffer::frameCount() const
{
    return m_impl->frameCount;
}

std::size_t MetalFrameUniformBuffer::frameStride() const
{
    return alignedUniformSize();
}

std::size_t MetalFrameUniformBuffer::frameOffset(uint32_t frameIndex) const
{
    (void)frameIndex;
    return 0;
}

std::size_t MetalFrameUniformBuffer::bufferSize() const
{
    return uniformSize();
}

std::size_t MetalFrameUniformBuffer::sizeBytes() const
{
    std::size_t total = 0;
    for (const std::unique_ptr<MetalBuffer>& buffer : m_impl->buffers) {
        total += buffer == nullptr ? 0 : buffer->size();
    }
    return total;
}

void* MetalFrameUniformBuffer::buffer(uint32_t frameIndex) const
{
    return frameBinding(frameIndex).nativeBuffer;
}

const std::string& MetalFrameUniformBuffer::lastDiagnostic() const
{
    return m_impl->lastDiagnostic;
}

uint64_t MetalFrameUniformBuffer::lastUploadSerial() const
{
    return m_impl->uploadSerial;
}

MetalFrameUniformBuffer::Diagnostics MetalFrameUniformBuffer::diagnostics() const
{
    Diagnostics result;
    result.frameCount = frameCount();
    result.uniformSize = uniformSize();
    result.uniformAlignment = uniformAlignment();
    result.frameStride = frameStride();
    result.totalSizeBytes = sizeBytes();
    result.inFlightFrameCount = inFlightFrameCount();
    for (const Impl::FrameState& frame : m_impl->frames) {
        if (frame.hasUpload) {
            ++result.uploadedFrameCount;
        }
    }
    result.overwrittenInFlightFrameCount = m_impl->overwrittenInFlightFrameCount;
    result.lastUploadSerial = m_impl->uploadSerial;
    result.lastSubmissionSerial = m_impl->submissionSerial;
    result.lastCompletionSerial = m_impl->completionSerial;
    result.lastBinding = m_impl->lastBinding.isValid || m_impl->lastBinding.hasUpload ?
        m_impl->lastBinding :
        frameBinding(0);
    result.debugLabel = m_impl->debugLabel;
    result.lastMessage = m_impl->lastDiagnostic;
    return result;
}

void MetalFrameUniformBuffer::setDebugLabel(const char* label)
{
    m_impl->debugLabel = label != nullptr ? label : std::string{};
    m_impl->lastDiagnostic = describeFrame(0);
}

const std::string& MetalFrameUniformBuffer::debugLabel() const
{
    return m_impl->debugLabel;
}

std::string MetalFrameUniformBuffer::describeFrame(uint32_t frameIndex) const
{
    const FrameBinding binding = frameBinding(frameIndex);
    std::ostringstream stream;
    stream << m_impl->debugLabel
           << " frame requestedFrameIndex=" << binding.requestedFrameIndex
           << " frameIndex=" << binding.frameIndex
           << " wrapped=" << (binding.isWrapped ? "yes" : "no")
           << " offset=" << binding.offset
           << " size=" << binding.size
           << " bufferSize=" << binding.bufferSize
           << " stride=" << frameStride()
           << " alignment=" << binding.alignment
           << " frameCount=" << frameCount()
           << " valid=" << (binding.isValid ? "yes" : "no")
           << " hasUpload=" << (binding.hasUpload ? "yes" : "no")
           << " inFlight=" << (binding.isInFlight ? "yes" : "no")
           << " uploadSerial=" << binding.uploadSerial
           << " submissionSerial=" << binding.submissionSerial
           << " completionSerial=" << binding.completionSerial;
    if (!binding.debugLabel.empty()) {
        stream << " label='" << binding.debugLabel << "'";
    }
    return stream.str();
}

std::size_t MetalFrameUniformBuffer::uniformAlignment()
{
    return alignof(core::FrameUniforms);
}

std::size_t MetalFrameUniformBuffer::uniformSize()
{
    return sizeof(core::FrameUniforms);
}

std::size_t MetalFrameUniformBuffer::alignedUniformSize(std::size_t alignment)
{
    const std::size_t resolvedAlignment = alignment == 0 ? uniformAlignment() : alignment;
    if (resolvedAlignment <= 1) {
        return uniformSize();
    }

    const std::size_t remainder = uniformSize() % resolvedAlignment;
    return remainder == 0 ? uniformSize() : uniformSize() + (resolvedAlignment - remainder);
}

} // namespace mesh2splat::metal
