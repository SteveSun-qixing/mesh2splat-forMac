#pragma once

#include "MetalBindings.hpp"

#include <cstddef>
#include <cstdint>
#include <initializer_list>
#include <limits>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace mesh2splat::metal {

inline constexpr bindings::BindingIndex kUnboundedMetalShaderBindingSlotCount =
    (std::numeric_limits<bindings::BindingIndex>::max)();

enum class MetalShaderBindingKind : std::uint8_t {
    Buffer,
    Texture,
    Sampler,
};

enum class MetalShaderBindingIssueKind : std::uint8_t {
    Missing,
    Duplicate,
    OutOfRange,
};

enum class MetalShaderBindingIssueSource : std::uint8_t {
    Requirement,
    BoundSlot,
};

struct MetalShaderBindingSlotLimits {
    bindings::BindingIndex bufferSlotCount = kUnboundedMetalShaderBindingSlotCount;
    bindings::BindingIndex textureSlotCount = kUnboundedMetalShaderBindingSlotCount;
    bindings::BindingIndex samplerSlotCount = kUnboundedMetalShaderBindingSlotCount;

    constexpr bindings::BindingIndex slotCountFor(MetalShaderBindingKind kind) const noexcept
    {
        switch (kind) {
        case MetalShaderBindingKind::Buffer:
            return bufferSlotCount;
        case MetalShaderBindingKind::Texture:
            return textureSlotCount;
        case MetalShaderBindingKind::Sampler:
            return samplerSlotCount;
        }

        return kUnboundedMetalShaderBindingSlotCount;
    }

    constexpr bool hasLimitFor(MetalShaderBindingKind kind) const noexcept
    {
        return slotCountFor(kind) != kUnboundedMetalShaderBindingSlotCount;
    }

    constexpr bool contains(MetalShaderBindingKind kind, bindings::BindingIndex slot) const noexcept
    {
        const bindings::BindingIndex slotCount = slotCountFor(kind);
        return slotCount == kUnboundedMetalShaderBindingSlotCount || slot < slotCount;
    }
};

struct MetalShaderBindingRequirement {
    MetalShaderBindingKind kind = MetalShaderBindingKind::Buffer;
    bindings::BindingIndex slot = 0;
    std::string_view name;
    bool required = true;
};

struct MetalShaderBoundSlot {
    MetalShaderBindingKind kind = MetalShaderBindingKind::Buffer;
    bindings::BindingIndex slot = 0;
    std::string_view name;
};

struct MetalShaderBindingIssue {
    MetalShaderBindingIssueKind issueKind = MetalShaderBindingIssueKind::Missing;
    MetalShaderBindingIssueSource source = MetalShaderBindingIssueSource::Requirement;
    MetalShaderBindingKind bindingKind = MetalShaderBindingKind::Buffer;
    bindings::BindingIndex slot = 0;
    bindings::BindingIndex slotCount = kUnboundedMetalShaderBindingSlotCount;
    std::size_t occurrenceCount = 1;
    std::string name;
    std::string message;
};

struct MetalShaderBindingValidationReport {
    std::string shaderLabel;
    std::vector<MetalShaderBindingIssue> issues;

    [[nodiscard]] bool valid() const noexcept
    {
        return issues.empty();
    }

    [[nodiscard]] bool hasIssue(MetalShaderBindingIssueKind kind) const noexcept
    {
        for (const MetalShaderBindingIssue& issue : issues) {
            if (issue.issueKind == kind) {
                return true;
            }
        }

        return false;
    }

    [[nodiscard]] bool hasIssue(MetalShaderBindingKind kind) const noexcept
    {
        for (const MetalShaderBindingIssue& issue : issues) {
            if (issue.bindingKind == kind) {
                return true;
            }
        }

        return false;
    }

    [[nodiscard]] std::size_t issueCount(MetalShaderBindingIssueKind kind) const noexcept
    {
        std::size_t count = 0;
        for (const MetalShaderBindingIssue& issue : issues) {
            if (issue.issueKind == kind) {
                ++count;
            }
        }

        return count;
    }

    [[nodiscard]] std::size_t issueCount(MetalShaderBindingKind kind) const noexcept
    {
        std::size_t count = 0;
        for (const MetalShaderBindingIssue& issue : issues) {
            if (issue.bindingKind == kind) {
                ++count;
            }
        }

        return count;
    }

    explicit operator bool() const noexcept
    {
        return valid();
    }

    [[nodiscard]] std::string diagnosticString() const
    {
        std::ostringstream output;
        output << "Metal shader binding validation";
        if (!shaderLabel.empty()) {
            output << " for '" << shaderLabel << "'";
        }

        if (valid()) {
            output << ": valid";
            return output.str();
        }

        output << " failed with " << issues.size() << " issue";
        if (issues.size() != 1) {
            output << "s";
        }
        output << ':';

        for (const MetalShaderBindingIssue& issue : issues) {
            output << "\n- " << issue.message;
        }

        return output.str();
    }
};

inline const char* metalShaderBindingKindName(MetalShaderBindingKind kind) noexcept
{
    switch (kind) {
    case MetalShaderBindingKind::Buffer:
        return "buffer";
    case MetalShaderBindingKind::Texture:
        return "texture";
    case MetalShaderBindingKind::Sampler:
        return "sampler";
    }

    return "binding";
}

inline const char* metalShaderBindingIssueKindName(MetalShaderBindingIssueKind kind) noexcept
{
    switch (kind) {
    case MetalShaderBindingIssueKind::Missing:
        return "missing";
    case MetalShaderBindingIssueKind::Duplicate:
        return "duplicate";
    case MetalShaderBindingIssueKind::OutOfRange:
        return "out-of-range";
    }

    return "unknown";
}

inline const char* metalShaderBindingIssueSourceName(MetalShaderBindingIssueSource source) noexcept
{
    switch (source) {
    case MetalShaderBindingIssueSource::Requirement:
        return "requirement";
    case MetalShaderBindingIssueSource::BoundSlot:
        return "bound slot";
    }

    return "binding";
}

inline constexpr MetalShaderBindingRequirement requiredBinding(
    MetalShaderBindingKind kind,
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return {kind, slot, name, true};
}

inline constexpr MetalShaderBindingRequirement optionalBinding(
    MetalShaderBindingKind kind,
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return {kind, slot, name, false};
}

inline constexpr MetalShaderBoundSlot boundBinding(
    MetalShaderBindingKind kind,
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return {kind, slot, name};
}

inline constexpr MetalShaderBindingRequirement requiredBuffer(
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return requiredBinding(MetalShaderBindingKind::Buffer, slot, name);
}

inline constexpr MetalShaderBindingRequirement optionalBuffer(
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return optionalBinding(MetalShaderBindingKind::Buffer, slot, name);
}

inline constexpr MetalShaderBindingRequirement requiredTexture(
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return requiredBinding(MetalShaderBindingKind::Texture, slot, name);
}

inline constexpr MetalShaderBindingRequirement optionalTexture(
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return optionalBinding(MetalShaderBindingKind::Texture, slot, name);
}

inline constexpr MetalShaderBindingRequirement requiredSampler(
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return requiredBinding(MetalShaderBindingKind::Sampler, slot, name);
}

inline constexpr MetalShaderBindingRequirement optionalSampler(
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return optionalBinding(MetalShaderBindingKind::Sampler, slot, name);
}

inline constexpr MetalShaderBoundSlot boundBuffer(
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return boundBinding(MetalShaderBindingKind::Buffer, slot, name);
}

inline constexpr MetalShaderBoundSlot boundTexture(
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return boundBinding(MetalShaderBindingKind::Texture, slot, name);
}

inline constexpr MetalShaderBoundSlot boundSampler(
    bindings::BindingIndex slot,
    std::string_view name = {}) noexcept
{
    return boundBinding(MetalShaderBindingKind::Sampler, slot, name);
}

namespace detail {

inline bool sameBinding(
    MetalShaderBindingKind lhsKind,
    bindings::BindingIndex lhsSlot,
    MetalShaderBindingKind rhsKind,
    bindings::BindingIndex rhsSlot) noexcept
{
    return lhsKind == rhsKind && lhsSlot == rhsSlot;
}

inline std::string shaderPrefix(std::string_view shaderLabel)
{
    std::string prefix = "Metal shader";
    if (!shaderLabel.empty()) {
        prefix += " '";
        prefix += shaderLabel;
        prefix += "'";
    }
    return prefix;
}

inline std::string bindingDescription(
    MetalShaderBindingKind kind,
    bindings::BindingIndex slot,
    std::string_view name)
{
    std::ostringstream output;
    output << metalShaderBindingKindName(kind) << '[' << slot << ']';
    if (!name.empty()) {
        output << " (" << name << ')';
    }
    return output.str();
}

inline bool hasPreviousRequirement(
    const MetalShaderBindingRequirement* requirements,
    std::size_t currentIndex) noexcept
{
    const MetalShaderBindingRequirement& current = requirements[currentIndex];
    for (std::size_t index = 0; index < currentIndex; ++index) {
        if (sameBinding(requirements[index].kind, requirements[index].slot, current.kind, current.slot)) {
            return true;
        }
    }

    return false;
}

inline bool hasPreviousBoundSlot(
    const MetalShaderBoundSlot* boundSlots,
    std::size_t currentIndex) noexcept
{
    const MetalShaderBoundSlot& current = boundSlots[currentIndex];
    for (std::size_t index = 0; index < currentIndex; ++index) {
        if (sameBinding(boundSlots[index].kind, boundSlots[index].slot, current.kind, current.slot)) {
            return true;
        }
    }

    return false;
}

inline std::size_t requirementOccurrenceCount(
    const MetalShaderBindingRequirement* requirements,
    std::size_t requirementCount,
    MetalShaderBindingKind kind,
    bindings::BindingIndex slot) noexcept
{
    std::size_t count = 0;
    for (std::size_t index = 0; index < requirementCount; ++index) {
        if (sameBinding(requirements[index].kind, requirements[index].slot, kind, slot)) {
            ++count;
        }
    }
    return count;
}

inline std::size_t boundSlotOccurrenceCount(
    const MetalShaderBoundSlot* boundSlots,
    std::size_t boundSlotCount,
    MetalShaderBindingKind kind,
    bindings::BindingIndex slot) noexcept
{
    std::size_t count = 0;
    for (std::size_t index = 0; index < boundSlotCount; ++index) {
        if (sameBinding(boundSlots[index].kind, boundSlots[index].slot, kind, slot)) {
            ++count;
        }
    }
    return count;
}

inline bool hasBoundSlot(
    const MetalShaderBoundSlot* boundSlots,
    std::size_t boundSlotCount,
    MetalShaderBindingKind kind,
    bindings::BindingIndex slot) noexcept
{
    for (std::size_t index = 0; index < boundSlotCount; ++index) {
        if (sameBinding(boundSlots[index].kind, boundSlots[index].slot, kind, slot)) {
            return true;
        }
    }

    return false;
}

inline std::string missingMessage(
    std::string_view shaderLabel,
    const MetalShaderBindingRequirement& requirement)
{
    return shaderPrefix(shaderLabel) + " is missing required " +
        bindingDescription(requirement.kind, requirement.slot, requirement.name);
}

inline std::string duplicateMessage(
    std::string_view shaderLabel,
    MetalShaderBindingIssueSource source,
    MetalShaderBindingKind kind,
    bindings::BindingIndex slot,
    std::string_view name,
    std::size_t occurrenceCount)
{
    std::ostringstream output;
    output << shaderPrefix(shaderLabel) << " has duplicate "
           << metalShaderBindingIssueSourceName(source) << " entries for "
           << bindingDescription(kind, slot, name) << " (" << occurrenceCount << " entries)";
    return output.str();
}

inline std::string outOfRangeMessage(
    std::string_view shaderLabel,
    MetalShaderBindingIssueSource source,
    MetalShaderBindingKind kind,
    bindings::BindingIndex slot,
    std::string_view name,
    bindings::BindingIndex slotCount)
{
    std::ostringstream output;
    output << shaderPrefix(shaderLabel) << ' ' << metalShaderBindingIssueSourceName(source) << ' '
           << bindingDescription(kind, slot, name) << " is out of range";
    if (slotCount == 0) {
        output << "; no " << metalShaderBindingKindName(kind) << " slots are allowed";
    } else {
        output << "; valid range is 0.." << (slotCount - 1);
    }
    return output.str();
}

inline void addMissingIssue(
    MetalShaderBindingValidationReport& report,
    const MetalShaderBindingRequirement& requirement)
{
    MetalShaderBindingIssue issue;
    issue.issueKind = MetalShaderBindingIssueKind::Missing;
    issue.source = MetalShaderBindingIssueSource::Requirement;
    issue.bindingKind = requirement.kind;
    issue.slot = requirement.slot;
    issue.name = std::string(requirement.name);
    issue.message = missingMessage(report.shaderLabel, requirement);
    report.issues.push_back(std::move(issue));
}

inline void addDuplicateIssue(
    MetalShaderBindingValidationReport& report,
    MetalShaderBindingIssueSource source,
    MetalShaderBindingKind kind,
    bindings::BindingIndex slot,
    std::string_view name,
    std::size_t occurrenceCount)
{
    MetalShaderBindingIssue issue;
    issue.issueKind = MetalShaderBindingIssueKind::Duplicate;
    issue.source = source;
    issue.bindingKind = kind;
    issue.slot = slot;
    issue.occurrenceCount = occurrenceCount;
    issue.name = std::string(name);
    issue.message = duplicateMessage(report.shaderLabel, source, kind, slot, name, occurrenceCount);
    report.issues.push_back(std::move(issue));
}

inline void addOutOfRangeIssue(
    MetalShaderBindingValidationReport& report,
    MetalShaderBindingIssueSource source,
    MetalShaderBindingKind kind,
    bindings::BindingIndex slot,
    std::string_view name,
    bindings::BindingIndex slotCount)
{
    MetalShaderBindingIssue issue;
    issue.issueKind = MetalShaderBindingIssueKind::OutOfRange;
    issue.source = source;
    issue.bindingKind = kind;
    issue.slot = slot;
    issue.slotCount = slotCount;
    issue.name = std::string(name);
    issue.message = outOfRangeMessage(report.shaderLabel, source, kind, slot, name, slotCount);
    report.issues.push_back(std::move(issue));
}

} // namespace detail

inline MetalShaderBindingValidationReport validateMetalShaderBindings(
    std::string_view shaderLabel,
    const MetalShaderBindingRequirement* requirements,
    std::size_t requirementCount,
    const MetalShaderBoundSlot* boundSlots,
    std::size_t boundSlotCount,
    MetalShaderBindingSlotLimits limits = {})
{
    MetalShaderBindingValidationReport report;
    report.shaderLabel = std::string(shaderLabel);

    if (requirements == nullptr) {
        requirementCount = 0;
    }
    if (boundSlots == nullptr) {
        boundSlotCount = 0;
    }

    for (std::size_t index = 0; index < requirementCount; ++index) {
        const MetalShaderBindingRequirement& requirement = requirements[index];
        if (!limits.contains(requirement.kind, requirement.slot)) {
            detail::addOutOfRangeIssue(
                report,
                MetalShaderBindingIssueSource::Requirement,
                requirement.kind,
                requirement.slot,
                requirement.name,
                limits.slotCountFor(requirement.kind));
        }
    }

    for (std::size_t index = 0; index < boundSlotCount; ++index) {
        const MetalShaderBoundSlot& boundSlot = boundSlots[index];
        if (!limits.contains(boundSlot.kind, boundSlot.slot)) {
            detail::addOutOfRangeIssue(
                report,
                MetalShaderBindingIssueSource::BoundSlot,
                boundSlot.kind,
                boundSlot.slot,
                boundSlot.name,
                limits.slotCountFor(boundSlot.kind));
        }
    }

    for (std::size_t index = 0; index < requirementCount; ++index) {
        const MetalShaderBindingRequirement& requirement = requirements[index];
        if (detail::hasPreviousRequirement(requirements, index)) {
            continue;
        }

        const std::size_t occurrenceCount = detail::requirementOccurrenceCount(
            requirements,
            requirementCount,
            requirement.kind,
            requirement.slot);
        if (occurrenceCount > 1) {
            detail::addDuplicateIssue(
                report,
                MetalShaderBindingIssueSource::Requirement,
                requirement.kind,
                requirement.slot,
                requirement.name,
                occurrenceCount);
        }
    }

    for (std::size_t index = 0; index < boundSlotCount; ++index) {
        const MetalShaderBoundSlot& boundSlot = boundSlots[index];
        if (detail::hasPreviousBoundSlot(boundSlots, index)) {
            continue;
        }

        const std::size_t occurrenceCount = detail::boundSlotOccurrenceCount(
            boundSlots,
            boundSlotCount,
            boundSlot.kind,
            boundSlot.slot);
        if (occurrenceCount > 1) {
            detail::addDuplicateIssue(
                report,
                MetalShaderBindingIssueSource::BoundSlot,
                boundSlot.kind,
                boundSlot.slot,
                boundSlot.name,
                occurrenceCount);
        }
    }

    for (std::size_t index = 0; index < requirementCount; ++index) {
        const MetalShaderBindingRequirement& requirement = requirements[index];
        if (!requirement.required || detail::hasPreviousRequirement(requirements, index) ||
            !limits.contains(requirement.kind, requirement.slot)) {
            continue;
        }

        if (!detail::hasBoundSlot(boundSlots, boundSlotCount, requirement.kind, requirement.slot)) {
            detail::addMissingIssue(report, requirement);
        }
    }

    return report;
}

inline MetalShaderBindingValidationReport validateMetalShaderBindings(
    std::string_view shaderLabel,
    const std::vector<MetalShaderBindingRequirement>& requirements,
    const std::vector<MetalShaderBoundSlot>& boundSlots,
    MetalShaderBindingSlotLimits limits = {})
{
    return validateMetalShaderBindings(
        shaderLabel,
        requirements.data(),
        requirements.size(),
        boundSlots.data(),
        boundSlots.size(),
        limits);
}

inline MetalShaderBindingValidationReport validateMetalShaderBindings(
    std::string_view shaderLabel,
    std::initializer_list<MetalShaderBindingRequirement> requirements,
    std::initializer_list<MetalShaderBoundSlot> boundSlots,
    MetalShaderBindingSlotLimits limits = {})
{
    return validateMetalShaderBindings(
        shaderLabel,
        requirements.begin(),
        requirements.size(),
        boundSlots.begin(),
        boundSlots.size(),
        limits);
}

} // namespace mesh2splat::metal
