#pragma once

#include "MetalTexture.hpp"

#include <cstddef>
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

enum class MetalRenderTargetRole {
    Unknown,
    Main,
    Depth,
    Offscreen,
};

struct MetalRenderTargetSize {
    uint32_t width = 0;
    uint32_t height = 0;
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
    MetalRenderTargetRole role = MetalRenderTargetRole::Unknown;
    std::string label;
};

struct MetalRenderTargetDiagnostics {
    bool valid = false;
    MetalRenderTargetRole role = MetalRenderTargetRole::Unknown;
    MetalRenderTargetSize size{};
    bool colorEnabled = false;
    bool depthEnabled = false;
    MetalTextureFormat colorFormat = MetalTextureFormat::BGRA8Unorm;
    MetalTextureFormat depthFormat = MetalTextureFormat::Depth32Float;
    std::size_t colorSizeBytes = 0;
    std::size_t depthSizeBytes = 0;
    std::size_t totalSizeBytes = 0;
    MetalClearColor clearColor{};
    double clearDepth = 1.0;
    std::string debugLabel;
    std::string colorDebugLabel;
    std::string depthDebugLabel;
    std::string lastErrorMessage;
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
    bool resize(const MetalRenderTargetDesc& desc);
    MetalRenderTargetDesc resizeDescriptor(uint32_t width, uint32_t height) const;

    bool isValid() const;
    uint32_t width() const;
    uint32_t height() const;
    MetalRenderTargetSize size() const;
    const MetalRenderTargetDesc& descriptor() const;
    MetalRenderTargetRole role() const;
    bool colorEnabled() const;
    bool depthEnabled() const;
    MetalTextureFormat colorFormat() const;
    MetalTextureFormat depthFormat() const;
    std::size_t colorSizeBytes() const;
    std::size_t depthSizeBytes() const;
    std::size_t sizeBytes() const;
    MetalClearColor clearColorValue() const;
    double clearDepthValue() const;
    const std::string& debugLabel() const;
    std::string colorDebugLabel() const;
    std::string depthDebugLabel() const;
    const std::string& lastErrorMessage() const;
    MetalRenderTargetDiagnostics diagnostics() const;

    void* colorTexture() const;
    void* depthTexture() const;

    void* createRenderPassDescriptor(bool clearColor = true, bool clearDepth = true) const;
    static void releaseRenderPassDescriptor(void* descriptor);
    static const char* roleName(MetalRenderTargetRole role);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
