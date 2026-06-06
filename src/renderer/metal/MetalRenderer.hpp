#pragma once

#include "renderer/RendererInterface.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::metal {

using mesh2splat::renderer::GaussianVisualizationMode;
using mesh2splat::renderer::RenderViewMode;
using MetalRendererStats = mesh2splat::renderer::RendererStats;

class MetalRenderer final : public mesh2splat::renderer::Renderer {
public:
    explicit MetalRenderer(void* metalDevice);
    ~MetalRenderer() override;

    MetalRenderer(const MetalRenderer&) = delete;
    MetalRenderer& operator=(const MetalRenderer&) = delete;

    bool initialize() override;
    bool loadMeshFile(const std::string& filePath) override;
    void resize(uint32_t width, uint32_t height) override;
    void setViewMode(RenderViewMode mode) override;
    RenderViewMode viewMode() const override;
    void setGaussianVisualizationMode(GaussianVisualizationMode mode) override;
    GaussianVisualizationMode gaussianVisualizationMode() const override;
    void setGaussianScale(float scale) override;
    float gaussianScale() const override;
    bool setConversionSamplesPerTriangle(uint32_t samplesPerTriangle) override;
    uint32_t conversionSamplesPerTriangle() const override;
    bool isConvertingGaussians() const override;
    uint32_t convertedGaussianCount() const override;
    MetalRendererStats rendererStats() const override;
    const std::string& lastDiagnostic() const override;
    const std::string& loadedMeshPath() const override;
    void draw(
        void* renderPassDescriptor,
        void* drawable,
        const core::InputState& inputState,
        double deltaTimeSeconds) override;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
