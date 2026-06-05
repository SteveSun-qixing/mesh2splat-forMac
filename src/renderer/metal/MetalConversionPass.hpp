#pragma once

#include <memory>

namespace mesh2splat::metal {

class MetalGaussianBuffer;
class MetalPipelineCache;
class MetalRenderStateCache;
class MetalSceneResources;
class MetalShaderLibrary;

class MetalConversionPass {
public:
    MetalConversionPass();
    ~MetalConversionPass();

    MetalConversionPass(const MetalConversionPass&) = delete;
    MetalConversionPass& operator=(const MetalConversionPass&) = delete;

    MetalConversionPass(MetalConversionPass&&) noexcept;
    MetalConversionPass& operator=(MetalConversionPass&&) noexcept;

    bool initialize(
        MetalShaderLibrary& shaderLibrary,
        MetalPipelineCache& pipelineCache,
        MetalRenderStateCache& renderStateCache);
    bool isReady() const;
    bool encode(void* commandBuffer, const MetalSceneResources& sceneResources, MetalGaussianBuffer& gaussianBuffer) const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
