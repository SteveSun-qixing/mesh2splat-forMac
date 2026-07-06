#pragma once

#include "MetalTexture.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalGaussianBuffer;
class MetalGaussianSortBuffer;
class MetalDeviceContext;
class MetalPipelineCache;
class MetalRenderStateCache;
class MetalShaderLibrary;

struct MetalGaussianRenderPassDiagnostics {
    bool ready = false;
    bool gaussianBufferValid = false;
    bool sortBufferValid = false;
    bool usedSortedIndices = false;
    bool usedIdentityIndices = false;
    bool depthTestEnabled = true;
    bool depthWriteEnabled = false;
    std::size_t gaussianCapacity = 0;
    uint32_t gaussianCount = 0;
    std::size_t sortCapacity = 0;
    uint32_t sortCount = 0;
    uint32_t instanceCount = 0;
    std::size_t gaussianResourceBytes = 0;
    std::size_t sortResourceBytes = 0;
    std::size_t identityIndexCapacity = 0;
    std::size_t identityIndexBytes = 0;
    std::string colorFormat;
    std::string depthFormat;
    std::string blendMode;
    std::string alphaBlendDescription;
    std::string additiveBlendDescription;
    std::string indexSource;
    std::string indexFallbackReason;
    std::string debugLabel;
    std::string lastMessage;
};

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
        MetalTextureFormat depthFormat,
        std::string* errorMessage = nullptr);

    bool isReady() const;
    const std::string& lastDiagnostic() const;
    MetalGaussianRenderPassDiagnostics lastEncodeDiagnostics() const;
    void encode(
        void* renderCommandEncoder,
        const MetalGaussianBuffer& gaussianBuffer,
        void* frameUniformBuffer,
        bool depthTestEnabled = true,
        bool overdrawVisualization = false) const;
    void encode(
        void* renderCommandEncoder,
        const MetalGaussianBuffer& gaussianBuffer,
        const MetalGaussianSortBuffer& sortBuffer,
        void* frameUniformBuffer,
        bool depthTestEnabled = true,
        bool overdrawVisualization = false) const;

private:
    void encodeImpl(
        void* renderCommandEncoder,
        const MetalGaussianBuffer& gaussianBuffer,
        const MetalGaussianSortBuffer* sortBuffer,
        void* frameUniformBuffer,
        bool depthTestEnabled,
        bool overdrawVisualization) const;

    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
