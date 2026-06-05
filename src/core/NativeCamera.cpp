#include "NativeCamera.hpp"

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

float dot(Vec3 lhs, Vec3 rhs)
{
    return lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z;
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
    const float length = std::sqrt(dot(value, value));
    if (length <= 0.000001f) {
        return Vec3{};
    }
    return scale(value, 1.0f / length);
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

Matrix4 perspectiveMetal(float verticalFovDegrees, float aspectRatio, float nearPlane, float farPlane)
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

} // namespace

NativeCamera::NativeCamera() = default;

void NativeCamera::resize(uint32_t width, uint32_t height)
{
    m_width = std::max<uint32_t>(width, 1);
    m_height = std::max<uint32_t>(height, 1);
}

void NativeCamera::update(const InputState& inputState, double deltaTimeSeconds)
{
    if (inputState.mouseButtonsDown[1]) {
        m_yawDegrees += static_cast<float>(inputState.mouseDeltaX) * 0.12f;
        m_pitchDegrees += static_cast<float>(inputState.mouseDeltaY) * 0.12f;
        m_pitchDegrees = std::clamp(m_pitchDegrees, -88.0f, 88.0f);
    }

    if (inputState.scrollDeltaY != 0.0) {
        m_verticalFovDegrees -= static_cast<float>(inputState.scrollDeltaY) * 0.04f;
        m_verticalFovDegrees = std::clamp(m_verticalFovDegrees, 20.0f, 80.0f);
    }

    const Vec3 forward = cameraForward(m_yawDegrees, m_pitchDegrees);
    const Vec3 worldUp{0.0f, 1.0f, 0.0f};
    const Vec3 right = normalize(cross(forward, worldUp));
    const bool boosted = isKeyDown(inputState, kKeyLeftShift) || isKeyDown(inputState, kKeyRightShift);
    const float speed = (boosted ? 4.0f : 1.4f) * static_cast<float>(std::min(deltaTimeSeconds, 0.05));

    Vec3 movement{};
    if (isKeyDown(inputState, kKeyW)) {
        movement = add(movement, forward);
    }
    if (isKeyDown(inputState, kKeyS)) {
        movement = add(movement, scale(forward, -1.0f));
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
    m_position[0] += movement.x * speed;
    m_position[1] += movement.y * speed;
    m_position[2] += movement.z * speed;
}

void NativeCamera::writeFrameUniforms(FrameUniforms& uniforms) const
{
    const Vec3 eye{m_position[0], m_position[1], m_position[2]};
    const Vec3 forward = cameraForward(m_yawDegrees, m_pitchDegrees);
    const Matrix4 model = identityMatrix();
    const Matrix4 view = lookAt(eye, add(eye, forward), Vec3{0.0f, 1.0f, 0.0f});
    const float aspect = static_cast<float>(m_width) / static_cast<float>(m_height);
    const Matrix4 projection = perspectiveMetal(m_verticalFovDegrees, aspect, m_nearPlane, m_farPlane);
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
}

} // namespace mesh2splat::core
