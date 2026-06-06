#pragma once

#include "FrameData.hpp"
#include "InputState.hpp"
#include "MeshData.hpp"

#include <cstdint>

namespace mesh2splat::core {

class CameraController {
public:
    CameraController();

    void resize(uint32_t width, uint32_t height);
    void setViewportAspect(float aspectRatio);
    float viewportAspect() const;
    void frameBounds(const MeshBounds& bounds);
    void focusBounds(const MeshBounds& bounds);
    void resetView();
    void orbit(float deltaX, float deltaY);
    void pan(float deltaX, float deltaY);
    void dolly(float delta);
    void update(const InputState& inputState);
    void update(const InputState& inputState, double deltaTimeSeconds);
    void update(const FrameInputSnapshot& snapshot);
    void writeFrameUniforms(FrameUniforms& uniforms) const;
    void writeFrameUniforms(FrameUniforms& uniforms, const FrameInputSnapshot& snapshot) const;

private:
    void updatePositionFromOrbit();
    void updateClipPlanes();

    float m_target[3] = {0.0f, 0.0f, 0.0f};
    float m_defaultTarget[3] = {0.0f, 0.0f, 0.0f};
    float m_position[3] = {0.0f, 0.0f, 2.2f};
    float m_defaultDistance = 2.2f;
    float m_distance = 2.2f;
    float m_boundsRadius = 1.0f;
    float m_defaultBoundsRadius = 1.0f;
    float m_yawDegrees = -90.0f;
    float m_pitchDegrees = 0.0f;
    float m_defaultYawDegrees = -90.0f;
    float m_defaultPitchDegrees = 0.0f;
    float m_verticalFovDegrees = 45.0f;
    float m_nearPlane = 0.01f;
    float m_farPlane = 100.0f;
    float m_movementScale = 1.0f;
    float m_viewportAspect = 1.0f;
    uint32_t m_width = 1;
    uint32_t m_height = 1;
};

} // namespace mesh2splat::core
