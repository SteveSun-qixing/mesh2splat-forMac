#pragma once

#include "MetalTexture.hpp"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace mesh2splat::metal {

class MetalDeviceContext;
class MetalShaderLibrary;

enum class MetalBlendMode {
    Disabled,
    Alpha,
    PremultipliedAlpha,
    Additive,
};

struct MetalRenderPipelineDesc {
    std::string label;
    std::string vertexFunction;
    std::string fragmentFunction;
    MetalTextureFormat colorFormat = MetalTextureFormat::BGRA8Unorm;
    MetalTextureFormat depthFormat = MetalTextureFormat::Depth32Float;
    bool depthEnabled = false;
    MetalBlendMode blendMode = MetalBlendMode::Disabled;
    std::string variantKey;
    uint32_t rasterSampleCount = 1;
};

struct MetalComputePipelineDesc {
    std::string label;
    std::string function;
    std::string variantKey;
    uint32_t maxTotalThreadsPerThreadgroup = 0;
    bool threadGroupSizeIsMultipleOfThreadExecutionWidth = false;
    bool supportIndirectCommandBuffers = false;
};

class MetalPipelineCache {
public:
    explicit MetalPipelineCache(MetalDeviceContext& deviceContext);
    ~MetalPipelineCache();

    MetalPipelineCache(const MetalPipelineCache&) = delete;
    MetalPipelineCache& operator=(const MetalPipelineCache&) = delete;

    static MetalRenderPipelineDesc meshPipelineDesc(
        MetalTextureFormat colorFormat,
        MetalTextureFormat depthFormat,
        uint32_t rasterSampleCount = 1);
    static MetalRenderPipelineDesc gaussianPipelineDesc(
        MetalTextureFormat colorFormat,
        MetalTextureFormat depthFormat,
        uint32_t rasterSampleCount = 1);
    static MetalComputePipelineDesc conversionPipelineDesc();
    static std::vector<MetalComputePipelineDesc> sortPipelineDescs();

    void* renderPipeline(
        MetalShaderLibrary& library,
        const MetalRenderPipelineDesc& desc,
        std::string* errorMessage = nullptr);

    void* computePipeline(
        MetalShaderLibrary& library,
        const MetalComputePipelineDesc& desc,
        std::string* errorMessage = nullptr);

    void clear();
    bool rebuild(
        MetalShaderLibrary& library,
        const std::vector<MetalRenderPipelineDesc>& renderPipelineDescs,
        const std::vector<MetalComputePipelineDesc>& computePipelineDescs,
        std::string* errorMessage = nullptr);
    bool rebuildStandardPipelines(
        MetalShaderLibrary& library,
        MetalTextureFormat colorFormat,
        MetalTextureFormat depthFormat,
        uint32_t rasterSampleCount = 1,
        std::string* errorMessage = nullptr);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
