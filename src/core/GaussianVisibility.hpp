#pragma once

#include "GaussianData.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace mesh2splat::core {

constexpr std::size_t kGaussianVisibilityMaxClipPlaneCount = 6;
constexpr std::size_t kGaussianVisibilityFrustumPlaneCount = 6;
constexpr float kGaussianVisibilityDefaultClipRadiusMultiplier = 3.0f;
constexpr float kGaussianVisibilityDefaultAlphaCullThreshold = 1.0e-4f;
constexpr float kGaussianVisibilityDefaultMinimumScaleCullThreshold = kGaussianMinimumAxisScale;
constexpr float kGaussianVisibilityMinimumPlaneNormalLength = 1.0e-20f;

struct GaussianClipPlane {
    float normal[3] = {0.0f, 0.0f, 0.0f};
    float offset = 0.0f;
};

struct GaussianClipParams {
    std::array<GaussianClipPlane, kGaussianVisibilityMaxClipPlaneCount> planes = {};
    std::size_t planeCount = 0;
    float radiusMultiplier = kGaussianVisibilityDefaultClipRadiusMultiplier;
    bool enabled = false;
};

struct GaussianFrustumParams {
    std::array<GaussianClipPlane, kGaussianVisibilityFrustumPlaneCount> planes = {};
    std::size_t planeCount = 0;
    float radiusMultiplier = kGaussianVisibilityDefaultClipRadiusMultiplier;
    bool enabled = false;
};

enum class GaussianVisibilityDepthRange : uint32_t {
    ZeroToOne = 0,
    NegativeOneToOne = 1,
};

enum class GaussianVisibilityMatrixLayout : uint32_t {
    ColumnMajor = 0,
    RowMajor = 1,
};

enum class GaussianFrustumPlane : uint32_t {
    Left = 0,
    Right = 1,
    Bottom = 2,
    Top = 3,
    Near = 4,
    Far = 5,
};

enum class GaussianVisibilityCullReason : uint32_t {
    Visible = 0,
    InvalidRecord = 1,
    AlphaBelowThreshold = 2,
    ScaleBelowThreshold = 3,
    ScaleAboveThreshold = 4,
    OutsideClipVolume = 5,
    OutsideFrustum = 6,
};

struct GaussianVisibilitySettings {
    GaussianClipParams clip = {};
    GaussianFrustumParams frustum = {};
    float alphaCullThreshold = kGaussianVisibilityDefaultAlphaCullThreshold;
    float minimumScaleCullThreshold = kGaussianVisibilityDefaultMinimumScaleCullThreshold;
    float maximumScaleCullThreshold = std::numeric_limits<float>::infinity();
    std::size_t visibleBudget = 0;
    bool rejectInvalidRecords = true;
    bool enableAlphaCull = true;
    bool enableScaleCull = true;
};

struct GaussianVisibilityDiagnostics {
    std::size_t inputCount = 0;
    std::size_t invalidRecordCount = 0;
    std::size_t alphaCullCount = 0;
    std::size_t scaleBelowThresholdCount = 0;
    std::size_t scaleAboveThresholdCount = 0;
    std::size_t frustumCullCount = 0;
    std::size_t clipCullCount = 0;
    std::size_t visibleCount = 0;
    std::size_t visibleBudget = 0;
    std::size_t budgetedVisibleCount = 0;
    std::size_t configuredFrustumPlaneCount = 0;
    std::size_t invalidFrustumPlaneCount = 0;
    std::size_t configuredClipPlaneCount = 0;
    std::size_t invalidClipPlaneCount = 0;

    bool budgetExceeded() const
    {
        return visibleBudget > 0 && visibleCount > visibleBudget;
    }

    std::size_t scaleCullCount() const
    {
        return scaleBelowThresholdCount + scaleAboveThresholdCount;
    }

    std::size_t rejectedCount() const
    {
        return invalidRecordCount + alphaCullCount + scaleCullCount() + frustumCullCount + clipCullCount;
    }

    std::size_t budgetOverflowCount() const
    {
        return visibleCount > budgetedVisibleCount ? visibleCount - budgetedVisibleCount : 0;
    }
};

inline GaussianClipPlane makeGaussianClipPlane(float normalX, float normalY, float normalZ, float offset)
{
    GaussianClipPlane plane;
    plane.normal[0] = normalX;
    plane.normal[1] = normalY;
    plane.normal[2] = normalZ;
    plane.offset = offset;
    return plane;
}

inline GaussianClipPlane makeGaussianClipPlaneFromPoint(
    float normalX,
    float normalY,
    float normalZ,
    float pointX,
    float pointY,
    float pointZ)
{
    return makeGaussianClipPlane(
        normalX,
        normalY,
        normalZ,
        -(normalX * pointX + normalY * pointY + normalZ * pointZ));
}

inline bool appendGaussianClipPlane(GaussianClipParams& params, const GaussianClipPlane& plane)
{
    if (params.planeCount >= kGaussianVisibilityMaxClipPlaneCount) {
        return false;
    }

    params.planes[params.planeCount] = plane;
    ++params.planeCount;
    params.enabled = true;
    return true;
}

inline bool appendGaussianFrustumPlane(GaussianFrustumParams& params, const GaussianClipPlane& plane)
{
    if (params.planeCount >= kGaussianVisibilityFrustumPlaneCount) {
        return false;
    }

    params.planes[params.planeCount] = plane;
    ++params.planeCount;
    params.enabled = true;
    return true;
}

inline GaussianClipParams makeGaussianClipParams(
    const GaussianClipPlane* planes,
    std::size_t planeCount,
    float radiusMultiplier = kGaussianVisibilityDefaultClipRadiusMultiplier)
{
    GaussianClipParams params;
    params.radiusMultiplier = radiusMultiplier;

    if (planes == nullptr) {
        return params;
    }

    const std::size_t copiedPlaneCount = std::min(planeCount, kGaussianVisibilityMaxClipPlaneCount);
    for (std::size_t index = 0; index < copiedPlaneCount; ++index) {
        params.planes[index] = planes[index];
    }

    params.planeCount = copiedPlaneCount;
    params.enabled = copiedPlaneCount > 0;
    return params;
}

inline GaussianFrustumParams makeGaussianFrustumParams(
    const GaussianClipPlane* planes,
    std::size_t planeCount,
    float radiusMultiplier = kGaussianVisibilityDefaultClipRadiusMultiplier)
{
    GaussianFrustumParams params;
    params.radiusMultiplier = radiusMultiplier;

    if (planes == nullptr) {
        return params;
    }

    const std::size_t copiedPlaneCount = std::min(planeCount, kGaussianVisibilityFrustumPlaneCount);
    for (std::size_t index = 0; index < copiedPlaneCount; ++index) {
        params.planes[index] = planes[index];
    }

    params.planeCount = copiedPlaneCount;
    params.enabled = copiedPlaneCount > 0;
    return params;
}

inline bool isFiniteGaussianClipPlane(const GaussianClipPlane& plane)
{
    return std::isfinite(plane.normal[0]) &&
        std::isfinite(plane.normal[1]) &&
        std::isfinite(plane.normal[2]) &&
        std::isfinite(plane.offset);
}

inline float gaussianClipPlaneDistance(const GaussianClipPlane& plane, const GaussianRecord& gaussian)
{
    return plane.normal[0] * gaussian.position[0] +
        plane.normal[1] * gaussian.position[1] +
        plane.normal[2] * gaussian.position[2] +
        plane.offset;
}

inline float gaussianClipPlaneNormalLength(const GaussianClipPlane& plane)
{
    return std::sqrt(
        plane.normal[0] * plane.normal[0] +
        plane.normal[1] * plane.normal[1] +
        plane.normal[2] * plane.normal[2]);
}

inline bool hasUsableGaussianClipPlaneNormal(const GaussianClipPlane& plane)
{
    const float normalLength = gaussianClipPlaneNormalLength(plane);
    return std::isfinite(normalLength) && normalLength > kGaussianVisibilityMinimumPlaneNormalLength;
}

inline bool isUsableGaussianClipPlane(const GaussianClipPlane& plane)
{
    return isFiniteGaussianClipPlane(plane) && hasUsableGaussianClipPlaneNormal(plane);
}

inline bool normalizeGaussianClipPlane(GaussianClipPlane& plane)
{
    if (!isFiniteGaussianClipPlane(plane)) {
        return false;
    }

    const float normalLength = gaussianClipPlaneNormalLength(plane);
    if (!std::isfinite(normalLength) || normalLength <= kGaussianVisibilityMinimumPlaneNormalLength) {
        return false;
    }

    const float inverseNormalLength = 1.0f / normalLength;
    plane.normal[0] *= inverseNormalLength;
    plane.normal[1] *= inverseNormalLength;
    plane.normal[2] *= inverseNormalLength;
    plane.offset *= inverseNormalLength;
    return true;
}

inline GaussianClipPlane normalizedGaussianClipPlane(const GaussianClipPlane& plane)
{
    GaussianClipPlane normalizedPlane = plane;
    normalizeGaussianClipPlane(normalizedPlane);
    return normalizedPlane;
}

inline float gaussianVisibilityMatrixElement(
    const float* matrix,
    GaussianVisibilityMatrixLayout layout,
    std::size_t row,
    std::size_t column)
{
    return layout == GaussianVisibilityMatrixLayout::RowMajor ?
        matrix[row * 4 + column] :
        matrix[column * 4 + row];
}

inline GaussianClipPlane makeGaussianClipPlaneFromMatrixRows(
    const float* matrix,
    GaussianVisibilityMatrixLayout layout,
    float row0Scale,
    float row1Scale,
    float row2Scale,
    float row3Scale)
{
    GaussianClipPlane plane;
    plane.normal[0] =
        row0Scale * gaussianVisibilityMatrixElement(matrix, layout, 0, 0) +
        row1Scale * gaussianVisibilityMatrixElement(matrix, layout, 1, 0) +
        row2Scale * gaussianVisibilityMatrixElement(matrix, layout, 2, 0) +
        row3Scale * gaussianVisibilityMatrixElement(matrix, layout, 3, 0);
    plane.normal[1] =
        row0Scale * gaussianVisibilityMatrixElement(matrix, layout, 0, 1) +
        row1Scale * gaussianVisibilityMatrixElement(matrix, layout, 1, 1) +
        row2Scale * gaussianVisibilityMatrixElement(matrix, layout, 2, 1) +
        row3Scale * gaussianVisibilityMatrixElement(matrix, layout, 3, 1);
    plane.normal[2] =
        row0Scale * gaussianVisibilityMatrixElement(matrix, layout, 0, 2) +
        row1Scale * gaussianVisibilityMatrixElement(matrix, layout, 1, 2) +
        row2Scale * gaussianVisibilityMatrixElement(matrix, layout, 2, 2) +
        row3Scale * gaussianVisibilityMatrixElement(matrix, layout, 3, 2);
    plane.offset =
        row0Scale * gaussianVisibilityMatrixElement(matrix, layout, 0, 3) +
        row1Scale * gaussianVisibilityMatrixElement(matrix, layout, 1, 3) +
        row2Scale * gaussianVisibilityMatrixElement(matrix, layout, 2, 3) +
        row3Scale * gaussianVisibilityMatrixElement(matrix, layout, 3, 3);
    return plane;
}

inline GaussianFrustumParams makeGaussianFrustumParamsFromClipMatrix(
    const float* clipMatrix,
    GaussianVisibilityDepthRange depthRange = GaussianVisibilityDepthRange::ZeroToOne,
    GaussianVisibilityMatrixLayout layout = GaussianVisibilityMatrixLayout::ColumnMajor,
    float radiusMultiplier = kGaussianVisibilityDefaultClipRadiusMultiplier)
{
    GaussianFrustumParams params;
    params.radiusMultiplier = radiusMultiplier;

    if (clipMatrix == nullptr) {
        return params;
    }

    params.planes[static_cast<std::size_t>(GaussianFrustumPlane::Left)] =
        makeGaussianClipPlaneFromMatrixRows(clipMatrix, layout, 1.0f, 0.0f, 0.0f, 1.0f);
    params.planes[static_cast<std::size_t>(GaussianFrustumPlane::Right)] =
        makeGaussianClipPlaneFromMatrixRows(clipMatrix, layout, -1.0f, 0.0f, 0.0f, 1.0f);
    params.planes[static_cast<std::size_t>(GaussianFrustumPlane::Bottom)] =
        makeGaussianClipPlaneFromMatrixRows(clipMatrix, layout, 0.0f, 1.0f, 0.0f, 1.0f);
    params.planes[static_cast<std::size_t>(GaussianFrustumPlane::Top)] =
        makeGaussianClipPlaneFromMatrixRows(clipMatrix, layout, 0.0f, -1.0f, 0.0f, 1.0f);
    params.planes[static_cast<std::size_t>(GaussianFrustumPlane::Near)] =
        depthRange == GaussianVisibilityDepthRange::ZeroToOne ?
        makeGaussianClipPlaneFromMatrixRows(clipMatrix, layout, 0.0f, 0.0f, 1.0f, 0.0f) :
        makeGaussianClipPlaneFromMatrixRows(clipMatrix, layout, 0.0f, 0.0f, 1.0f, 1.0f);
    params.planes[static_cast<std::size_t>(GaussianFrustumPlane::Far)] =
        makeGaussianClipPlaneFromMatrixRows(clipMatrix, layout, 0.0f, 0.0f, -1.0f, 1.0f);

    for (std::size_t index = 0; index < kGaussianVisibilityFrustumPlaneCount; ++index) {
        normalizeGaussianClipPlane(params.planes[index]);
    }

    params.planeCount = kGaussianVisibilityFrustumPlaneCount;
    params.enabled = true;
    return params;
}

inline GaussianFrustumParams makeGaussianFrustumParamsFromClipMatrix(
    const std::array<float, 16>& clipMatrix,
    GaussianVisibilityDepthRange depthRange = GaussianVisibilityDepthRange::ZeroToOne,
    GaussianVisibilityMatrixLayout layout = GaussianVisibilityMatrixLayout::ColumnMajor,
    float radiusMultiplier = kGaussianVisibilityDefaultClipRadiusMultiplier)
{
    return makeGaussianFrustumParamsFromClipMatrix(clipMatrix.data(), depthRange, layout, radiusMultiplier);
}

inline float gaussianMaximumAxisScale(const GaussianRecord& gaussian)
{
    return std::max(
        std::abs(gaussian.scale[0]),
        std::max(std::abs(gaussian.scale[1]), std::abs(gaussian.scale[2])));
}

inline float gaussianVisibilitySupportRadius(const GaussianRecord& gaussian, float radiusMultiplier)
{
    if (!std::isfinite(radiusMultiplier) || radiusMultiplier < 0.0f) {
        return 0.0f;
    }

    const float maximumScale = gaussianMaximumAxisScale(gaussian);
    return std::isfinite(maximumScale) ? maximumScale * radiusMultiplier : 0.0f;
}

inline bool gaussianPassesAlphaCull(const GaussianRecord& gaussian, const GaussianVisibilitySettings& settings)
{
    if (!settings.enableAlphaCull) {
        return true;
    }

    const float threshold = std::max(settings.alphaCullThreshold, 0.0f);
    return gaussian.color[3] >= threshold;
}

inline bool gaussianPassesScaleCull(
    const GaussianRecord& gaussian,
    const GaussianVisibilitySettings& settings,
    GaussianVisibilityCullReason* reason = nullptr)
{
    if (!settings.enableScaleCull) {
        return true;
    }

    const float maximumScale = gaussianMaximumAxisScale(gaussian);
    const float minimumThreshold = std::max(settings.minimumScaleCullThreshold, 0.0f);
    if (maximumScale < minimumThreshold) {
        if (reason != nullptr) {
            *reason = GaussianVisibilityCullReason::ScaleBelowThreshold;
        }
        return false;
    }

    if (std::isfinite(settings.maximumScaleCullThreshold) && maximumScale > settings.maximumScaleCullThreshold) {
        if (reason != nullptr) {
            *reason = GaussianVisibilityCullReason::ScaleAboveThreshold;
        }
        return false;
    }

    return true;
}

template <std::size_t PlaneCapacity>
inline std::size_t configuredGaussianVisibilityPlaneCount(
    const std::array<GaussianClipPlane, PlaneCapacity>&,
    std::size_t planeCount)
{
    return std::min(planeCount, PlaneCapacity);
}

template <std::size_t PlaneCapacity>
inline std::size_t countInvalidGaussianVisibilityPlanes(
    const std::array<GaussianClipPlane, PlaneCapacity>& planes,
    std::size_t planeCount)
{
    const std::size_t configuredPlaneCount = configuredGaussianVisibilityPlaneCount(planes, planeCount);
    std::size_t invalidPlaneCount = 0;
    for (std::size_t index = 0; index < configuredPlaneCount; ++index) {
        if (!isUsableGaussianClipPlane(planes[index])) {
            ++invalidPlaneCount;
        }
    }
    return invalidPlaneCount;
}

template <std::size_t PlaneCapacity>
inline bool gaussianPassesVisibilityPlanes(
    const GaussianRecord& gaussian,
    const std::array<GaussianClipPlane, PlaneCapacity>& planes,
    std::size_t planeCount,
    bool enabled,
    float radiusMultiplier,
    std::size_t* invalidPlaneCount = nullptr)
{
    if (!enabled || planeCount == 0) {
        return true;
    }

    const std::size_t configuredPlaneCount = configuredGaussianVisibilityPlaneCount(planes, planeCount);
    const float supportRadius = gaussianVisibilitySupportRadius(gaussian, radiusMultiplier);
    for (std::size_t index = 0; index < configuredPlaneCount; ++index) {
        const GaussianClipPlane& plane = planes[index];
        if (!isUsableGaussianClipPlane(plane)) {
            if (invalidPlaneCount != nullptr) {
                ++(*invalidPlaneCount);
            }
            continue;
        }

        if (gaussianClipPlaneDistance(plane, gaussian) + supportRadius * gaussianClipPlaneNormalLength(plane) < 0.0f) {
            return false;
        }
    }

    return true;
}

inline bool gaussianPassesClipParams(
    const GaussianRecord& gaussian,
    const GaussianClipParams& params,
    std::size_t* invalidClipPlaneCount = nullptr)
{
    return gaussianPassesVisibilityPlanes(
        gaussian,
        params.planes,
        params.planeCount,
        params.enabled,
        params.radiusMultiplier,
        invalidClipPlaneCount);
}

inline bool gaussianPassesFrustumParams(
    const GaussianRecord& gaussian,
    const GaussianFrustumParams& params,
    std::size_t* invalidFrustumPlaneCount = nullptr)
{
    return gaussianPassesVisibilityPlanes(
        gaussian,
        params.planes,
        params.planeCount,
        params.enabled,
        params.radiusMultiplier,
        invalidFrustumPlaneCount);
}

inline bool isGaussianVisible(
    const GaussianRecord& gaussian,
    const GaussianVisibilitySettings& settings = GaussianVisibilitySettings{},
    GaussianVisibilityCullReason* reason = nullptr)
{
    if (reason != nullptr) {
        *reason = GaussianVisibilityCullReason::Visible;
    }

    if (settings.rejectInvalidRecords && !isValidGaussianRecordForGpuUpload(gaussian)) {
        if (reason != nullptr) {
            *reason = GaussianVisibilityCullReason::InvalidRecord;
        }
        return false;
    }

    if (!gaussianPassesAlphaCull(gaussian, settings)) {
        if (reason != nullptr) {
            *reason = GaussianVisibilityCullReason::AlphaBelowThreshold;
        }
        return false;
    }

    GaussianVisibilityCullReason scaleCullReason = GaussianVisibilityCullReason::Visible;
    if (!gaussianPassesScaleCull(gaussian, settings, &scaleCullReason)) {
        if (reason != nullptr) {
            *reason = scaleCullReason;
        }
        return false;
    }

    if (!gaussianPassesFrustumParams(gaussian, settings.frustum)) {
        if (reason != nullptr) {
            *reason = GaussianVisibilityCullReason::OutsideFrustum;
        }
        return false;
    }

    if (!gaussianPassesClipParams(gaussian, settings.clip)) {
        if (reason != nullptr) {
            *reason = GaussianVisibilityCullReason::OutsideClipVolume;
        }
        return false;
    }

    return true;
}

inline GaussianVisibilityDiagnostics estimateGaussianVisibility(
    const GaussianRecord* gaussians,
    std::size_t count,
    const GaussianVisibilitySettings& settings = GaussianVisibilitySettings{})
{
    GaussianVisibilityDiagnostics diagnostics;
    diagnostics.inputCount = count;
    diagnostics.visibleBudget = settings.visibleBudget;
    diagnostics.configuredFrustumPlaneCount =
        configuredGaussianVisibilityPlaneCount(settings.frustum.planes, settings.frustum.planeCount);
    diagnostics.configuredClipPlaneCount =
        configuredGaussianVisibilityPlaneCount(settings.clip.planes, settings.clip.planeCount);
    diagnostics.invalidFrustumPlaneCount =
        countInvalidGaussianVisibilityPlanes(settings.frustum.planes, settings.frustum.planeCount);
    diagnostics.invalidClipPlaneCount =
        countInvalidGaussianVisibilityPlanes(settings.clip.planes, settings.clip.planeCount);

    if (gaussians == nullptr) {
        diagnostics.invalidRecordCount = count;
        return diagnostics;
    }

    for (std::size_t index = 0; index < count; ++index) {
        GaussianVisibilityCullReason reason = GaussianVisibilityCullReason::Visible;
        if (isGaussianVisible(gaussians[index], settings, &reason)) {
            ++diagnostics.visibleCount;
            continue;
        }

        switch (reason) {
        case GaussianVisibilityCullReason::InvalidRecord:
            ++diagnostics.invalidRecordCount;
            break;
        case GaussianVisibilityCullReason::AlphaBelowThreshold:
            ++diagnostics.alphaCullCount;
            break;
        case GaussianVisibilityCullReason::ScaleBelowThreshold:
            ++diagnostics.scaleBelowThresholdCount;
            break;
        case GaussianVisibilityCullReason::ScaleAboveThreshold:
            ++diagnostics.scaleAboveThresholdCount;
            break;
        case GaussianVisibilityCullReason::OutsideFrustum:
            ++diagnostics.frustumCullCount;
            break;
        case GaussianVisibilityCullReason::OutsideClipVolume:
            ++diagnostics.clipCullCount;
            break;
        case GaussianVisibilityCullReason::Visible:
            break;
        }
    }

    diagnostics.budgetedVisibleCount = settings.visibleBudget > 0 ?
        std::min(diagnostics.visibleCount, settings.visibleBudget) :
        diagnostics.visibleCount;
    return diagnostics;
}

inline std::size_t estimateVisibleCount(
    const GaussianRecord* gaussians,
    std::size_t count,
    const GaussianVisibilitySettings& settings = GaussianVisibilitySettings{})
{
    return estimateGaussianVisibility(gaussians, count, settings).visibleCount;
}

inline std::size_t estimateBudgetedVisibleCount(
    const GaussianRecord* gaussians,
    std::size_t count,
    const GaussianVisibilitySettings& settings = GaussianVisibilitySettings{})
{
    return estimateGaussianVisibility(gaussians, count, settings).budgetedVisibleCount;
}

} // namespace mesh2splat::core
