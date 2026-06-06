#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <type_traits>

namespace mesh2splat::core {

constexpr uint32_t kDefaultMaxGaussianCount = 7000000;
constexpr float kSphericalHarmonicC0 = 0.28209479177387814f;
constexpr std::size_t kGaussianRecordSlotComponentCount = 4;
constexpr std::size_t kGaussianRecordSlotCount = 6;
constexpr std::size_t kGaussianRecordFloatCount =
    kGaussianRecordSlotComponentCount * kGaussianRecordSlotCount;
constexpr std::size_t kGaussianRecordSlotStrideBytes =
    sizeof(float) * kGaussianRecordSlotComponentCount;
constexpr float kGaussianMinimumAxisScale = 1.0e-7f;

enum class GaussianRecordSlot : uint32_t {
    Position = 0,
    Color = 1,
    Scale = 2,
    Normal = 3,
    Rotation = 4,
    Pbr = 5,
};

struct GaussianRecord {
    float position[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    float color[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    float scale[4] = {1.0f, 1.0f, kGaussianMinimumAxisScale, 0.0f};
    float normal[4] = {0.0f, 1.0f, 0.0f, 0.0f};
    float rotation[4] = {1.0f, 0.0f, 0.0f, 0.0f};
    float pbr[4] = {0.1f, 0.5f, 0.0f, 1.0f};
};

constexpr std::size_t kGaussianRecordStrideBytes = sizeof(GaussianRecord);
constexpr std::size_t kGaussianRecordPositionOffsetBytes = offsetof(GaussianRecord, position);
constexpr std::size_t kGaussianRecordColorOffsetBytes = offsetof(GaussianRecord, color);
constexpr std::size_t kGaussianRecordScaleOffsetBytes = offsetof(GaussianRecord, scale);
constexpr std::size_t kGaussianRecordNormalOffsetBytes = offsetof(GaussianRecord, normal);
constexpr std::size_t kGaussianRecordRotationOffsetBytes = offsetof(GaussianRecord, rotation);
constexpr std::size_t kGaussianRecordPbrOffsetBytes = offsetof(GaussianRecord, pbr);

static_assert(std::is_standard_layout<GaussianRecord>::value, "GaussianRecord must remain a plain GPU upload record.");
static_assert(sizeof(GaussianRecord) == sizeof(float) * kGaussianRecordFloatCount, "GaussianRecord must stay a tightly packed 6-float4 GPU ABI.");
static_assert(kGaussianRecordPositionOffsetBytes == 0, "Gaussian position must start at float4 slot 0.");
static_assert(kGaussianRecordColorOffsetBytes == kGaussianRecordSlotStrideBytes, "Gaussian color must start at float4 slot 1.");
static_assert(kGaussianRecordScaleOffsetBytes == kGaussianRecordSlotStrideBytes * 2, "Gaussian scale must start at float4 slot 2.");
static_assert(kGaussianRecordNormalOffsetBytes == kGaussianRecordSlotStrideBytes * 3, "Gaussian normal must start at float4 slot 3.");
static_assert(kGaussianRecordRotationOffsetBytes == kGaussianRecordSlotStrideBytes * 4, "Gaussian rotation must start at float4 slot 4.");
static_assert(kGaussianRecordPbrOffsetBytes == kGaussianRecordSlotStrideBytes * 5, "Gaussian pbr must start at float4 slot 5.");

constexpr std::size_t gaussianRecordSlotOffset(GaussianRecordSlot slot)
{
    return static_cast<std::size_t>(slot) * kGaussianRecordSlotStrideBytes;
}

inline bool gaussianCountFitsBuffer(std::size_t count)
{
    return count <= static_cast<std::size_t>(std::numeric_limits<uint32_t>::max()) &&
        count <= std::numeric_limits<std::size_t>::max() / sizeof(GaussianRecord);
}

inline std::size_t gaussianBufferByteSize(std::size_t count)
{
    return gaussianCountFitsBuffer(count) ? count * sizeof(GaussianRecord) : 0;
}

inline float gaussianColorToSh0(float linearColor)
{
    return (linearColor - 0.5f) / kSphericalHarmonicC0;
}

inline float gaussianAlphaToOpacityLogit(float alpha)
{
    const float clampedAlpha = std::clamp(alpha, 1.0e-6f, 1.0f - 1.0e-6f);
    return std::log(clampedAlpha / (1.0f - clampedAlpha));
}

inline float gaussianPositiveScaleToLog(float scale, float multiplier)
{
    constexpr float kMinimumScale = 1.0e-20f;
    return std::log(std::max(scale * multiplier, kMinimumScale));
}

inline bool isFiniteFloatArray(const float* values, std::size_t count)
{
    if (values == nullptr) {
        return false;
    }

    for (std::size_t index = 0; index < count; ++index) {
        if (!std::isfinite(values[index])) {
            return false;
        }
    }
    return true;
}

inline bool isFiniteGaussianRecord(const GaussianRecord& gaussian)
{
    const float* values[] = {
        gaussian.position,
        gaussian.color,
        gaussian.scale,
        gaussian.normal,
        gaussian.rotation,
        gaussian.pbr,
    };

    for (const float* slot : values) {
        for (int component = 0; component < 4; ++component) {
            if (!std::isfinite(slot[component])) {
                return false;
            }
        }
    }

    return true;
}

inline bool hasUsableGaussianScale(const GaussianRecord& gaussian)
{
    return gaussian.scale[0] > 0.0f &&
        gaussian.scale[1] > 0.0f &&
        gaussian.scale[2] >= 0.0f;
}

inline bool hasNormalizedGaussianAlpha(const GaussianRecord& gaussian)
{
    return gaussian.color[3] >= 0.0f && gaussian.color[3] <= 1.0f;
}

inline bool isValidGaussianRecordForGpuUpload(const GaussianRecord& gaussian)
{
    return isFiniteGaussianRecord(gaussian) &&
        hasUsableGaussianScale(gaussian) &&
        hasNormalizedGaussianAlpha(gaussian);
}

inline void copyGaussianComponents(float* destination, const float* source, std::size_t count)
{
    if (destination == nullptr || source == nullptr) {
        return;
    }

    std::copy_n(source, count, destination);
}

inline GaussianRecord makeGaussianRecord(
    const float* position3,
    const float* color4 = nullptr,
    const float* scale3 = nullptr,
    const float* normal3 = nullptr,
    const float* rotation4 = nullptr,
    const float* pbr4 = nullptr)
{
    GaussianRecord gaussian;
    copyGaussianComponents(gaussian.position, position3, 3);
    copyGaussianComponents(gaussian.color, color4, 4);
    copyGaussianComponents(gaussian.scale, scale3, 3);
    copyGaussianComponents(gaussian.normal, normal3, 3);
    copyGaussianComponents(gaussian.rotation, rotation4, 4);
    copyGaussianComponents(gaussian.pbr, pbr4, 4);
    return gaussian;
}

inline GaussianRecord makeGaussianRecordFromGpuSlots(
    const float* position4,
    const float* color4,
    const float* scale4,
    const float* normal4,
    const float* rotation4,
    const float* pbr4)
{
    GaussianRecord gaussian;
    copyGaussianComponents(gaussian.position, position4, 4);
    copyGaussianComponents(gaussian.color, color4, 4);
    copyGaussianComponents(gaussian.scale, scale4, 4);
    copyGaussianComponents(gaussian.normal, normal4, 4);
    copyGaussianComponents(gaussian.rotation, rotation4, 4);
    copyGaussianComponents(gaussian.pbr, pbr4, 4);
    return gaussian;
}

} // namespace mesh2splat::core
