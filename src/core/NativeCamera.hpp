#pragma once

#include "FrameData.hpp"
#include "InputState.hpp"

#include <cstdint>

namespace mesh2splat::core {

class NativeCamera {
public:
    NativeCamera();

    void resize(uint32_t width, uint32_t height);
    void update(const InputState& inputState, double deltaTimeSeconds);
    void writeFrameUniforms(FrameUniforms& uniforms) const;

private:
    float m_position[3] = {0.0f, 0.0f, 2.2f};
    float m_yawDegrees = -90.0f;
    float m_pitchDegrees = 0.0f;
    float m_verticalFovDegrees = 45.0f;
    float m_nearPlane = 0.01f;
    float m_farPlane = 100.0f;
    uint32_t m_width = 1;
    uint32_t m_height = 1;
};

} // namespace mesh2splat::core
