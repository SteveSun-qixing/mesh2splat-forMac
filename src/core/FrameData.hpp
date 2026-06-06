#pragma once

#include <cstdint>

namespace mesh2splat::core {

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
};

static_assert(sizeof(FrameUniforms) % 16 == 0, "FrameUniforms must stay 16-byte aligned for GPU constant buffers.");

inline FrameUniforms makeDefaultFrameUniforms(uint32_t width, uint32_t height)
{
    FrameUniforms uniforms;
    uniforms.viewport[0] = static_cast<float>(width);
    uniforms.viewport[1] = static_cast<float>(height);
    uniforms.viewport[2] = width == 0 ? 1.0f : 1.0f / static_cast<float>(width);
    uniforms.viewport[3] = height == 0 ? 1.0f : 1.0f / static_cast<float>(height);
    return uniforms;
}

} // namespace mesh2splat::core
