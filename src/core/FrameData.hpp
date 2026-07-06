#pragma once

#include "InputState.hpp"

#include <cstddef>
#include <cstdint>

namespace mesh2splat::core {

struct ViewportState {
    uint32_t width = 0;
    uint32_t height = 0;
    float widthFloat = 0.0f;
    float heightFloat = 0.0f;
    float inverseWidth = 1.0f;
    float inverseHeight = 1.0f;

    bool empty() const
    {
        return width == 0 || height == 0;
    }

    float aspectRatio() const
    {
        return empty() ? 1.0f : widthFloat / heightFloat;
    }
};

struct FrameTiming {
    uint64_t frameNumber = 0;
    uint32_t frameIndex = 0;
    double deltaTimeSeconds = 0.0;
    double elapsedTimeSeconds = 0.0;
    double cpuEncodeMilliseconds = 0.0;
    double gpuMilliseconds = 0.0;
};

struct FrameRenderStatistics {
    uint64_t submittedFrameCount = 0;
    uint64_t completedFrameCount = 0;
    uint64_t failedFrameCount = 0;
    uint32_t meshCount = 0;
    uint32_t materialCount = 0;
    uint32_t textureCount = 0;
    uint32_t gaussianCount = 0;
    bool renderedMesh = false;
    bool renderedGaussians = false;
    bool sortedGaussians = false;
};

struct FrameInputSnapshot {
    ViewportState viewport;
    FrameTiming timing;
    InputState inputState;
    uint32_t renderMode = 0;
    uint32_t flags = 0;
    float gaussianScale = 1.0f;
    uint32_t conversionSamplesPerTriangle = 1;
    bool wantsMeshRender = true;
    bool wantsGaussianRender = true;

    bool hasPointerDelta() const
    {
        return inputState.mouseDeltaX != 0.0 || inputState.mouseDeltaY != 0.0 ||
            inputState.trackpadDeltaX != 0.0 || inputState.trackpadDeltaY != 0.0 ||
            inputState.orbitDeltaX != 0.0 || inputState.orbitDeltaY != 0.0 ||
            inputState.panDeltaX != 0.0 || inputState.panDeltaY != 0.0;
    }

    bool hasScrollDelta() const
    {
        return inputState.scrollDeltaX != 0.0 || inputState.scrollDeltaY != 0.0 ||
            inputState.dollyDelta != 0.0;
    }
};

struct alignas(16) Matrix4 {
    float values[16] = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f,
    };
};

struct alignas(16) FrameUniforms {
    Matrix4 modelMatrix;
    Matrix4 viewMatrix;
    Matrix4 projectionMatrix;
    Matrix4 modelViewProjectionMatrix;
    float cameraPosition[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    float hfovFocal[4] = {0.0f, 0.0f, 0.0f, 0.0f};
    float viewport[4] = {0.0f, 0.0f, 1.0f, 1.0f};
    float clippingPlanes[4] = {0.1f, 1000.0f, 0.0f, 0.0f};
    float gaussianParams[4] = {1.0f, 0.0f, 0.0f, 0.0f};
    uint32_t frameIndex = 0;
    uint32_t renderMode = 0;
    uint32_t flags = 0;
    uint32_t reserved = 0;
    float frameTiming[4] = {0.0f, 0.0f, 0.0f, 0.0f};
    float lightPositionIntensity[4] = {3.0f, 4.0f, 2.5f, 1.0f};
    float lightColorFlags[4] = {1.0f, 0.95f, 0.85f, 1.0f};
};

static_assert(sizeof(FrameUniforms) % 16 == 0, "FrameUniforms must stay 16-byte aligned for GPU constant buffers.");
static_assert(sizeof(FrameUniforms) == 400, "FrameUniforms must match the Metal shader ABI.");

inline ViewportState makeViewportState(uint32_t width, uint32_t height)
{
    ViewportState viewport;
    viewport.width = width;
    viewport.height = height;
    viewport.widthFloat = static_cast<float>(width);
    viewport.heightFloat = static_cast<float>(height);
    viewport.inverseWidth = width == 0 ? 1.0f : 1.0f / viewport.widthFloat;
    viewport.inverseHeight = height == 0 ? 1.0f : 1.0f / viewport.heightFloat;
    return viewport;
}

inline void applyViewportState(FrameUniforms& uniforms, const ViewportState& viewport)
{
    uniforms.viewport[0] = viewport.widthFloat;
    uniforms.viewport[1] = viewport.heightFloat;
    uniforms.viewport[2] = viewport.inverseWidth;
    uniforms.viewport[3] = viewport.inverseHeight;
}

inline void applyFrameTiming(FrameUniforms& uniforms, const FrameTiming& timing)
{
    uniforms.frameIndex = timing.frameIndex;
    uniforms.frameTiming[0] = static_cast<float>(timing.deltaTimeSeconds);
    uniforms.frameTiming[1] = static_cast<float>(timing.elapsedTimeSeconds);
    uniforms.frameTiming[2] = static_cast<float>(timing.cpuEncodeMilliseconds);
    uniforms.frameTiming[3] = static_cast<float>(timing.gpuMilliseconds);
}

inline void applyFrameInputSnapshot(FrameUniforms& uniforms, const FrameInputSnapshot& snapshot)
{
    applyViewportState(uniforms, snapshot.viewport);
    applyFrameTiming(uniforms, snapshot.timing);
    uniforms.renderMode = snapshot.renderMode;
    uniforms.flags = snapshot.flags;
    uniforms.gaussianParams[0] = snapshot.gaussianScale;
    uniforms.gaussianParams[1] = static_cast<float>(snapshot.conversionSamplesPerTriangle);
    uniforms.gaussianParams[2] = snapshot.wantsMeshRender ? 1.0f : 0.0f;
    uniforms.gaussianParams[3] = snapshot.wantsGaussianRender ? 1.0f : 0.0f;
}

inline FrameUniforms makeDefaultFrameUniforms(uint32_t width, uint32_t height)
{
    FrameUniforms uniforms;
    applyViewportState(uniforms, makeViewportState(width, height));
    return uniforms;
}

inline bool inputMouseButtonDown(const InputState& inputState, std::size_t button)
{
    return button < inputState.mouseButtonsDown.size() && inputState.mouseButtonsDown[button];
}

inline FrameInputSnapshot makeFrameInputSnapshot(
    const InputState& inputState,
    const ViewportState& viewport,
    const FrameTiming& timing = {})
{
    FrameInputSnapshot snapshot;
    snapshot.viewport = viewport;
    snapshot.timing = timing;
    snapshot.inputState = inputState;
    return snapshot;
}

inline FrameInputSnapshot makeFrameInputSnapshot(
    const InputState& inputState,
    uint32_t width,
    uint32_t height,
    const FrameTiming& timing = {})
{
    return makeFrameInputSnapshot(inputState, makeViewportState(width, height), timing);
}

} // namespace mesh2splat::core
