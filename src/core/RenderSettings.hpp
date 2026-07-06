#pragma once

#include "ConversionSettings.hpp"
#include "NumericUtils.hpp"

#include <cstddef>
#include <cstdint>

namespace mesh2splat::core {

enum class RenderMode : uint32_t {
    Final = 0,
    MeshOnly = 1,
    GaussianOnly = 2,
    Albedo = 3,
    Depth = 4,
    Normal = 5,
    Geometry = 6,
    Overdraw = 7,
    Pbr = 8,
};

enum class RenderQualityPreset : uint32_t {
    Low = 0,
    Balanced = 1,
    High = 2,
    Ultra = 3,
};

enum class RenderDebugFlag : uint32_t {
    None = 0,
    ShowBounds = 1u << 0,
    ShowMeshWireframe = 1u << 1,
    ShowGaussianCenters = 1u << 2,
    ShowGaussianTiles = 1u << 3,
    ShowSortOrder = 1u << 4,
    FreezeCamera = 1u << 5,
    DisableToneMapping = 1u << 6,
    ForceLinearOutput = 1u << 7,
};

using RenderDebugFlags = uint32_t;

constexpr float kDefaultGaussianScale = 1.0f;
constexpr float kDefaultExposure = 1.0f;
constexpr float kDefaultGamma = 2.2f;
constexpr float kDefaultBackgroundBrightness = 0.04f;
constexpr float kDefaultLightPositionX = 3.0f;
constexpr float kDefaultLightPositionY = 4.0f;
constexpr float kDefaultLightPositionZ = 2.5f;
constexpr float kDefaultLightIntensity = 1.0f;
constexpr float kDefaultLightColorRed = 1.0f;
constexpr float kDefaultLightColorGreen = 0.95f;
constexpr float kDefaultLightColorBlue = 0.85f;
constexpr RenderDebugFlags kNoRenderDebugFlags = 0;
constexpr RenderDebugFlags kKnownRenderDebugFlags =
    static_cast<RenderDebugFlags>(RenderDebugFlag::ShowBounds) |
    static_cast<RenderDebugFlags>(RenderDebugFlag::ShowMeshWireframe) |
    static_cast<RenderDebugFlags>(RenderDebugFlag::ShowGaussianCenters) |
    static_cast<RenderDebugFlags>(RenderDebugFlag::ShowGaussianTiles) |
    static_cast<RenderDebugFlags>(RenderDebugFlag::ShowSortOrder) |
    static_cast<RenderDebugFlags>(RenderDebugFlag::FreezeCamera) |
    static_cast<RenderDebugFlags>(RenderDebugFlag::DisableToneMapping) |
    static_cast<RenderDebugFlags>(RenderDebugFlag::ForceLinearOutput);

struct RenderSettingsLimits {
    float minGaussianScale = 0.1f;
    float maxGaussianScale = 8.0f;
    float minExposure = 0.0f;
    float maxExposure = 16.0f;
    float minGamma = 0.1f;
    float maxGamma = 4.0f;
    float minBackgroundBrightness = 0.0f;
    float maxBackgroundBrightness = 1.0f;
    float minLightPosition = -100.0f;
    float maxLightPosition = 100.0f;
    float minLightIntensity = 0.0f;
    float maxLightIntensity = 1000.0f;
    float minLightColor = 0.0f;
    float maxLightColor = 4.0f;
    float minSplitScreenPosition = 0.0f;
    float maxSplitScreenPosition = 1.0f;
    uint32_t minConversionSamplesPerTriangle = kLowConversionSamplesPerTriangle;
    uint32_t maxConversionSamplesPerTriangle = kUltraConversionSamplesPerTriangle;
    uint32_t maxEffectiveConversionSamplesPerTriangle = kMaxEffectiveConversionSamplesPerTriangle;
};

struct RenderSettings {
    RenderMode mode = RenderMode::Final;
    RenderQualityPreset qualityPreset = RenderQualityPreset::Balanced;
    bool enableMeshRendering = true;
    bool enableGaussianRendering = true;
    bool enableGaussianSorting = true;
    bool enableMeshToGaussianConversion = true;
    bool enableDepthTest = true;
    bool enableSplitScreen = false;
    float splitScreenPosition = 0.5f;
    float gaussianScale = kDefaultGaussianScale;
    float exposure = kDefaultExposure;
    float gamma = kDefaultGamma;
    float backgroundBrightness = kDefaultBackgroundBrightness;
    bool enableLighting = true;
    float lightPosition[3] = {
        kDefaultLightPositionX,
        kDefaultLightPositionY,
        kDefaultLightPositionZ,
    };
    float lightIntensity = kDefaultLightIntensity;
    float lightColor[3] = {
        kDefaultLightColorRed,
        kDefaultLightColorGreen,
        kDefaultLightColorBlue,
    };
    RenderDebugFlags debugFlags = kNoRenderDebugFlags;
    uint32_t conversionSamplesPerTriangle = kDefaultConversionSamplesPerTriangle;
};

struct RenderSettingsSnapshot {
    RenderMode mode = RenderMode::Final;
    RenderQualityPreset qualityPreset = RenderQualityPreset::Balanced;
    bool meshRenderingEnabled = true;
    bool gaussianRenderingEnabled = true;
    bool gaussianSortingEnabled = true;
    bool meshToGaussianConversionEnabled = true;
    bool depthTestEnabled = true;
    bool splitScreenEnabled = false;
    float splitScreenPosition = 0.5f;
    float gaussianScale = kDefaultGaussianScale;
    float exposure = kDefaultExposure;
    float gamma = kDefaultGamma;
    float backgroundBrightness = kDefaultBackgroundBrightness;
    bool lightingEnabled = true;
    float lightPosition[3] = {
        kDefaultLightPositionX,
        kDefaultLightPositionY,
        kDefaultLightPositionZ,
    };
    float lightIntensity = kDefaultLightIntensity;
    float lightColor[3] = {
        kDefaultLightColorRed,
        kDefaultLightColorGreen,
        kDefaultLightColorBlue,
    };
    RenderDebugFlags debugFlags = kNoRenderDebugFlags;
    uint32_t requestedConversionSamplesPerTriangle = kDefaultConversionSamplesPerTriangle;
    uint32_t conversionSamplesPerTriangle = kDefaultConversionSamplesPerTriangle;

    bool drawsMesh() const
    {
        return meshRenderingEnabled && mode != RenderMode::GaussianOnly;
    }

    bool drawsGaussians() const
    {
        return gaussianRenderingEnabled && mode != RenderMode::MeshOnly;
    }

    bool sortsGaussians() const
    {
        return drawsGaussians() && gaussianSortingEnabled;
    }

    bool convertsMeshToGaussians() const
    {
        return meshToGaussianConversionEnabled && conversionSamplesPerTriangle != 0;
    }
};

enum class RenderSettingsValidationFlag : uint32_t {
    None = 0,
    UnknownRenderMode = 1u << 0,
    UnknownQualityPreset = 1u << 1,
    EmptyRenderOutput = 1u << 2,
    UnknownDebugFlags = 1u << 3,
    NonFiniteGaussianScale = 1u << 4,
    GaussianScaleOutOfRange = 1u << 5,
    NonFiniteExposure = 1u << 6,
    ExposureOutOfRange = 1u << 7,
    NonFiniteGamma = 1u << 8,
    GammaOutOfRange = 1u << 9,
    ConversionSamplesOutOfRange = 1u << 10,
    ConversionSamplesRequireNormalization = 1u << 11,
    NonFiniteBackgroundBrightness = 1u << 12,
    BackgroundBrightnessOutOfRange = 1u << 13,
    NonFiniteLightPosition = 1u << 14,
    LightPositionOutOfRange = 1u << 15,
    NonFiniteLightIntensity = 1u << 16,
    LightIntensityOutOfRange = 1u << 17,
    NonFiniteLightColor = 1u << 18,
    LightColorOutOfRange = 1u << 19,
};

using RenderSettingsValidationFlags = uint32_t;

struct RenderSettingsValidation {
    RenderSettingsValidationFlags flags = 0;

    bool valid() const
    {
        return flags == 0;
    }

    bool has(RenderSettingsValidationFlag flag) const
    {
        return (flags & static_cast<RenderSettingsValidationFlags>(flag)) != 0;
    }
};

constexpr RenderSettingsValidationFlags toRenderSettingsValidationFlags(RenderSettingsValidationFlag flag)
{
    return static_cast<RenderSettingsValidationFlags>(flag);
}

constexpr RenderDebugFlags toRenderDebugFlags(RenderDebugFlag flag)
{
    return static_cast<RenderDebugFlags>(flag);
}

constexpr RenderDebugFlags operator|(RenderDebugFlag lhs, RenderDebugFlag rhs)
{
    return toRenderDebugFlags(lhs) | toRenderDebugFlags(rhs);
}

constexpr RenderDebugFlags operator|(RenderDebugFlags flags, RenderDebugFlag flag)
{
    return flags | toRenderDebugFlags(flag);
}

constexpr RenderDebugFlags operator&(RenderDebugFlags flags, RenderDebugFlag flag)
{
    return flags & toRenderDebugFlags(flag);
}

constexpr bool hasRenderDebugFlag(RenderDebugFlags flags, RenderDebugFlag flag)
{
    return (flags & flag) != 0;
}

constexpr RenderDebugFlags withRenderDebugFlag(RenderDebugFlags flags, RenderDebugFlag flag, bool enabled)
{
    return enabled ? (flags | flag) : (flags & ~toRenderDebugFlags(flag));
}

inline void setRenderDebugFlag(RenderSettings& settings, RenderDebugFlag flag, bool enabled)
{
    settings.debugFlags = withRenderDebugFlag(settings.debugFlags, flag, enabled);
}

constexpr bool isKnownRenderMode(RenderMode mode)
{
    switch (mode) {
    case RenderMode::Final:
    case RenderMode::MeshOnly:
    case RenderMode::GaussianOnly:
    case RenderMode::Albedo:
    case RenderMode::Depth:
    case RenderMode::Normal:
    case RenderMode::Geometry:
    case RenderMode::Overdraw:
    case RenderMode::Pbr:
        return true;
    }

    return false;
}

constexpr bool isKnownRenderQualityPreset(RenderQualityPreset preset)
{
    switch (preset) {
    case RenderQualityPreset::Low:
    case RenderQualityPreset::Balanced:
    case RenderQualityPreset::High:
    case RenderQualityPreset::Ultra:
        return true;
    }

    return false;
}

constexpr bool renderModeAllowsMesh(RenderMode mode)
{
    return mode != RenderMode::GaussianOnly;
}

constexpr bool renderModeAllowsGaussians(RenderMode mode)
{
    return mode != RenderMode::MeshOnly;
}

inline bool wantsMeshRender(const RenderSettings& settings)
{
    return settings.enableMeshRendering && renderModeAllowsMesh(settings.mode);
}

inline bool wantsGaussianRender(const RenderSettings& settings)
{
    return settings.enableGaussianRendering && renderModeAllowsGaussians(settings.mode);
}

inline bool wantsGaussianSort(const RenderSettings& settings)
{
    return wantsGaussianRender(settings) && settings.enableGaussianSorting;
}

inline bool wantsMeshToGaussianConversion(const RenderSettings& settings)
{
    return settings.enableMeshToGaussianConversion && settings.conversionSamplesPerTriangle != 0;
}

constexpr ConversionQualityPreset conversionQualityPresetForRenderQualityPreset(RenderQualityPreset preset)
{
    switch (preset) {
    case RenderQualityPreset::Low:
        return ConversionQualityPreset::Low;
    case RenderQualityPreset::Balanced:
        return ConversionQualityPreset::Balanced;
    case RenderQualityPreset::High:
        return ConversionQualityPreset::High;
    case RenderQualityPreset::Ultra:
        return ConversionQualityPreset::Ultra;
    }

    return ConversionQualityPreset::Balanced;
}

constexpr uint32_t requestedConversionSamplesForQualityPreset(RenderQualityPreset preset)
{
    return samplesForConversionQualityPreset(conversionQualityPresetForRenderQualityPreset(preset));
}

constexpr uint32_t conversionSamplesForQualityPreset(RenderQualityPreset preset)
{
    return normalizeConversionSamplesPerTriangle(requestedConversionSamplesForQualityPreset(preset));
}

constexpr bool gaussianSortingEnabledForQualityPreset(RenderQualityPreset preset)
{
    switch (preset) {
    case RenderQualityPreset::Low:
        return false;
    case RenderQualityPreset::Balanced:
    case RenderQualityPreset::High:
    case RenderQualityPreset::Ultra:
        return true;
    }

    return true;
}

constexpr ConversionSettingsLimits conversionLimitsForRenderSettings(const RenderSettingsLimits& limits)
{
    ConversionSettingsLimits conversionLimits;
    conversionLimits.minRequestedSamplesPerTriangle = limits.minConversionSamplesPerTriangle;
    conversionLimits.maxRequestedSamplesPerTriangle = limits.maxConversionSamplesPerTriangle;
    conversionLimits.maxEffectiveSamplesPerTriangle = limits.maxEffectiveConversionSamplesPerTriangle;
    return conversionLimits;
}

inline RenderSettings makeRenderSettingsForQualityPreset(RenderQualityPreset preset)
{
    RenderSettings settings;
    settings.qualityPreset = isKnownRenderQualityPreset(preset) ? preset : RenderQualityPreset::Balanced;
    settings.enableGaussianSorting = gaussianSortingEnabledForQualityPreset(settings.qualityPreset);
    settings.conversionSamplesPerTriangle =
        requestedConversionSamplesForQualityPreset(settings.qualityPreset);
    return settings;
}

inline RenderSettings makeDefaultRenderSettings()
{
    return makeRenderSettingsForQualityPreset(RenderQualityPreset::Balanced);
}

inline uint32_t clampConversionSamplesPerTriangle(
    uint32_t samplesPerTriangle,
    const RenderSettingsLimits& limits = {})
{
    return clampRequestedConversionSamplesPerTriangle(
        samplesPerTriangle,
        conversionLimitsForRenderSettings(limits));
}

inline RenderSettings clampRenderSettings(RenderSettings settings, const RenderSettingsLimits& limits = {})
{
    if (!isKnownRenderMode(settings.mode)) {
        settings.mode = RenderMode::Final;
    }
    if (!isKnownRenderQualityPreset(settings.qualityPreset)) {
        settings.qualityPreset = RenderQualityPreset::Balanced;
    }

    settings.gaussianScale =
        clampFinite(settings.gaussianScale, limits.minGaussianScale, limits.maxGaussianScale, kDefaultGaussianScale);
    settings.exposure = clampFinite(settings.exposure, limits.minExposure, limits.maxExposure, kDefaultExposure);
    settings.gamma = clampFinite(settings.gamma, limits.minGamma, limits.maxGamma, kDefaultGamma);
    settings.backgroundBrightness = clampFinite(
        settings.backgroundBrightness,
        limits.minBackgroundBrightness,
        limits.maxBackgroundBrightness,
        kDefaultBackgroundBrightness);
    settings.lightPosition[0] = clampFinite(
        settings.lightPosition[0],
        limits.minLightPosition,
        limits.maxLightPosition,
        kDefaultLightPositionX);
    settings.lightPosition[1] = clampFinite(
        settings.lightPosition[1],
        limits.minLightPosition,
        limits.maxLightPosition,
        kDefaultLightPositionY);
    settings.lightPosition[2] = clampFinite(
        settings.lightPosition[2],
        limits.minLightPosition,
        limits.maxLightPosition,
        kDefaultLightPositionZ);
    settings.lightIntensity = clampFinite(
        settings.lightIntensity,
        limits.minLightIntensity,
        limits.maxLightIntensity,
        kDefaultLightIntensity);
    settings.lightColor[0] = clampFinite(
        settings.lightColor[0],
        limits.minLightColor,
        limits.maxLightColor,
        kDefaultLightColorRed);
    settings.lightColor[1] = clampFinite(
        settings.lightColor[1],
        limits.minLightColor,
        limits.maxLightColor,
        kDefaultLightColorGreen);
    settings.lightColor[2] = clampFinite(
        settings.lightColor[2],
        limits.minLightColor,
        limits.maxLightColor,
        kDefaultLightColorBlue);
    settings.splitScreenPosition = clampFinite(
        settings.splitScreenPosition,
        limits.minSplitScreenPosition,
        limits.maxSplitScreenPosition,
        0.5f);
    settings.debugFlags &= kKnownRenderDebugFlags;
    settings.conversionSamplesPerTriangle =
        clampConversionSamplesPerTriangle(settings.conversionSamplesPerTriangle, limits);

    if (!wantsMeshRender(settings) && !wantsGaussianRender(settings)) {
        settings.mode = RenderMode::Final;
        settings.enableMeshRendering = true;
    }

    return settings;
}

inline RenderSettingsSnapshot makeRenderSettingsSnapshot(
    const RenderSettings& settings,
    const RenderSettingsLimits& limits = {})
{
    const RenderSettings clampedSettings = clampRenderSettings(settings, limits);
    const ConversionSettings conversionSettings = makeConversionSettingsFromRequestedSamples(
        clampedSettings.conversionSamplesPerTriangle,
        false,
        false,
        clampedSettings.conversionSamplesPerTriangle,
        conversionLimitsForRenderSettings(limits));

    RenderSettingsSnapshot snapshot;
    snapshot.mode = clampedSettings.mode;
    snapshot.qualityPreset = clampedSettings.qualityPreset;
    snapshot.meshRenderingEnabled = clampedSettings.enableMeshRendering;
    snapshot.gaussianRenderingEnabled = clampedSettings.enableGaussianRendering;
    snapshot.gaussianSortingEnabled = clampedSettings.enableGaussianSorting;
    snapshot.meshToGaussianConversionEnabled = clampedSettings.enableMeshToGaussianConversion;
    snapshot.depthTestEnabled = clampedSettings.enableDepthTest;
    snapshot.splitScreenEnabled = clampedSettings.enableSplitScreen;
    snapshot.splitScreenPosition = clampedSettings.splitScreenPosition;
    snapshot.gaussianScale = clampedSettings.gaussianScale;
    snapshot.exposure = clampedSettings.exposure;
    snapshot.gamma = clampedSettings.gamma;
    snapshot.backgroundBrightness = clampedSettings.backgroundBrightness;
    snapshot.lightingEnabled = clampedSettings.enableLighting;
    snapshot.lightPosition[0] = clampedSettings.lightPosition[0];
    snapshot.lightPosition[1] = clampedSettings.lightPosition[1];
    snapshot.lightPosition[2] = clampedSettings.lightPosition[2];
    snapshot.lightIntensity = clampedSettings.lightIntensity;
    snapshot.lightColor[0] = clampedSettings.lightColor[0];
    snapshot.lightColor[1] = clampedSettings.lightColor[1];
    snapshot.lightColor[2] = clampedSettings.lightColor[2];
    snapshot.debugFlags = clampedSettings.debugFlags;
    snapshot.requestedConversionSamplesPerTriangle = conversionSettings.requestedSamplesPerTriangle;
    snapshot.conversionSamplesPerTriangle = conversionSettings.effectiveSamplesPerTriangle;
    return snapshot;
}

inline void validateFiniteRenderValue(
    RenderSettingsValidation& validation,
    float value,
    float minimum,
    float maximum,
    RenderSettingsValidationFlag nonFiniteFlag,
    RenderSettingsValidationFlag outOfRangeFlag)
{
    if (!isFiniteNumber(value)) {
        validation.flags |= toRenderSettingsValidationFlags(nonFiniteFlag);
        return;
    }

    const NumericRange<float> range = orderedRange(minimum, maximum);
    if (!range.contains(value)) {
        validation.flags |= toRenderSettingsValidationFlags(outOfRangeFlag);
    }
}

inline RenderSettingsValidation validateRenderSettings(
    const RenderSettings& settings,
    const RenderSettingsLimits& limits = {})
{
    RenderSettingsValidation validation;
    if (!isKnownRenderMode(settings.mode)) {
        validation.flags |= toRenderSettingsValidationFlags(RenderSettingsValidationFlag::UnknownRenderMode);
    }
    if (!isKnownRenderQualityPreset(settings.qualityPreset)) {
        validation.flags |= toRenderSettingsValidationFlags(RenderSettingsValidationFlag::UnknownQualityPreset);
    }
    if (!wantsMeshRender(settings) && !wantsGaussianRender(settings)) {
        validation.flags |= toRenderSettingsValidationFlags(RenderSettingsValidationFlag::EmptyRenderOutput);
    }
    if ((settings.debugFlags & ~kKnownRenderDebugFlags) != 0) {
        validation.flags |= toRenderSettingsValidationFlags(RenderSettingsValidationFlag::UnknownDebugFlags);
    }

    validateFiniteRenderValue(
        validation,
        settings.gaussianScale,
        limits.minGaussianScale,
        limits.maxGaussianScale,
        RenderSettingsValidationFlag::NonFiniteGaussianScale,
        RenderSettingsValidationFlag::GaussianScaleOutOfRange);
    validateFiniteRenderValue(
        validation,
        settings.exposure,
        limits.minExposure,
        limits.maxExposure,
        RenderSettingsValidationFlag::NonFiniteExposure,
        RenderSettingsValidationFlag::ExposureOutOfRange);
    validateFiniteRenderValue(
        validation,
        settings.gamma,
        limits.minGamma,
        limits.maxGamma,
        RenderSettingsValidationFlag::NonFiniteGamma,
        RenderSettingsValidationFlag::GammaOutOfRange);
    validateFiniteRenderValue(
        validation,
        settings.backgroundBrightness,
        limits.minBackgroundBrightness,
        limits.maxBackgroundBrightness,
        RenderSettingsValidationFlag::NonFiniteBackgroundBrightness,
        RenderSettingsValidationFlag::BackgroundBrightnessOutOfRange);
    validateFiniteRenderValue(
        validation,
        settings.lightPosition[0],
        limits.minLightPosition,
        limits.maxLightPosition,
        RenderSettingsValidationFlag::NonFiniteLightPosition,
        RenderSettingsValidationFlag::LightPositionOutOfRange);
    validateFiniteRenderValue(
        validation,
        settings.lightPosition[1],
        limits.minLightPosition,
        limits.maxLightPosition,
        RenderSettingsValidationFlag::NonFiniteLightPosition,
        RenderSettingsValidationFlag::LightPositionOutOfRange);
    validateFiniteRenderValue(
        validation,
        settings.lightPosition[2],
        limits.minLightPosition,
        limits.maxLightPosition,
        RenderSettingsValidationFlag::NonFiniteLightPosition,
        RenderSettingsValidationFlag::LightPositionOutOfRange);
    validateFiniteRenderValue(
        validation,
        settings.lightIntensity,
        limits.minLightIntensity,
        limits.maxLightIntensity,
        RenderSettingsValidationFlag::NonFiniteLightIntensity,
        RenderSettingsValidationFlag::LightIntensityOutOfRange);
    validateFiniteRenderValue(
        validation,
        settings.lightColor[0],
        limits.minLightColor,
        limits.maxLightColor,
        RenderSettingsValidationFlag::NonFiniteLightColor,
        RenderSettingsValidationFlag::LightColorOutOfRange);
    validateFiniteRenderValue(
        validation,
        settings.lightColor[1],
        limits.minLightColor,
        limits.maxLightColor,
        RenderSettingsValidationFlag::NonFiniteLightColor,
        RenderSettingsValidationFlag::LightColorOutOfRange);
    validateFiniteRenderValue(
        validation,
        settings.lightColor[2],
        limits.minLightColor,
        limits.maxLightColor,
        RenderSettingsValidationFlag::NonFiniteLightColor,
        RenderSettingsValidationFlag::LightColorOutOfRange);

    const NumericRange<uint32_t> conversionSamplesRange =
        orderedRange(limits.minConversionSamplesPerTriangle, limits.maxConversionSamplesPerTriangle);
    if (!conversionSamplesRange.contains(settings.conversionSamplesPerTriangle)) {
        validation.flags |= toRenderSettingsValidationFlags(
            RenderSettingsValidationFlag::ConversionSamplesOutOfRange);
    }
    if (settings.conversionSamplesPerTriangle !=
        clampEffectiveConversionSamplesPerTriangle(
            settings.conversionSamplesPerTriangle,
            conversionLimitsForRenderSettings(limits))) {
        validation.flags |= toRenderSettingsValidationFlags(
            RenderSettingsValidationFlag::ConversionSamplesRequireNormalization);
    }

    return validation;
}

} // namespace mesh2splat::core
