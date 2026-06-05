#pragma once

#include "MetalTexture.hpp"

#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalDeviceContext;
class MetalShaderLibrary;

enum class MetalBlendMode {
    Disabled,
    Alpha,
    PremultipliedAlpha,
};

struct MetalRenderPipelineDesc {
    std::string label;
    std::string vertexFunction;
    std::string fragmentFunction;
    MetalTextureFormat colorFormat = MetalTextureFormat::BGRA8Unorm;
    MetalTextureFormat depthFormat = MetalTextureFormat::Depth32Float;
    bool depthEnabled = false;
    MetalBlendMode blendMode = MetalBlendMode::Disabled;
};

struct MetalComputePipelineDesc {
    std::string label;
    std::string function;
};

class MetalPipelineCache {
public:
    explicit MetalPipelineCache(MetalDeviceContext& deviceContext);
    ~MetalPipelineCache();

    MetalPipelineCache(const MetalPipelineCache&) = delete;
    MetalPipelineCache& operator=(const MetalPipelineCache&) = delete;

    void* renderPipeline(
        MetalShaderLibrary& library,
        const MetalRenderPipelineDesc& desc,
        std::string* errorMessage = nullptr);

    void* computePipeline(
        MetalShaderLibrary& library,
        const MetalComputePipelineDesc& desc,
        std::string* errorMessage = nullptr);

    void clear();

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
