#pragma once

#include "MetalTexture.hpp"

#include <cstddef>
#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalDeviceContext;
class MetalPipelineCache;
class MetalRenderStateCache;
class MetalSceneResources;
class MetalShaderLibrary;

struct MetalMeshRenderPassDiagnostics {
    bool ready = false;
    bool sceneValid = false;
    bool emptyScene = false;
    std::size_t meshCount = 0;
    std::size_t totalVertexCount = 0;
    std::size_t totalDrawRangeCount = 0;
    std::size_t totalMaterialCount = 0;
    std::size_t totalTextureCount = 0;
    std::size_t encodedMeshCount = 0;
    std::size_t encodedDrawRangeCount = 0;
    std::size_t skippedMeshCount = 0;
    std::size_t skippedDrawRangeCount = 0;
    std::size_t drawnVertexCount = 0;
    std::size_t boundMaterialTextureCount = 0;
    std::size_t missingMaterialTextureCount = 0;
    bool depthEnabled = true;
    bool depthWriteEnabled = true;
    bool wireframeEnabled = false;
    bool shadowsEnabled = false;
    bool shadowTextureBound = false;
    std::string colorFormat;
    std::string depthFormat;
    std::string debugLabel;
    std::string lastMessage;
};

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
    const std::string& lastDiagnostic() const;
    MetalMeshRenderPassDiagnostics lastEncodeDiagnostics() const;
    void encode(
        void* renderCommandEncoder,
        const MetalSceneResources& sceneResources,
        void* frameUniformBuffer,
        bool depthTestEnabled = true,
        bool wireframeEnabled = false,
        void* shadowDistanceTexture = nullptr,
        bool shadowsEnabled = false) const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
