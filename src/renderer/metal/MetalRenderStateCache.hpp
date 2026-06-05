#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalDeviceContext;

enum class MetalSamplerFilter : uint8_t {
    Nearest,
    Linear,
};

enum class MetalSamplerAddressMode : uint8_t {
    ClampToEdge,
    Repeat,
    MirrorRepeat,
};

enum class MetalCompareFunction : uint8_t {
    Never,
    Less,
    LessEqual,
    Equal,
    Greater,
    GreaterEqual,
    Always,
};

struct MetalSamplerDesc {
    MetalSamplerFilter minFilter = MetalSamplerFilter::Linear;
    MetalSamplerFilter magFilter = MetalSamplerFilter::Linear;
    MetalSamplerFilter mipFilter = MetalSamplerFilter::Linear;
    MetalSamplerAddressMode addressU = MetalSamplerAddressMode::Repeat;
    MetalSamplerAddressMode addressV = MetalSamplerAddressMode::Repeat;
    MetalSamplerAddressMode addressW = MetalSamplerAddressMode::Repeat;
    std::string label;
};

struct MetalDepthStencilDesc {
    bool depthTestEnabled = true;
    bool depthWriteEnabled = true;
    MetalCompareFunction depthCompareFunction = MetalCompareFunction::LessEqual;
    std::string label;
};

class MetalRenderStateCache {
public:
    explicit MetalRenderStateCache(MetalDeviceContext& deviceContext);
    ~MetalRenderStateCache();

    MetalRenderStateCache(const MetalRenderStateCache&) = delete;
    MetalRenderStateCache& operator=(const MetalRenderStateCache&) = delete;

    MetalRenderStateCache(MetalRenderStateCache&&) noexcept;
    MetalRenderStateCache& operator=(MetalRenderStateCache&&) noexcept;

    void* samplerState(const MetalSamplerDesc& desc);
    void* depthStencilState(const MetalDepthStencilDesc& desc);
    void clear();

    std::size_t samplerStateCount() const;
    std::size_t depthStencilStateCount() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
