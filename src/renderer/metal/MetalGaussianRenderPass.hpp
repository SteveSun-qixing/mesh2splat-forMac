#pragma once

#include "MetalTexture.hpp"

#include <memory>

namespace mesh2splat::metal {

class MetalGaussianBuffer;
class MetalGaussianSortBuffer;
class MetalDeviceContext;
class MetalPipelineCache;
class MetalRenderStateCache;
class MetalShaderLibrary;

class MetalGaussianRenderPass {
public:
    explicit MetalGaussianRenderPass(MetalDeviceContext& deviceContext);
    ~MetalGaussianRenderPass();

    MetalGaussianRenderPass(const MetalGaussianRenderPass&) = delete;
    MetalGaussianRenderPass& operator=(const MetalGaussianRenderPass&) = delete;

    MetalGaussianRenderPass(MetalGaussianRenderPass&&) noexcept;
    MetalGaussianRenderPass& operator=(MetalGaussianRenderPass&&) noexcept;

    bool initialize(
        MetalShaderLibrary& shaderLibrary,
        MetalPipelineCache& pipelineCache,
        MetalRenderStateCache& renderStateCache,
        MetalTextureFormat colorFormat,
        MetalTextureFormat depthFormat);

    bool isReady() const;
    void encode(
        void* renderCommandEncoder,
        const MetalGaussianBuffer& gaussianBuffer,
        const MetalGaussianSortBuffer& sortBuffer,
        void* frameUniformBuffer) const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
