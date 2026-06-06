#pragma once

#include "GaussianData.hpp"
#include "NumericUtils.hpp"

#include <cstddef>
#include <cstdint>
#include <limits>

namespace mesh2splat::core {

enum class ConversionQualityPreset : uint32_t {
    Low = 1,
    Balanced = 4,
    High = 9,
    Ultra = 16,
};

constexpr uint32_t kLowConversionSamplesPerTriangle = 1;
constexpr uint32_t kBalancedConversionSamplesPerTriangle = 4;
constexpr uint32_t kHighConversionSamplesPerTriangle = 9;
constexpr uint32_t kUltraConversionSamplesPerTriangle = 16;
constexpr uint32_t kDefaultConversionSamplesPerTriangle = kBalancedConversionSamplesPerTriangle;
constexpr uint32_t kMaxEffectiveConversionSamplesPerTriangle = kHighConversionSamplesPerTriangle;
constexpr std::size_t kDefaultConversionGaussianCapacity = kDefaultMaxGaussianCount;

struct ConversionSettingsLimits {
    uint32_t minRequestedSamplesPerTriangle = kLowConversionSamplesPerTriangle;
    uint32_t maxRequestedSamplesPerTriangle = kUltraConversionSamplesPerTriangle;
    uint32_t maxEffectiveSamplesPerTriangle = kMaxEffectiveConversionSamplesPerTriangle;
    std::size_t maxGaussianCapacity = kDefaultConversionGaussianCapacity;
};

struct ConversionSettings {
    ConversionQualityPreset qualityPreset = ConversionQualityPreset::Balanced;
    uint32_t requestedSamplesPerTriangle = kDefaultConversionSamplesPerTriangle;
    uint32_t effectiveSamplesPerTriangle = kDefaultConversionSamplesPerTriangle;
    bool enabled = true;
    bool replacesSceneResources = false;
    bool revertsSamplesOnFailure = false;
    uint32_t previousSamplesPerTriangle = kDefaultConversionSamplesPerTriangle;
};

struct ConversionCapacitySnapshot {
    std::size_t plannedGaussianCapacity = 0;
    std::size_t allocatedGaussianCapacity = 0;
    std::size_t allocatedSortCapacity = 0;
    std::size_t gaussianRecordStrideBytes = kGaussianRecordStrideBytes;

    bool hasPlannedOutput() const
    {
        return plannedGaussianCapacity > 0;
    }

    bool fitsAllocatedBuffers() const
    {
        return plannedGaussianCapacity <= allocatedGaussianCapacity &&
            plannedGaussianCapacity <= allocatedSortCapacity;
    }
};

enum class ConversionSettingsValidationFlag : uint32_t {
    None = 0,
    UnknownQualityPreset = 1u << 0,
    RequestedSamplesOutOfRange = 1u << 1,
    SamplesRequireNormalization = 1u << 2,
    EffectiveSamplesOutOfRange = 1u << 3,
    PreviousSamplesRequireNormalization = 1u << 4,
    PlannedCapacityIsZero = 1u << 5,
    PlannedCapacityExceedsLimit = 1u << 6,
    PlannedCapacityExceedsUInt32 = 1u << 7,
    PlannedCapacityByteSizeOverflow = 1u << 8,
    GaussianCapacityTooSmall = 1u << 9,
    SortCapacityTooSmall = 1u << 10,
    InvalidGaussianRecordStride = 1u << 11,
};

using ConversionSettingsValidationFlags = uint32_t;

struct ConversionSettingsValidation {
    ConversionSettingsValidationFlags flags = 0;
    uint32_t normalizedSamplesPerTriangle = kDefaultConversionSamplesPerTriangle;
    std::size_t plannedByteSize = 0;

    bool valid() const
    {
        return flags == 0;
    }

    bool has(ConversionSettingsValidationFlag flag) const
    {
        return (flags & static_cast<ConversionSettingsValidationFlags>(flag)) != 0;
    }
};

constexpr ConversionSettingsValidationFlags toConversionSettingsValidationFlags(
    ConversionSettingsValidationFlag flag)
{
    return static_cast<ConversionSettingsValidationFlags>(flag);
}

constexpr bool isKnownConversionQualityPreset(ConversionQualityPreset preset)
{
    switch (preset) {
    case ConversionQualityPreset::Low:
    case ConversionQualityPreset::Balanced:
    case ConversionQualityPreset::High:
    case ConversionQualityPreset::Ultra:
        return true;
    }

    return false;
}

constexpr uint32_t samplesForConversionQualityPreset(ConversionQualityPreset preset)
{
    switch (preset) {
    case ConversionQualityPreset::Low:
        return kLowConversionSamplesPerTriangle;
    case ConversionQualityPreset::Balanced:
        return kBalancedConversionSamplesPerTriangle;
    case ConversionQualityPreset::High:
        return kHighConversionSamplesPerTriangle;
    case ConversionQualityPreset::Ultra:
        return kUltraConversionSamplesPerTriangle;
    }

    return kDefaultConversionSamplesPerTriangle;
}

constexpr ConversionQualityPreset conversionQualityPresetForSamples(uint32_t samplesPerTriangle)
{
    if (samplesPerTriangle <= kLowConversionSamplesPerTriangle) {
        return ConversionQualityPreset::Low;
    }
    if (samplesPerTriangle <= kBalancedConversionSamplesPerTriangle) {
        return ConversionQualityPreset::Balanced;
    }
    if (samplesPerTriangle <= kHighConversionSamplesPerTriangle) {
        return ConversionQualityPreset::High;
    }
    return ConversionQualityPreset::Ultra;
}

constexpr uint32_t normalizeConversionSamplesPerTriangle(uint32_t samplesPerTriangle)
{
    if (samplesPerTriangle <= kLowConversionSamplesPerTriangle) {
        return kLowConversionSamplesPerTriangle;
    }
    if (samplesPerTriangle <= kBalancedConversionSamplesPerTriangle) {
        return kBalancedConversionSamplesPerTriangle;
    }
    return kHighConversionSamplesPerTriangle;
}

constexpr uint32_t clampRequestedConversionSamplesPerTriangle(
    uint32_t samplesPerTriangle,
    const ConversionSettingsLimits& limits = {})
{
    const NumericRange<uint32_t> range =
        orderedRange(limits.minRequestedSamplesPerTriangle, limits.maxRequestedSamplesPerTriangle);
    return safeClamp(samplesPerTriangle, range.minimum, range.maximum);
}

constexpr uint32_t clampEffectiveConversionSamplesPerTriangle(
    uint32_t samplesPerTriangle,
    const ConversionSettingsLimits& limits = {})
{
    const uint32_t normalizedSamples = normalizeConversionSamplesPerTriangle(samplesPerTriangle);
    const uint32_t maxEffectiveSamples =
        normalizeConversionSamplesPerTriangle(limits.maxEffectiveSamplesPerTriangle);
    return safeClamp(normalizedSamples, kLowConversionSamplesPerTriangle, maxEffectiveSamples);
}

inline ConversionSettings makeConversionSettingsForQualityPreset(
    ConversionQualityPreset preset,
    const ConversionSettingsLimits& limits = {})
{
    ConversionSettings settings;
    settings.qualityPreset = isKnownConversionQualityPreset(preset) ? preset : ConversionQualityPreset::Balanced;
    settings.requestedSamplesPerTriangle =
        clampRequestedConversionSamplesPerTriangle(samplesForConversionQualityPreset(settings.qualityPreset), limits);
    settings.effectiveSamplesPerTriangle =
        clampEffectiveConversionSamplesPerTriangle(settings.requestedSamplesPerTriangle, limits);
    settings.previousSamplesPerTriangle = settings.effectiveSamplesPerTriangle;
    return settings;
}

inline ConversionSettings makeConversionSettingsFromRequestedSamples(
    uint32_t requestedSamples,
    bool replacesScene = false,
    bool revertsOnFailure = false,
    uint32_t previousSamples = kDefaultConversionSamplesPerTriangle,
    const ConversionSettingsLimits& limits = {})
{
    ConversionSettings settings;
    settings.qualityPreset = conversionQualityPresetForSamples(requestedSamples);
    settings.requestedSamplesPerTriangle = clampRequestedConversionSamplesPerTriangle(requestedSamples, limits);
    settings.effectiveSamplesPerTriangle =
        clampEffectiveConversionSamplesPerTriangle(settings.requestedSamplesPerTriangle, limits);
    settings.replacesSceneResources = replacesScene;
    settings.revertsSamplesOnFailure = revertsOnFailure;
    settings.previousSamplesPerTriangle = clampEffectiveConversionSamplesPerTriangle(previousSamples, limits);
    return settings;
}

inline ConversionSettings makeDefaultConversionSettings()
{
    return makeConversionSettingsForQualityPreset(ConversionQualityPreset::Balanced);
}

constexpr std::size_t maxUInt32AsSize()
{
    return static_cast<std::size_t>(std::numeric_limits<uint32_t>::max());
}

constexpr bool estimateConversionGaussianCapacity(
    std::size_t triangleCount,
    uint32_t samplesPerTriangle,
    std::size_t& gaussianCapacity)
{
    return checkedMultiply(
        triangleCount,
        static_cast<std::size_t>(normalizeConversionSamplesPerTriangle(samplesPerTriangle)),
        gaussianCapacity);
}

constexpr bool estimateConversionGaussianByteSize(
    std::size_t gaussianCapacity,
    std::size_t gaussianRecordStrideBytes,
    std::size_t& byteSize)
{
    return checkedMultiply(gaussianCapacity, gaussianRecordStrideBytes, byteSize);
}

inline bool conversionGaussianCapacityFits(
    std::size_t gaussianCapacity,
    const ConversionSettingsLimits& limits = {})
{
    return gaussianCapacity > 0 &&
        gaussianCapacity <= limits.maxGaussianCapacity &&
        gaussianCountFitsBuffer(gaussianCapacity);
}

inline ConversionCapacitySnapshot makeConversionCapacitySnapshot(
    std::size_t plannedGaussianCapacity,
    std::size_t allocatedGaussianCapacity,
    std::size_t allocatedSortCapacity,
    std::size_t gaussianRecordStrideBytes = kGaussianRecordStrideBytes)
{
    ConversionCapacitySnapshot capacity;
    capacity.plannedGaussianCapacity = plannedGaussianCapacity;
    capacity.allocatedGaussianCapacity = allocatedGaussianCapacity;
    capacity.allocatedSortCapacity = allocatedSortCapacity;
    capacity.gaussianRecordStrideBytes = gaussianRecordStrideBytes;
    return capacity;
}

inline ConversionSettingsValidation validateConversionSettings(
    const ConversionSettings& settings,
    const ConversionCapacitySnapshot* capacity = nullptr,
    const ConversionSettingsLimits& limits = {})
{
    ConversionSettingsValidation validation;
    const NumericRange<uint32_t> requestedRange =
        orderedRange(limits.minRequestedSamplesPerTriangle, limits.maxRequestedSamplesPerTriangle);

    if (!isKnownConversionQualityPreset(settings.qualityPreset)) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::UnknownQualityPreset);
    }
    if (!requestedRange.contains(settings.requestedSamplesPerTriangle)) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::RequestedSamplesOutOfRange);
    }

    validation.normalizedSamplesPerTriangle =
        clampEffectiveConversionSamplesPerTriangle(settings.requestedSamplesPerTriangle, limits);
    if (settings.effectiveSamplesPerTriangle != validation.normalizedSamplesPerTriangle) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::SamplesRequireNormalization);
    }
    if (settings.effectiveSamplesPerTriangle < kLowConversionSamplesPerTriangle ||
        settings.effectiveSamplesPerTriangle >
            normalizeConversionSamplesPerTriangle(limits.maxEffectiveSamplesPerTriangle)) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::EffectiveSamplesOutOfRange);
    }
    if (settings.previousSamplesPerTriangle !=
        clampEffectiveConversionSamplesPerTriangle(settings.previousSamplesPerTriangle, limits)) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::PreviousSamplesRequireNormalization);
    }

    if (capacity == nullptr) {
        return validation;
    }

    if (capacity->plannedGaussianCapacity == 0) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::PlannedCapacityIsZero);
    }
    if (capacity->plannedGaussianCapacity > limits.maxGaussianCapacity) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::PlannedCapacityExceedsLimit);
    }
    if (capacity->plannedGaussianCapacity > maxUInt32AsSize()) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::PlannedCapacityExceedsUInt32);
    }
    if (capacity->gaussianRecordStrideBytes != kGaussianRecordStrideBytes) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::InvalidGaussianRecordStride);
    }
    if (!estimateConversionGaussianByteSize(
            capacity->plannedGaussianCapacity,
            capacity->gaussianRecordStrideBytes,
            validation.plannedByteSize)) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::PlannedCapacityByteSizeOverflow);
    }
    if (capacity->plannedGaussianCapacity > capacity->allocatedGaussianCapacity) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::GaussianCapacityTooSmall);
    }
    if (capacity->plannedGaussianCapacity > capacity->allocatedSortCapacity) {
        validation.flags |= toConversionSettingsValidationFlags(
            ConversionSettingsValidationFlag::SortCapacityTooSmall);
    }

    return validation;
}

inline ConversionSettings clampConversionSettings(
    ConversionSettings settings,
    const ConversionSettingsLimits& limits = {})
{
    if (!isKnownConversionQualityPreset(settings.qualityPreset)) {
        settings.qualityPreset = ConversionQualityPreset::Balanced;
    }
    settings.requestedSamplesPerTriangle =
        clampRequestedConversionSamplesPerTriangle(settings.requestedSamplesPerTriangle, limits);
    settings.effectiveSamplesPerTriangle =
        clampEffectiveConversionSamplesPerTriangle(settings.requestedSamplesPerTriangle, limits);
    settings.previousSamplesPerTriangle =
        clampEffectiveConversionSamplesPerTriangle(settings.previousSamplesPerTriangle, limits);
    return settings;
}

} // namespace mesh2splat::core
