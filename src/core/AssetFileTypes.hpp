#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>

namespace mesh2splat::core {

enum class AssetFileKind : std::uint8_t {
    Unknown = 0,
    GltfJson,
    GltfBinary,
    Ply,
    Splat,
};

enum class AssetFileIntent : std::uint8_t {
    Unknown = 0,
    Load,
    LoadMesh,
    LoadGaussian,
    ExportGaussian,
};

inline constexpr std::array<AssetFileKind, 4> kSupportedAssetFileKinds = {
    AssetFileKind::GltfJson,
    AssetFileKind::GltfBinary,
    AssetFileKind::Ply,
    AssetFileKind::Splat,
};

inline constexpr std::array<AssetFileKind, 2> kMeshAssetFileKinds = {
    AssetFileKind::GltfJson,
    AssetFileKind::GltfBinary,
};

inline constexpr std::array<AssetFileKind, 2> kGaussianAssetFileKinds = {
    AssetFileKind::Ply,
    AssetFileKind::Splat,
};

inline constexpr std::array<std::string_view, 4> kSupportedAssetFileExtensions = {
    "gltf",
    "glb",
    "ply",
    "splat",
};

inline constexpr std::array<std::string_view, 2> kMeshAssetFileExtensions = {
    "gltf",
    "glb",
};

inline constexpr std::array<std::string_view, 2> kGaussianAssetFileExtensions = {
    "ply",
    "splat",
};

inline constexpr std::array<std::string_view, 2> kGaussianExportAssetFileExtensions = {
    "ply",
    "splat",
};

constexpr char assetFileAsciiLower(char value)
{
    return value >= 'A' && value <= 'Z'
        ? static_cast<char>(value - 'A' + 'a')
        : value;
}

constexpr bool assetFileIsAsciiWhitespace(char value)
{
    return value == ' ' ||
        value == '\t' ||
        value == '\n' ||
        value == '\r' ||
        value == '\f' ||
        value == '\v';
}

constexpr std::string_view assetFileTrimAsciiWhitespace(std::string_view value)
{
    std::size_t first = 0;
    while (first < value.size() && assetFileIsAsciiWhitespace(value[first])) {
        ++first;
    }

    std::size_t last = value.size();
    while (last > first && assetFileIsAsciiWhitespace(value[last - 1])) {
        --last;
    }

    return value.substr(first, last - first);
}

constexpr bool assetFileEqualsIgnoreCase(std::string_view lhs, std::string_view rhs)
{
    if (lhs.size() != rhs.size()) {
        return false;
    }

    for (std::size_t index = 0; index < lhs.size(); ++index) {
        if (assetFileAsciiLower(lhs[index]) != assetFileAsciiLower(rhs[index])) {
            return false;
        }
    }
    return true;
}

constexpr std::string_view assetFileExtensionWithoutDot(std::string_view extension)
{
    extension = assetFileTrimAsciiWhitespace(extension);
    while (!extension.empty() && extension.front() == '.') {
        extension.remove_prefix(1);
    }
    return extension;
}

template <std::size_t Size>
constexpr bool assetFileExtensionIsOneOf(
    std::string_view extension,
    const std::array<std::string_view, Size>& extensions)
{
    const std::string_view normalized = assetFileExtensionWithoutDot(extension);
    for (std::string_view candidate : extensions) {
        if (assetFileEqualsIgnoreCase(normalized, candidate)) {
            return true;
        }
    }
    return false;
}

constexpr AssetFileKind assetFileKindFromExtension(std::string_view extension)
{
    const std::string_view normalized = assetFileExtensionWithoutDot(extension);
    if (assetFileEqualsIgnoreCase(normalized, "gltf")) {
        return AssetFileKind::GltfJson;
    }
    if (assetFileEqualsIgnoreCase(normalized, "glb")) {
        return AssetFileKind::GltfBinary;
    }
    if (assetFileEqualsIgnoreCase(normalized, "ply")) {
        return AssetFileKind::Ply;
    }
    if (assetFileEqualsIgnoreCase(normalized, "splat")) {
        return AssetFileKind::Splat;
    }
    return AssetFileKind::Unknown;
}

inline std::string_view assetFileExtensionFromPath(std::string_view path)
{
    const std::size_t separator = path.find_last_of("/\\");
    const std::size_t filenameStart = separator == std::string_view::npos ? 0 : separator + 1;
    const std::size_t dot = path.find_last_of('.');

    if (dot == std::string_view::npos ||
        dot < filenameStart ||
        dot == filenameStart ||
        dot + 1 >= path.size()) {
        return {};
    }

    return path.substr(dot + 1);
}

inline AssetFileKind assetFileKindFromPath(std::string_view path)
{
    return assetFileKindFromExtension(assetFileExtensionFromPath(path));
}

constexpr std::string_view assetFileCanonicalExtension(AssetFileKind kind)
{
    switch (kind) {
    case AssetFileKind::GltfJson:
        return "gltf";
    case AssetFileKind::GltfBinary:
        return "glb";
    case AssetFileKind::Ply:
        return "ply";
    case AssetFileKind::Splat:
        return "splat";
    case AssetFileKind::Unknown:
        break;
    }
    return {};
}

constexpr std::string_view assetFileKindName(AssetFileKind kind)
{
    switch (kind) {
    case AssetFileKind::GltfJson:
        return "gltf";
    case AssetFileKind::GltfBinary:
        return "glb";
    case AssetFileKind::Ply:
        return "ply";
    case AssetFileKind::Splat:
        return "splat";
    case AssetFileKind::Unknown:
        break;
    }
    return "unknown";
}

constexpr std::string_view assetFileIntentName(AssetFileIntent intent)
{
    switch (intent) {
    case AssetFileIntent::Load:
        return "load";
    case AssetFileIntent::LoadMesh:
        return "load-mesh";
    case AssetFileIntent::LoadGaussian:
        return "load-gaussian";
    case AssetFileIntent::ExportGaussian:
        return "export-gaussian";
    case AssetFileIntent::Unknown:
        break;
    }
    return "unknown";
}

constexpr bool isKnownAssetFileKind(AssetFileKind kind)
{
    return kind != AssetFileKind::Unknown;
}

constexpr bool isMeshAssetFileKind(AssetFileKind kind)
{
    return kind == AssetFileKind::GltfJson ||
        kind == AssetFileKind::GltfBinary;
}

constexpr bool isGaussianAssetFileKind(AssetFileKind kind)
{
    return kind == AssetFileKind::Ply ||
        kind == AssetFileKind::Splat;
}

constexpr bool isLoadableAssetFileKind(AssetFileKind kind)
{
    return isMeshAssetFileKind(kind) || isGaussianAssetFileKind(kind);
}

constexpr bool isExportableAssetFileKind(AssetFileKind kind)
{
    return isGaussianAssetFileKind(kind);
}

constexpr bool isMeshAssetFileExtension(std::string_view extension)
{
    return assetFileExtensionIsOneOf(extension, kMeshAssetFileExtensions);
}

constexpr bool isGaussianAssetFileExtension(std::string_view extension)
{
    return assetFileExtensionIsOneOf(extension, kGaussianAssetFileExtensions);
}

constexpr bool isExportableAssetFileExtension(std::string_view extension)
{
    return assetFileExtensionIsOneOf(extension, kGaussianExportAssetFileExtensions);
}

inline bool isMeshAssetFilePath(std::string_view path)
{
    return isMeshAssetFileKind(assetFileKindFromPath(path));
}

inline bool isGaussianAssetFilePath(std::string_view path)
{
    return isGaussianAssetFileKind(assetFileKindFromPath(path));
}

inline bool isExportableAssetFilePath(std::string_view path)
{
    return isExportableAssetFileKind(assetFileKindFromPath(path));
}

constexpr AssetFileIntent assetFilePrimaryLoadIntent(AssetFileKind kind)
{
    if (isMeshAssetFileKind(kind)) {
        return AssetFileIntent::LoadMesh;
    }
    if (isGaussianAssetFileKind(kind)) {
        return AssetFileIntent::LoadGaussian;
    }
    return AssetFileIntent::Unknown;
}

inline AssetFileIntent assetFilePrimaryLoadIntentFromPath(std::string_view path)
{
    return assetFilePrimaryLoadIntent(assetFileKindFromPath(path));
}

constexpr bool assetFileKindSupportsIntent(AssetFileKind kind, AssetFileIntent intent)
{
    switch (intent) {
    case AssetFileIntent::Load:
        return isLoadableAssetFileKind(kind);
    case AssetFileIntent::LoadMesh:
        return isMeshAssetFileKind(kind);
    case AssetFileIntent::LoadGaussian:
    case AssetFileIntent::ExportGaussian:
        return isGaussianAssetFileKind(kind);
    case AssetFileIntent::Unknown:
        break;
    }
    return false;
}

constexpr bool assetFileExtensionSupportsIntent(std::string_view extension, AssetFileIntent intent)
{
    return assetFileKindSupportsIntent(assetFileKindFromExtension(extension), intent);
}

inline bool assetFilePathSupportsIntent(std::string_view path, AssetFileIntent intent)
{
    return assetFileKindSupportsIntent(assetFileKindFromPath(path), intent);
}

constexpr bool isSupportedAssetFileExtension(std::string_view extension)
{
    return isKnownAssetFileKind(assetFileKindFromExtension(extension));
}

inline bool isSupportedAssetFilePath(std::string_view path)
{
    return isKnownAssetFileKind(assetFileKindFromPath(path));
}

} // namespace mesh2splat::core
