#pragma once

#include "MetalTexture.hpp"

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

enum class MetalStencilOperation : uint8_t {
    Keep,
    Zero,
    Replace,
    IncrementClamp,
    DecrementClamp,
    Invert,
    IncrementWrap,
    DecrementWrap,
};

enum class MetalRenderBlendFactor : uint8_t {
    Zero,
    One,
    SourceColor,
    OneMinusSourceColor,
    SourceAlpha,
    OneMinusSourceAlpha,
    DestinationColor,
    OneMinusDestinationColor,
    DestinationAlpha,
    OneMinusDestinationAlpha,
    SourceAlphaSaturated,
    BlendColor,
    OneMinusBlendColor,
    BlendAlpha,
    OneMinusBlendAlpha,
};

enum class MetalRenderBlendOperation : uint8_t {
    Add,
    Subtract,
    ReverseSubtract,
    Min,
    Max,
};

enum class MetalColorWriteMask : uint8_t {
    None = 0,
    Red = 1 << 0,
    Green = 1 << 1,
    Blue = 1 << 2,
    Alpha = 1 << 3,
    All = 0x0f,
};

inline MetalColorWriteMask operator|(MetalColorWriteMask lhs, MetalColorWriteMask rhs)
{
    return static_cast<MetalColorWriteMask>(static_cast<uint8_t>(lhs) | static_cast<uint8_t>(rhs));
}

struct MetalSamplerDesc {
    MetalSamplerFilter minFilter = MetalSamplerFilter::Linear;
    MetalSamplerFilter magFilter = MetalSamplerFilter::Linear;
    MetalSamplerFilter mipFilter = MetalSamplerFilter::Linear;
    MetalSamplerAddressMode addressU = MetalSamplerAddressMode::Repeat;
    MetalSamplerAddressMode addressV = MetalSamplerAddressMode::Repeat;
    MetalSamplerAddressMode addressW = MetalSamplerAddressMode::Repeat;
    uint32_t maxAnisotropy = 1;
    bool normalizedCoordinates = true;
    std::string label;
};

struct MetalStencilFaceDesc {
    MetalCompareFunction compareFunction = MetalCompareFunction::Always;
    MetalStencilOperation stencilFailureOperation = MetalStencilOperation::Keep;
    MetalStencilOperation depthFailureOperation = MetalStencilOperation::Keep;
    MetalStencilOperation depthStencilPassOperation = MetalStencilOperation::Keep;
    uint32_t readMask = 0xff;
    uint32_t writeMask = 0xff;
};

struct MetalDepthStencilDesc {
    bool depthTestEnabled = true;
    bool depthWriteEnabled = true;
    MetalCompareFunction depthCompareFunction = MetalCompareFunction::LessEqual;
    bool stencilEnabled = false;
    MetalStencilFaceDesc frontFaceStencil;
    MetalStencilFaceDesc backFaceStencil;
    std::string label;
};

struct MetalBlendAttachmentDesc {
    bool blendingEnabled = false;
    MetalRenderBlendFactor sourceRGBBlendFactor = MetalRenderBlendFactor::One;
    MetalRenderBlendFactor destinationRGBBlendFactor = MetalRenderBlendFactor::Zero;
    MetalRenderBlendOperation rgbBlendOperation = MetalRenderBlendOperation::Add;
    MetalRenderBlendFactor sourceAlphaBlendFactor = MetalRenderBlendFactor::One;
    MetalRenderBlendFactor destinationAlphaBlendFactor = MetalRenderBlendFactor::Zero;
    MetalRenderBlendOperation alphaBlendOperation = MetalRenderBlendOperation::Add;
    MetalColorWriteMask writeMask = MetalColorWriteMask::All;
};

struct MetalColorAttachmentStateDesc {
    bool enabled = true;
    MetalTextureFormat pixelFormat = MetalTextureFormat::BGRA8Unorm;
    MetalBlendAttachmentDesc blend;
    std::string label;
};

struct MetalRenderAttachmentStateDesc {
    std::string label;
    MetalColorAttachmentStateDesc colorAttachment0;
    bool depthAttachmentEnabled = false;
    MetalTextureFormat depthAttachmentFormat = MetalTextureFormat::Depth32Float;
    uint32_t rasterSampleCount = 1;
    bool alphaToCoverageEnabled = false;
    bool alphaToOneEnabled = false;
    bool rasterizationEnabled = true;
    std::string variantKey;
};

struct MetalRenderStateCacheDiagnostics {
    std::size_t samplerHits = 0;
    std::size_t samplerMisses = 0;
    std::size_t depthStencilHits = 0;
    std::size_t depthStencilMisses = 0;
    std::size_t attachmentKeyRequests = 0;
    std::size_t samplerStateCount = 0;
    std::size_t depthStencilStateCount = 0;
    std::string lastEvent;
};

class MetalRenderStateCache {
public:
    explicit MetalRenderStateCache(MetalDeviceContext& deviceContext);
    ~MetalRenderStateCache();

    MetalRenderStateCache(const MetalRenderStateCache&) = delete;
    MetalRenderStateCache& operator=(const MetalRenderStateCache&) = delete;

    MetalRenderStateCache(MetalRenderStateCache&&) noexcept;
    MetalRenderStateCache& operator=(MetalRenderStateCache&&) noexcept;

    void* samplerState(const MetalSamplerDesc& desc, std::string* diagnostic = nullptr);
    void* depthStencilState(const MetalDepthStencilDesc& desc, std::string* diagnostic = nullptr);

    std::string colorAttachmentKey(const MetalColorAttachmentStateDesc& desc);
    std::string renderAttachmentKey(const MetalRenderAttachmentStateDesc& desc);
    std::string colorAttachmentDescription(const MetalColorAttachmentStateDesc& desc) const;
    std::string renderAttachmentDescription(const MetalRenderAttachmentStateDesc& desc) const;
    bool applyColorAttachmentState(
        void* colorAttachmentDescriptor,
        const MetalColorAttachmentStateDesc& desc,
        std::string* errorMessage = nullptr) const;

    void clear();
    void reset();
    void resetDiagnostics();

    std::size_t samplerStateCount() const;
    std::size_t depthStencilStateCount() const;
    MetalRenderStateCacheDiagnostics diagnostics() const;
    const std::string& lastDiagnostic() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
