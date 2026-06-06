#include "CameraController.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <iterator>

namespace mesh2splat::core {
namespace {

constexpr float kPi = 3.14159265358979323846f;
constexpr std::size_t kKeyA = 0;
constexpr std::size_t kKeyS = 1;
constexpr std::size_t kKeyD = 2;
constexpr std::size_t kKeyW = 13;
constexpr std::size_t kKeyQ = 12;
constexpr std::size_t kKeyE = 14;
constexpr std::size_t kKeyLeftShift = 56;
constexpr std::size_t kKeyRightShift = 60;
constexpr float kOrbitDegreesPerPoint = 0.12f;
constexpr float kDollyScalePerPoint = 0.08f;
constexpr float kScrollPanScale = 8.0f;

struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
};

float radians(float degrees)
{
    return degrees * kPi / 180.0f;
}

Vec3 add(Vec3 lhs, Vec3 rhs)
{
    return Vec3{lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z};
}

Vec3 scale(Vec3 value, float multiplier)
{
    return Vec3{value.x * multiplier, value.y * multiplier, value.z * multiplier};
}

Vec3 subtract(Vec3 lhs, Vec3 rhs)
{
    return Vec3{lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z};
}

float dot(Vec3 lhs, Vec3 rhs)
{
    return lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z;
}

float length(Vec3 value)
{
    return std::sqrt(dot(value, value));
}

Vec3 cross(Vec3 lhs, Vec3 rhs)
{
    return Vec3{
        lhs.y * rhs.z - lhs.z * rhs.y,
        lhs.z * rhs.x - lhs.x * rhs.z,
        lhs.x * rhs.y - lhs.y * rhs.x,
    };
}

Vec3 normalize(Vec3 value)
{
    const float vectorLength = length(value);
    if (vectorLength <= 0.000001f) {
        return Vec3{};
    }
    return scale(value, 1.0f / vectorLength);
}

Vec3 cameraForward(float yawDegrees, float pitchDegrees)
{
    const float yaw = radians(yawDegrees);
    const float pitch = radians(pitchDegrees);
    return normalize(Vec3{
        std::cos(yaw) * std::cos(pitch),
        std::sin(pitch),
        std::sin(yaw) * std::cos(pitch),
    });
}

Matrix4 identityMatrix()
{
    return Matrix4{};
}

Matrix4 multiply(const Matrix4& lhs, const Matrix4& rhs)
{
    Matrix4 result{};
    std::fill(std::begin(result.values), std::end(result.values), 0.0f);

    for (int column = 0; column < 4; ++column) {
        for (int row = 0; row < 4; ++row) {
            float value = 0.0f;
            for (int index = 0; index < 4; ++index) {
                value += lhs.values[index * 4 + row] * rhs.values[column * 4 + index];
            }
            result.values[column * 4 + row] = value;
        }
    }

    return result;
}

Matrix4 lookAt(Vec3 eye, Vec3 center, Vec3 worldUp)
{
    const Vec3 forward = normalize(Vec3{center.x - eye.x, center.y - eye.y, center.z - eye.z});
    const Vec3 right = normalize(cross(forward, worldUp));
    const Vec3 up = cross(right, forward);

    Matrix4 result{};
    result.values[0] = right.x;
    result.values[1] = up.x;
    result.values[2] = -forward.x;
    result.values[4] = right.y;
    result.values[5] = up.y;
    result.values[6] = -forward.y;
    result.values[8] = right.z;
    result.values[9] = up.z;
    result.values[10] = -forward.z;
    result.values[12] = -dot(right, eye);
    result.values[13] = -dot(up, eye);
    result.values[14] = dot(forward, eye);
    return result;
}

Matrix4 perspectiveDepthZeroToOne(float verticalFovDegrees, float aspectRatio, float nearPlane, float farPlane)
{
    Matrix4 result{};
    std::fill(std::begin(result.values), std::end(result.values), 0.0f);

    const float yScale = 1.0f / std::tan(radians(verticalFovDegrees) * 0.5f);
    const float xScale = yScale / std::max(aspectRatio, 0.0001f);
    result.values[0] = xScale;
    result.values[5] = yScale;
    result.values[10] = farPlane / (nearPlane - farPlane);
    result.values[11] = -1.0f;
    result.values[14] = -(farPlane * nearPlane) / (farPlane - nearPlane);
    return result;
}

bool isKeyDown(const InputState& inputState, std::size_t key)
{
    return key < inputState.keysDown.size() && inputState.keysDown[key];
}

bool isMouseButtonDown(const InputState& inputState, InputState::MouseButton button)
{
    const std::size_t buttonIndex = static_cast<std::size_t>(button);
    return buttonIndex < inputState.mouseButtonsDown.size() && inputState.mouseButtonsDown[buttonIndex];
}

Vec3 readVec3(const float values[3])
{
    return Vec3{values[0], values[1], values[2]};
}

void writeVec3(float values[3], Vec3 vector)
{
    values[0] = vector.x;
    values[1] = vector.y;
    values[2] = vector.z;
}

float viewportAspectForSize(uint32_t width, uint32_t height)
{
    return height == 0 ? 1.0f : static_cast<float>(std::max<uint32_t>(width, 1)) / static_cast<float>(height);
}

float framingDistance(float radius, float verticalFovDegrees, float aspectRatio)
{
    const float halfVerticalFov = radians(verticalFovDegrees) * 0.5f;
    const float halfHorizontalFov = std::atan(std::tan(halfVerticalFov) * std::max(aspectRatio, 0.0001f));
    const float halfFov = std::max(std::min(halfVerticalFov, halfHorizontalFov), 0.001f);
    return radius / std::tan(halfFov) * 1.35f;
}

void clampDistance(float& distance, float radius)
{
    const float minDistance = std::max(radius * 0.02f, 0.001f);
    const float maxDistance = std::max(radius * 1000.0f, minDistance + 1.0f);
    distance = std::clamp(distance, minDistance, maxDistance);
}

} // namespace

CameraController::CameraController() = default;

void CameraController::resize(uint32_t width, uint32_t height)
{
    m_width = std::max<uint32_t>(width, 1);
    m_height = std::max<uint32_t>(height, 1);
    m_viewportAspect = viewportAspectForSize(m_width, m_height);
}

void CameraController::setViewportAspect(float aspectRatio)
{
    m_viewportAspect = aspectRatio > 0.0f ? aspectRatio : 1.0f;
}

float CameraController::viewportAspect() const
{
    return m_viewportAspect;
}

void CameraController::frameBounds(const MeshBounds& bounds)
{
    const Vec3 center{
        (bounds.min[0] + bounds.max[0]) * 0.5f,
        (bounds.min[1] + bounds.max[1]) * 0.5f,
        (bounds.min[2] + bounds.max[2]) * 0.5f,
    };
    const Vec3 extent{
        std::max(bounds.max[0] - bounds.min[0], 0.0f),
        std::max(bounds.max[1] - bounds.min[1], 0.0f),
        std::max(bounds.max[2] - bounds.min[2], 0.0f),
    };
    const float radius = std::max(length(extent) * 0.5f, 0.5f);
    const float distance = framingDistance(radius, m_verticalFovDegrees, m_viewportAspect);

    m_yawDegrees = -90.0f;
    m_pitchDegrees = 0.0f;
    m_defaultYawDegrees = m_yawDegrees;
    m_defaultPitchDegrees = m_pitchDegrees;
    m_distance = distance;
    m_defaultDistance = distance;
    m_boundsRadius = radius;
    m_defaultBoundsRadius = radius;
    m_movementScale = std::max(radius, 1.0f);
    writeVec3(m_target, center);
    writeVec3(m_defaultTarget, center);
    updatePositionFromOrbit();
    updateClipPlanes();
}

void CameraController::focusBounds(const MeshBounds& bounds)
{
    const Vec3 center{
        (bounds.min[0] + bounds.max[0]) * 0.5f,
        (bounds.min[1] + bounds.max[1]) * 0.5f,
        (bounds.min[2] + bounds.max[2]) * 0.5f,
    };
    const Vec3 extent{
        std::max(bounds.max[0] - bounds.min[0], 0.0f),
        std::max(bounds.max[1] - bounds.min[1], 0.0f),
        std::max(bounds.max[2] - bounds.min[2], 0.0f),
    };
    const float radius = std::max(length(extent) * 0.5f, 0.5f);
    const float distance = framingDistance(radius, m_verticalFovDegrees, m_viewportAspect);

    m_distance = distance;
    m_defaultDistance = distance;
    m_boundsRadius = radius;
    m_defaultBoundsRadius = radius;
    m_movementScale = std::max(radius, 1.0f);
    writeVec3(m_target, center);
    writeVec3(m_defaultTarget, center);
    updatePositionFromOrbit();
    updateClipPlanes();
}

void CameraController::resetView()
{
    writeVec3(m_target, readVec3(m_defaultTarget));
    m_distance = m_defaultDistance;
    m_boundsRadius = m_defaultBoundsRadius;
    m_movementScale = std::max(m_boundsRadius, 1.0f);
    m_yawDegrees = m_defaultYawDegrees;
    m_pitchDegrees = m_defaultPitchDegrees;
    updatePositionFromOrbit();
    updateClipPlanes();
}

void CameraController::orbit(float deltaX, float deltaY)
{
    if (deltaX == 0.0f && deltaY == 0.0f) {
        return;
    }

    m_yawDegrees += deltaX * kOrbitDegreesPerPoint;
    m_pitchDegrees += deltaY * kOrbitDegreesPerPoint;
    m_pitchDegrees = std::clamp(m_pitchDegrees, -88.0f, 88.0f);
    updatePositionFromOrbit();
}

void CameraController::pan(float deltaX, float deltaY)
{
    if (deltaX == 0.0f && deltaY == 0.0f) {
        return;
    }

    const Vec3 forward = cameraForward(m_yawDegrees, m_pitchDegrees);
    const Vec3 worldUp{0.0f, 1.0f, 0.0f};
    const Vec3 right = normalize(cross(forward, worldUp));
    const Vec3 up = normalize(cross(right, forward));
    const float worldUnitsPerPoint =
        2.0f * m_distance * std::tan(radians(m_verticalFovDegrees) * 0.5f) /
        static_cast<float>(std::max<uint32_t>(m_height, 1));
    const Vec3 panVector = add(
        scale(right, -deltaX * worldUnitsPerPoint),
        scale(up, deltaY * worldUnitsPerPoint));
    writeVec3(m_target, add(readVec3(m_target), panVector));
    updatePositionFromOrbit();
}

void CameraController::dolly(float delta)
{
    if (delta == 0.0f) {
        return;
    }

    m_distance *= std::exp(-delta * kDollyScalePerPoint);
    clampDistance(m_distance, m_boundsRadius);
    updatePositionFromOrbit();
    updateClipPlanes();
}

void CameraController::update(const InputState& inputState)
{
    update(inputState, inputState.frameDeltaSeconds);
}

void CameraController::update(const InputState& inputState, double deltaTimeSeconds)
{
    if (inputState.viewportWidth > 0 || inputState.viewportHeight > 0) {
        resize(inputState.viewportWidth, inputState.viewportHeight);
    }
    if (inputState.hasViewportAspect) {
        setViewportAspect(inputState.viewportAspect);
    }

    if (inputState.resetViewRequested) {
        resetView();
    }

    const bool shift = inputState.isModifierDown(InputState::ModifierShift) ||
        isKeyDown(inputState, kKeyLeftShift) || isKeyDown(inputState, kKeyRightShift);
    const bool control = inputState.isModifierDown(InputState::ModifierControl);
    const bool option = inputState.isModifierDown(InputState::ModifierOption);
    const bool command = inputState.isModifierDown(InputState::ModifierCommand);
    const bool leftMouseDown = isMouseButtonDown(inputState, InputState::MouseButtonLeft);
    const bool rightMouseDown = isMouseButtonDown(inputState, InputState::MouseButtonRight);
    const bool middleMouseDown = isMouseButtonDown(inputState, InputState::MouseButtonMiddle);

    double orbitDeltaX = inputState.orbitDeltaX;
    double orbitDeltaY = inputState.orbitDeltaY;
    double panDeltaX = inputState.panDeltaX;
    double panDeltaY = inputState.panDeltaY;
    double dollyDelta = inputState.dollyDelta;

    if (rightMouseDown) {
        orbitDeltaX += inputState.mouseDeltaX;
        orbitDeltaY += inputState.mouseDeltaY;
    } else if (middleMouseDown || (leftMouseDown && shift)) {
        panDeltaX += inputState.mouseDeltaX;
        panDeltaY += inputState.mouseDeltaY;
    } else if (leftMouseDown && option) {
        dollyDelta -= inputState.mouseDeltaY;
    }

    if (inputState.trackpadDeltaX != 0.0 || inputState.trackpadDeltaY != 0.0) {
        if (option || command) {
            dollyDelta -= inputState.trackpadDeltaY;
        } else if (shift || control) {
            panDeltaX += inputState.trackpadDeltaX;
            panDeltaY += inputState.trackpadDeltaY;
        } else {
            orbitDeltaX += inputState.trackpadDeltaX;
            orbitDeltaY += inputState.trackpadDeltaY;
        }
    }

    if (inputState.scrollDeltaX != 0.0 || inputState.scrollDeltaY != 0.0) {
        if (shift || control) {
            panDeltaX += inputState.scrollDeltaX * kScrollPanScale;
            panDeltaY += inputState.scrollDeltaY * kScrollPanScale;
        } else {
            dollyDelta += inputState.scrollDeltaY;
            panDeltaX += inputState.scrollDeltaX * kScrollPanScale;
        }
    }

    orbit(static_cast<float>(orbitDeltaX), static_cast<float>(orbitDeltaY));
    pan(static_cast<float>(panDeltaX), static_cast<float>(panDeltaY));
    dolly(static_cast<float>(dollyDelta));

    const Vec3 forward = cameraForward(m_yawDegrees, m_pitchDegrees);
    const Vec3 worldUp{0.0f, 1.0f, 0.0f};
    const Vec3 right = normalize(cross(forward, worldUp));
    const bool boosted = isKeyDown(inputState, kKeyLeftShift) || isKeyDown(inputState, kKeyRightShift);
    const double clampedDeltaTimeSeconds = std::clamp(deltaTimeSeconds, 0.0, 0.05);
    const float speed = (boosted ? 4.0f : 1.4f) * m_movementScale *
        static_cast<float>(clampedDeltaTimeSeconds);

    Vec3 movement{};
    if (isKeyDown(inputState, kKeyW)) {
        m_distance -= speed;
    }
    if (isKeyDown(inputState, kKeyS)) {
        m_distance += speed;
    }
    if (isKeyDown(inputState, kKeyD)) {
        movement = add(movement, right);
    }
    if (isKeyDown(inputState, kKeyA)) {
        movement = add(movement, scale(right, -1.0f));
    }
    if (isKeyDown(inputState, kKeyE)) {
        movement = add(movement, worldUp);
    }
    if (isKeyDown(inputState, kKeyQ)) {
        movement = add(movement, scale(worldUp, -1.0f));
    }

    movement = normalize(movement);
    if (movement.x != 0.0f || movement.y != 0.0f || movement.z != 0.0f) {
        writeVec3(m_target, add(readVec3(m_target), scale(movement, speed)));
    }
    clampDistance(m_distance, m_boundsRadius);
    updatePositionFromOrbit();
    updateClipPlanes();
}

void CameraController::update(const FrameInputSnapshot& snapshot)
{
    if (!snapshot.viewport.empty()) {
        resize(snapshot.viewport.width, snapshot.viewport.height);
    }
    InputState inputState = snapshot.inputState;
    if (!snapshot.viewport.empty()) {
        inputState.setViewportSize(snapshot.viewport.width, snapshot.viewport.height);
    }
    update(inputState, snapshot.timing.deltaTimeSeconds);
}

void CameraController::updatePositionFromOrbit()
{
    clampDistance(m_distance, m_boundsRadius);
    const Vec3 target = readVec3(m_target);
    const Vec3 forward = cameraForward(m_yawDegrees, m_pitchDegrees);
    writeVec3(m_position, subtract(target, scale(forward, m_distance)));
}

void CameraController::updateClipPlanes()
{
    m_nearPlane = std::max(m_boundsRadius * 0.001f, 0.001f);
    m_farPlane = std::max(m_distance + m_boundsRadius * 4.0f, m_nearPlane + 1.0f);
}

void CameraController::writeFrameUniforms(FrameUniforms& uniforms) const
{
    const Vec3 eye{m_position[0], m_position[1], m_position[2]};
    const Matrix4 model = identityMatrix();
    const Matrix4 view = lookAt(eye, readVec3(m_target), Vec3{0.0f, 1.0f, 0.0f});
    const float aspect = std::max(m_viewportAspect, 0.0001f);
    const Matrix4 projection = perspectiveDepthZeroToOne(m_verticalFovDegrees, aspect, m_nearPlane, m_farPlane);
    const Matrix4 modelViewProjection = multiply(projection, multiply(view, model));

    std::memcpy(uniforms.modelMatrix.values, model.values, sizeof(model.values));
    std::memcpy(uniforms.viewMatrix.values, view.values, sizeof(view.values));
    std::memcpy(uniforms.projectionMatrix.values, projection.values, sizeof(projection.values));
    std::memcpy(uniforms.modelViewProjectionMatrix.values, modelViewProjection.values, sizeof(modelViewProjection.values));
    uniforms.cameraPosition[0] = m_position[0];
    uniforms.cameraPosition[1] = m_position[1];
    uniforms.cameraPosition[2] = m_position[2];
    uniforms.cameraPosition[3] = 1.0f;
    uniforms.clippingPlanes[0] = m_nearPlane;
    uniforms.clippingPlanes[1] = m_farPlane;

    const float verticalFov = radians(m_verticalFovDegrees);
    const float horizontalFov = 2.0f * std::atan(std::tan(verticalFov * 0.5f) * aspect);
    uniforms.hfovFocal[0] = horizontalFov;
    uniforms.hfovFocal[1] = verticalFov;
    uniforms.hfovFocal[2] = static_cast<float>(m_width) / (2.0f * std::tan(horizontalFov * 0.5f));
    uniforms.hfovFocal[3] = static_cast<float>(m_height) / (2.0f * std::tan(verticalFov * 0.5f));
    applyViewportState(uniforms, makeViewportState(m_width, m_height));
}

void CameraController::writeFrameUniforms(FrameUniforms& uniforms, const FrameInputSnapshot& snapshot) const
{
    writeFrameUniforms(uniforms);
    applyFrameInputSnapshot(uniforms, snapshot);
}

} // namespace mesh2splat::core
