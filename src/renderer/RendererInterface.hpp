#pragma once

#include "core/InputState.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::renderer {

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

struct RendererStats {
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
    uint64_t frameUniformResourceBytes = 0;
    uint64_t sceneResourceBytes = 0;
    uint64_t gaussianResourceBytes = 0;
    uint64_t gaussianSortResourceBytes = 0;
    uint64_t pendingConversionResourceBytes = 0;
    uint64_t trackedResourceBytes = 0;
    bool lastFrameSortedGaussians = false;
    bool lastFrameRenderedMesh = false;
    bool lastFrameRenderedGaussians = false;
};

class Renderer {
public:
    virtual ~Renderer() = default;

    virtual bool initialize() = 0;
    virtual bool loadMeshFile(const std::string& filePath) = 0;
    virtual void resize(uint32_t width, uint32_t height) = 0;
    virtual void setViewMode(RenderViewMode mode) = 0;
    virtual RenderViewMode viewMode() const = 0;
    virtual void setGaussianVisualizationMode(GaussianVisualizationMode mode) = 0;
    virtual GaussianVisualizationMode gaussianVisualizationMode() const = 0;
    virtual void setGaussianScale(float scale) = 0;
    virtual float gaussianScale() const = 0;
    virtual bool setConversionSamplesPerTriangle(uint32_t samplesPerTriangle) = 0;
    virtual uint32_t conversionSamplesPerTriangle() const = 0;
    virtual bool isConvertingGaussians() const = 0;
    virtual uint32_t convertedGaussianCount() const = 0;
    virtual RendererStats rendererStats() const = 0;
    virtual const std::string& lastDiagnostic() const = 0;
    virtual const std::string& loadedMeshPath() const = 0;
    virtual void draw(
        void* renderPassDescriptor,
        void* drawable,
        const core::InputState& inputState,
        double deltaTimeSeconds) = 0;
};

std::unique_ptr<Renderer> createMetalRenderer(void* metalDevice);

} // namespace mesh2splat::renderer
