#pragma once

#include "core/InputState.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::metal {

enum class RenderViewMode : uint32_t {
    Combined = 0,
    MeshOnly = 1,
    GaussianOnly = 2,
};

enum class GaussianVisualizationMode : uint32_t {
    Albedo = 0,
    Depth = 1,
    Normal = 2,
    Geometry = 3,
    Overdraw = 4,
    Pbr = 5,
    Final = 6,
};

struct MetalRendererStats {
    uint64_t submittedFrameCount = 0;
    uint64_t completedFrameCount = 0;
    uint64_t failedFrameCount = 0;
    uint64_t submittedConversionCount = 0;
    uint64_t completedConversionCount = 0;
    uint64_t failedConversionCount = 0;
    double lastFrameCpuEncodeMs = 0.0;
    double averageFrameCpuEncodeMs = 0.0;
    double lastFrameGpuMs = 0.0;
    double averageFrameGpuMs = 0.0;
    double lastConversionCpuSubmitMs = 0.0;
    double averageConversionCpuSubmitMs = 0.0;
    double lastConversionGpuMs = 0.0;
    double averageConversionGpuMs = 0.0;
    uint32_t lastFrameGaussianCount = 0;
    bool lastFrameSortedGaussians = false;
    bool lastFrameRenderedMesh = false;
    bool lastFrameRenderedGaussians = false;
};

class MetalRenderer {
public:
    explicit MetalRenderer(void* metalDevice);
    ~MetalRenderer();

    MetalRenderer(const MetalRenderer&) = delete;
    MetalRenderer& operator=(const MetalRenderer&) = delete;

    bool initialize();
    bool loadMeshFile(const std::string& filePath);
    void resize(uint32_t width, uint32_t height);
    void setViewMode(RenderViewMode mode);
    RenderViewMode viewMode() const;
    void setGaussianVisualizationMode(GaussianVisualizationMode mode);
    GaussianVisualizationMode gaussianVisualizationMode() const;
    void setGaussianScale(float scale);
    float gaussianScale() const;
    bool setConversionSamplesPerTriangle(uint32_t samplesPerTriangle);
    uint32_t conversionSamplesPerTriangle() const;
    bool isConvertingGaussians() const;
    uint32_t convertedGaussianCount() const;
    MetalRendererStats rendererStats() const;
    const std::string& loadedMeshPath() const;
    void draw(
        void* renderPassDescriptor,
        void* drawable,
        const core::InputState& inputState,
        double deltaTimeSeconds);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
