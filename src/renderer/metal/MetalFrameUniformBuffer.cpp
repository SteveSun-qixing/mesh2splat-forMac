#include "MetalFrameUniformBuffer.hpp"

#include "MetalBuffer.hpp"
#include "MetalDeviceContext.hpp"

#include <algorithm>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::metal {

struct MetalFrameUniformBuffer::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    std::vector<std::unique_ptr<MetalBuffer>> buffers;
    uint32_t frameCount = 0;
};

MetalFrameUniformBuffer::MetalFrameUniformBuffer(MetalDeviceContext& deviceContext, uint32_t frameCount)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = &deviceContext;
    m_impl->frameCount = std::max<uint32_t>(frameCount, 1);
}

MetalFrameUniformBuffer::~MetalFrameUniformBuffer() = default;

MetalFrameUniformBuffer::MetalFrameUniformBuffer(MetalFrameUniformBuffer&&) noexcept = default;

MetalFrameUniformBuffer& MetalFrameUniformBuffer::operator=(MetalFrameUniformBuffer&&) noexcept = default;

bool MetalFrameUniformBuffer::initialize(const char* label)
{
    if (m_impl->deviceContext == nullptr) {
        return false;
    }

    std::vector<std::unique_ptr<MetalBuffer>> buffers;
    buffers.reserve(m_impl->frameCount);

    const core::FrameUniforms defaults = core::makeDefaultFrameUniforms(0, 0);
    const std::string baseLabel = label != nullptr ? label : "Frame Uniforms";

    for (uint32_t frameIndex = 0; frameIndex < m_impl->frameCount; ++frameIndex) {
        auto buffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
        const std::string bufferLabel = baseLabel + " " + std::to_string(frameIndex);
        if (!buffer->createShared(sizeof(core::FrameUniforms), &defaults, bufferLabel.c_str())) {
            return false;
        }
        buffers.push_back(std::move(buffer));
    }

    m_impl->buffers = std::move(buffers);
    return true;
}

bool MetalFrameUniformBuffer::update(uint32_t frameIndex, const core::FrameUniforms& uniforms)
{
    if (m_impl->buffers.empty()) {
        return false;
    }

    MetalBuffer* target = m_impl->buffers[frameIndex % m_impl->buffers.size()].get();
    return target != nullptr && target->update(&uniforms, sizeof(core::FrameUniforms));
}

bool MetalFrameUniformBuffer::isValid() const
{
    if (m_impl->buffers.size() != m_impl->frameCount) {
        return false;
    }

    for (const std::unique_ptr<MetalBuffer>& buffer : m_impl->buffers) {
        if (buffer == nullptr || !buffer->isValid() || buffer->size() != sizeof(core::FrameUniforms)) {
            return false;
        }
    }

    return true;
}

uint32_t MetalFrameUniformBuffer::frameCount() const
{
    return m_impl->frameCount;
}

std::size_t MetalFrameUniformBuffer::bufferSize() const
{
    return sizeof(core::FrameUniforms);
}

void* MetalFrameUniformBuffer::buffer(uint32_t frameIndex) const
{
    if (m_impl->buffers.empty()) {
        return nullptr;
    }

    const std::unique_ptr<MetalBuffer>& target = m_impl->buffers[frameIndex % m_impl->buffers.size()];
    return target == nullptr ? nullptr : target->nativeBuffer();
}

} // namespace mesh2splat::metal
