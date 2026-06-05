#pragma once

#include <cstddef>
#include <cstdint>
#include <limits>

namespace mesh2splat::core {

constexpr uint32_t kDefaultMaxGaussianCount = 7000000;

struct GaussianRecord {
    float position[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    float color[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    float scale[4] = {1.0f, 1.0f, 1.0e-7f, 0.0f};
    float normal[4] = {0.0f, 1.0f, 0.0f, 0.0f};
    float rotation[4] = {1.0f, 0.0f, 0.0f, 0.0f};
    float pbr[4] = {0.1f, 0.5f, 0.0f, 1.0f};
};

static_assert(sizeof(GaussianRecord) == sizeof(float) * 4 * 6, "GaussianRecord must stay a tightly packed 6-float4 GPU ABI.");
static_assert(offsetof(GaussianRecord, color) == sizeof(float) * 4, "Gaussian color must start at float4 slot 1.");
static_assert(offsetof(GaussianRecord, scale) == sizeof(float) * 4 * 2, "Gaussian scale must start at float4 slot 2.");
static_assert(offsetof(GaussianRecord, normal) == sizeof(float) * 4 * 3, "Gaussian normal must start at float4 slot 3.");
static_assert(offsetof(GaussianRecord, rotation) == sizeof(float) * 4 * 4, "Gaussian rotation must start at float4 slot 4.");
static_assert(offsetof(GaussianRecord, pbr) == sizeof(float) * 4 * 5, "Gaussian pbr must start at float4 slot 5.");

inline bool gaussianCountFitsBuffer(std::size_t count)
{
    return count <= static_cast<std::size_t>(std::numeric_limits<uint32_t>::max()) &&
        count <= std::numeric_limits<std::size_t>::max() / sizeof(GaussianRecord);
}

inline std::size_t gaussianBufferByteSize(std::size_t count)
{
    return gaussianCountFitsBuffer(count) ? count * sizeof(GaussianRecord) : 0;
}

} // namespace mesh2splat::core
