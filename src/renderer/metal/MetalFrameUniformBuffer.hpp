#pragma once

#include "core/FrameData.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>

namespace mesh2splat::metal {

class MetalDeviceContext;

class MetalFrameUniformBuffer {
public:
    explicit MetalFrameUniformBuffer(MetalDeviceContext& deviceContext, uint32_t frameCount = 3);
    ~MetalFrameUniformBuffer();

    MetalFrameUniformBuffer(const MetalFrameUniformBuffer&) = delete;
    MetalFrameUniformBuffer& operator=(const MetalFrameUniformBuffer&) = delete;

    MetalFrameUniformBuffer(MetalFrameUniformBuffer&&) noexcept;
    MetalFrameUniformBuffer& operator=(MetalFrameUniformBuffer&&) noexcept;

    bool initialize(const char* label = nullptr);
    bool update(uint32_t frameIndex, const core::FrameUniforms& uniforms);

    bool isValid() const;
    uint32_t frameCount() const;
    std::size_t bufferSize() const;
    void* buffer(uint32_t frameIndex) const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
