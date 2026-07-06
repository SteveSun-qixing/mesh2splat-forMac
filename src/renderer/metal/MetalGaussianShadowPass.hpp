#pragma once

#include "core/FrameData.hpp"
#include "MetalTexture.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalDeviceContext;
class MetalGaussianBuffer;
class MetalPipelineCache;
class MetalRenderStateCache;
class MetalShaderLibrary;

struct MetalGaussianShadowPassDiagnostics {
    bool ready = false;
    bool shadowMapReady = false;
    bool encoded = false;
    uint32_t shadowMapSize = 0;
    uint32_t gaussianCount = 0;
    std::size_t shadowDistanceBytes = 0;
    std::size_t shadowDepthBytes = 0;
    std::size_t uniformBytes = 0;
    std::size_t totalBytes = 0;
    std::string lastMessage;
};

class MetalGaussianShadowPass {
public:
    explicit MetalGaussianShadowPass(MetalDeviceContext& deviceContext);
    ~MetalGaussianShadowPass();

    MetalGaussianShadowPass(const MetalGaussianShadowPass&) = delete;
    MetalGaussianShadowPass& operator=(const MetalGaussianShadowPass&) = delete;

    MetalGaussianShadowPass(MetalGaussianShadowPass&&) noexcept;
    MetalGaussianShadowPass& operator=(MetalGaussianShadowPass&&) noexcept;

    bool initialize(
        MetalShaderLibrary& shaderLibrary,
        MetalPipelineCache& pipelineCache,
        MetalRenderStateCache& renderStateCache,
        uint32_t shadowMapSize = 1024,
        std::string* errorMessage = nullptr);

    bool isReady() const;
    bool resizeShadowMap(uint32_t shadowMapSize);
    uint32_t shadowMapSize() const;
    std::size_t sizeBytes() const;
    void* shadowDistanceTexture() const;
    const std::string& lastDiagnostic() const;
    MetalGaussianShadowPassDiagnostics diagnostics() const;

    bool encode(
        void* commandBuffer,
        const MetalGaussianBuffer& gaussianBuffer,
        const core::FrameUniforms& frameUniforms,
        uint32_t frameResourceIndex);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
