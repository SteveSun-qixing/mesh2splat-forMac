#pragma once

#include <memory>

namespace mesh2splat::metal {

class MetalGaussianBuffer;
class MetalGaussianSortBuffer;
class MetalPipelineCache;
class MetalShaderLibrary;

class MetalGaussianSortPass {
public:
    MetalGaussianSortPass();
    ~MetalGaussianSortPass();

    MetalGaussianSortPass(const MetalGaussianSortPass&) = delete;
    MetalGaussianSortPass& operator=(const MetalGaussianSortPass&) = delete;

    MetalGaussianSortPass(MetalGaussianSortPass&&) noexcept;
    MetalGaussianSortPass& operator=(MetalGaussianSortPass&&) noexcept;

    bool initialize(MetalShaderLibrary& shaderLibrary, MetalPipelineCache& pipelineCache);
    bool isReady() const;
    bool encodeDepthKeys(
        void* commandBuffer,
        const MetalGaussianBuffer& gaussianBuffer,
        MetalGaussianSortBuffer& sortBuffer,
        void* frameUniformBuffer) const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
