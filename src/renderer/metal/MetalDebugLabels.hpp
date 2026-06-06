#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace mesh2splat::metal {

enum class MetalDebugLabelKind : uint8_t {
    Generic,
    Buffer,
    Texture,
    RenderTarget,
    DepthStencil,
    Heap,
    Pipeline,
    Encoder,
    CommandBuffer,
    Pass,
    Shader,
    Frame,
};

struct MetalDebugLabelSuffixes {
    std::optional<uint64_t> serial;
    std::optional<std::size_t> sizeBytes;
    std::optional<uint64_t> frameIndex;
    std::optional<uint32_t> slot;
    std::optional<uint32_t> passIndex;
};

struct MetalDebugLabelPart {
    std::string_view key;
    std::string_view value;
};

struct MetalDebugLabelDescriptor {
    MetalDebugLabelKind kind = MetalDebugLabelKind::Generic;
    std::string_view subsystem;
    std::string_view role;
    std::string_view name;
    std::string_view owner;
    std::vector<MetalDebugLabelPart> parts;
    MetalDebugLabelSuffixes suffixes;
};

inline constexpr std::string_view kMetalDebugDefaultSubsystem = "Mesh2Splat";
inline constexpr std::string_view kMetalDebugLabelFallback = "Metal Debug Object";

inline const char* metalDebugLabelKindName(MetalDebugLabelKind kind)
{
    switch (kind) {
    case MetalDebugLabelKind::Generic:
        return "generic";
    case MetalDebugLabelKind::Buffer:
        return "buffer";
    case MetalDebugLabelKind::Texture:
        return "texture";
    case MetalDebugLabelKind::RenderTarget:
        return "render-target";
    case MetalDebugLabelKind::DepthStencil:
        return "depth-stencil";
    case MetalDebugLabelKind::Heap:
        return "heap";
    case MetalDebugLabelKind::Pipeline:
        return "pipeline";
    case MetalDebugLabelKind::Encoder:
        return "encoder";
    case MetalDebugLabelKind::CommandBuffer:
        return "command-buffer";
    case MetalDebugLabelKind::Pass:
        return "pass";
    case MetalDebugLabelKind::Shader:
        return "shader";
    case MetalDebugLabelKind::Frame:
        return "frame";
    }

    return "unknown";
}

inline bool isDebugLabelSeparator(char value)
{
    const auto byte = static_cast<unsigned char>(value);
    return byte <= 0x20u || byte == 0x7fu;
}

inline std::string sanitizeDebugLabel(std::string_view label, std::string_view fallback = {})
{
    auto sanitize = [](std::string_view value) {
        std::string result;
        result.reserve(value.size());

        bool pendingSpace = false;
        for (char character : value) {
            if (isDebugLabelSeparator(character)) {
                pendingSpace = !result.empty();
                continue;
            }

            if (pendingSpace) {
                result.push_back(' ');
                pendingSpace = false;
            }
            result.push_back(character);
        }

        return result;
    };

    std::string result = sanitize(label);
    if (result.empty() && !fallback.empty()) {
        result = sanitize(fallback);
    }
    return result;
}

inline std::string serialSuffix(uint64_t serial)
{
    return " [serial=" + std::to_string(serial) + "]";
}

inline std::string sizeSuffix(std::size_t sizeBytes)
{
    return " [bytes=" + std::to_string(sizeBytes) + "]";
}

inline std::string frameSuffix(uint64_t frameIndex)
{
    return " [frame=" + std::to_string(frameIndex) + "]";
}

inline std::string slotSuffix(uint32_t slot)
{
    return " [slot=" + std::to_string(slot) + "]";
}

inline std::string passSuffix(uint32_t passIndex)
{
    return " [pass=" + std::to_string(passIndex) + "]";
}

inline std::string keyValueSuffix(std::string_view key, std::string_view value)
{
    const std::string sanitizedKey = sanitizeDebugLabel(key);
    const std::string sanitizedValue = sanitizeDebugLabel(value);
    if (sanitizedKey.empty() || sanitizedValue.empty()) {
        return {};
    }

    return " [" + sanitizedKey + "=" + sanitizedValue + "]";
}

inline void appendDebugLabelPart(std::string& label, std::string_view part)
{
    const std::string sanitizedPart = sanitizeDebugLabel(part);
    if (sanitizedPart.empty()) {
        return;
    }

    if (!label.empty()) {
        label.push_back(' ');
    }
    label += sanitizedPart;
}

inline void appendDebugLabelPart(std::string& label, std::string_view key, std::string_view value)
{
    const std::string suffix = keyValueSuffix(key, value);
    if (!suffix.empty()) {
        label += suffix;
    }
}

inline void appendDebugLabelSuffixes(std::string& label, const MetalDebugLabelSuffixes& suffixes)
{
    if (suffixes.serial.has_value()) {
        label += serialSuffix(*suffixes.serial);
    }
    if (suffixes.sizeBytes.has_value()) {
        label += sizeSuffix(*suffixes.sizeBytes);
    }
    if (suffixes.frameIndex.has_value()) {
        label += frameSuffix(*suffixes.frameIndex);
    }
    if (suffixes.slot.has_value()) {
        label += slotSuffix(*suffixes.slot);
    }
    if (suffixes.passIndex.has_value()) {
        label += passSuffix(*suffixes.passIndex);
    }
}

inline MetalDebugLabelSuffixes withSerial(MetalDebugLabelSuffixes suffixes, uint64_t serial)
{
    suffixes.serial = serial;
    return suffixes;
}

inline MetalDebugLabelSuffixes withSizeBytes(MetalDebugLabelSuffixes suffixes, std::size_t sizeBytes)
{
    suffixes.sizeBytes = sizeBytes;
    return suffixes;
}

inline MetalDebugLabelSuffixes withFrameIndex(MetalDebugLabelSuffixes suffixes, uint64_t frameIndex)
{
    suffixes.frameIndex = frameIndex;
    return suffixes;
}

inline MetalDebugLabelSuffixes withSlot(MetalDebugLabelSuffixes suffixes, uint32_t slot)
{
    suffixes.slot = slot;
    return suffixes;
}

inline MetalDebugLabelSuffixes withPassIndex(MetalDebugLabelSuffixes suffixes, uint32_t passIndex)
{
    suffixes.passIndex = passIndex;
    return suffixes;
}

inline std::string composeDebugLabel(const MetalDebugLabelDescriptor& descriptor)
{
    std::string label;
    appendDebugLabelPart(label, descriptor.subsystem.empty() ? kMetalDebugDefaultSubsystem : descriptor.subsystem);
    appendDebugLabelPart(label, metalDebugLabelKindName(descriptor.kind));
    appendDebugLabelPart(label, descriptor.role);
    appendDebugLabelPart(label, descriptor.name);

    if (!descriptor.owner.empty()) {
        appendDebugLabelPart(label, "owner", descriptor.owner);
    }

    for (const MetalDebugLabelPart& part : descriptor.parts) {
        appendDebugLabelPart(label, part.key, part.value);
    }

    if (label.empty()) {
        label = std::string(kMetalDebugLabelFallback);
    }

    appendDebugLabelSuffixes(label, descriptor.suffixes);
    return label;
}

inline std::string composeResourceLabel(
    std::string_view baseLabel,
    std::string_view resourceRole = {},
    const MetalDebugLabelSuffixes& suffixes = {})
{
    std::string label;
    appendDebugLabelPart(label, baseLabel);
    appendDebugLabelPart(label, resourceRole);

    if (label.empty()) {
        label = "Metal Resource";
    }

    appendDebugLabelSuffixes(label, suffixes);
    return label;
}

inline std::string composeResourceLabel(
    MetalDebugLabelKind kind,
    std::string_view resourceRole,
    std::string_view resourceName = {},
    const MetalDebugLabelSuffixes& suffixes = {})
{
    MetalDebugLabelDescriptor descriptor;
    descriptor.kind = kind;
    descriptor.role = resourceRole;
    descriptor.name = resourceName;
    descriptor.suffixes = suffixes;
    return composeDebugLabel(descriptor);
}

inline std::string composeBufferLabel(
    std::string_view resourceRole,
    std::size_t sizeBytes = 0,
    std::string_view resourceName = {},
    MetalDebugLabelSuffixes suffixes = {})
{
    if (sizeBytes > 0 && !suffixes.sizeBytes.has_value()) {
        suffixes.sizeBytes = sizeBytes;
    }
    return composeResourceLabel(MetalDebugLabelKind::Buffer, resourceRole, resourceName, suffixes);
}

inline std::string composeTextureLabel(
    std::string_view resourceRole,
    std::string_view resourceName = {},
    const MetalDebugLabelSuffixes& suffixes = {})
{
    return composeResourceLabel(MetalDebugLabelKind::Texture, resourceRole, resourceName, suffixes);
}

inline std::string composePassLabel(
    std::string_view passLabel,
    const MetalDebugLabelSuffixes& suffixes = {})
{
    std::string label = sanitizeDebugLabel(passLabel, "Metal Pass");
    appendDebugLabelSuffixes(label, suffixes);
    return label;
}

inline std::string composePassLabel(
    std::string_view passRole,
    uint64_t frameIndex,
    uint32_t passIndex)
{
    MetalDebugLabelSuffixes suffixes;
    suffixes.frameIndex = frameIndex;
    suffixes.passIndex = passIndex;
    return composeResourceLabel(MetalDebugLabelKind::Pass, passRole, {}, suffixes);
}

inline std::string composeFrameLabel(uint64_t frameIndex, std::string_view role = {})
{
    MetalDebugLabelSuffixes suffixes;
    suffixes.frameIndex = frameIndex;
    return composeResourceLabel(MetalDebugLabelKind::Frame, role.empty() ? "frame" : role, {}, suffixes);
}

inline std::string composeShaderLabel(
    std::string_view functionName,
    std::string_view role = {},
    const MetalDebugLabelSuffixes& suffixes = {})
{
    return composeResourceLabel(MetalDebugLabelKind::Shader, role, functionName, suffixes);
}

} // namespace mesh2splat::metal
