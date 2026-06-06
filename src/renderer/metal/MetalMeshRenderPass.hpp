#pragma once

#include "MetalTexture.hpp"

#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalDeviceContext;
class MetalPipelineCache;
class MetalRenderStateCache;
class MetalSceneResources;
class MetalShaderLibrary;

class MetalMeshRenderPass {
public:
    explicit MetalMeshRenderPass(MetalDeviceContext& deviceContext);
    ~MetalMeshRenderPass();

    MetalMeshRenderPass(const MetalMeshRenderPass&) = delete;
    MetalMeshRenderPass& operator=(const MetalMeshRenderPass&) = delete;

    MetalMeshRenderPass(MetalMeshRenderPass&&) noexcept;
    MetalMeshRenderPass& operator=(MetalMeshRenderPass&&) noexcept;

    bool initialize(
        MetalShaderLibrary& shaderLibrary,
        MetalPipelineCache& pipelineCache,
        MetalRenderStateCache& renderStateCache,
        MetalTextureFormat colorFormat,
        MetalTextureFormat depthFormat,
        std::string* errorMessage = nullptr);

    bool isReady() const;
    void encode(void* renderCommandEncoder, const MetalSceneResources& sceneResources, void* frameUniformBuffer) const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
