#pragma once

#include "MetalTexture.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalDeviceContext;

struct MetalClearColor {
    double red = 0.0;
    double green = 0.0;
    double blue = 0.0;
    double alpha = 1.0;
};

struct MetalRenderTargetDesc {
    uint32_t width = 0;
    uint32_t height = 0;
    bool colorEnabled = true;
    bool depthEnabled = false;
    MetalTextureFormat colorFormat = MetalTextureFormat::BGRA8Unorm;
    MetalTextureFormat depthFormat = MetalTextureFormat::Depth32Float;
    MetalClearColor clearColor{};
    double clearDepth = 1.0;
    std::string label;
};

class MetalRenderTarget {
public:
    explicit MetalRenderTarget(MetalDeviceContext& deviceContext);
    ~MetalRenderTarget();

    MetalRenderTarget(const MetalRenderTarget&) = delete;
    MetalRenderTarget& operator=(const MetalRenderTarget&) = delete;

    MetalRenderTarget(MetalRenderTarget&&) noexcept;
    MetalRenderTarget& operator=(MetalRenderTarget&&) noexcept;

    bool create(const MetalRenderTargetDesc& desc);
    bool resize(uint32_t width, uint32_t height);

    bool isValid() const;
    uint32_t width() const;
    uint32_t height() const;

    void* colorTexture() const;
    void* depthTexture() const;

    void* createRenderPassDescriptor(bool clearColor = true, bool clearDepth = true) const;
    static void releaseRenderPassDescriptor(void* descriptor);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
