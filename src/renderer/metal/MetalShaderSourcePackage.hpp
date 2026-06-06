#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace mesh2splat::metal {

template <typename T>
struct MetalShaderPackageView {
    const T* data = nullptr;
    std::size_t count = 0;

    constexpr bool empty() const noexcept { return count == 0; }
    constexpr std::size_t size() const noexcept { return count; }
    constexpr const T* begin() const noexcept { return data; }
    constexpr const T* end() const noexcept { return data == nullptr ? nullptr : data + count; }
    constexpr const T& operator[](std::size_t index) const noexcept { return data[index]; }
    constexpr const T* first() const noexcept { return empty() ? nullptr : data; }
    constexpr const T* last() const noexcept { return empty() ? nullptr : data + count - 1; }
};

enum class MetalShaderFunctionStage : std::uint8_t {
    Vertex,
    Fragment,
    Compute,
};

struct MetalShaderSourceFileEntry {
    std::string_view id;
    std::string_view fileName;
    std::string_view repositorySourcePath;
    std::string_view bundleResourcePath;
    std::string_view fallbackSourceStringId;
    std::string_view checksumAlgorithm;
    std::string_view checksum;
};

struct MetalShaderExpectedFunction {
    std::string_view id;
    std::string_view name;
    MetalShaderFunctionStage stage = MetalShaderFunctionStage::Compute;
    std::string_view role;
    std::string_view sourceFileId;
    std::string_view logicalGroupId;
    bool required = true;
};

struct MetalShaderLogicalGroup {
    std::string_view id;
    std::string_view label;
    std::string_view sourceFileId;
    std::size_t expectedFunctionOffset = 0;
    std::size_t expectedFunctionCount = 0;
};

struct MetalShaderSourcePackage {
    std::string_view id;
    std::string_view displayName;
    std::string_view metallibResourceName;
    std::string_view metallibResourceExtension;
    std::string_view metallibBundleResourcePath;
    std::string_view repositoryShaderDirectory;
    std::string_view shaderResourceDirectory;
    std::string_view runtimeFallbackSourceStringId;
    std::string_view checksumAlgorithm;
    MetalShaderPackageView<MetalShaderSourceFileEntry> sourceFiles;
    MetalShaderPackageView<MetalShaderLogicalGroup> logicalGroups;
    MetalShaderPackageView<MetalShaderExpectedFunction> expectedFunctions;
};

struct MetalShaderExpectedFunctionSummary {
    std::size_t total = 0;
    std::size_t vertex = 0;
    std::size_t fragment = 0;
    std::size_t compute = 0;
    std::size_t required = 0;
    std::size_t optional = 0;
};

struct MetalShaderSourcePackageCheck {
    bool valid = true;
    std::vector<std::string> diagnostics;

    explicit operator bool() const noexcept
    {
        return valid;
    }
};

inline constexpr std::string_view kMetalShaderChecksumAlgorithm = "sha256";
inline constexpr std::string_view kMetalShaderChecksumPlaceholder = "sha256:pending";
inline constexpr std::string_view kMetalShaderResourceDirectory = "Shaders";
inline constexpr std::string_view kMetalShaderRepositoryDirectory = "shaders/metal";
inline constexpr std::string_view kMetalShaderLegacyRepositoryDirectory = "Shaders/metal";
inline constexpr std::string_view kMetalShaderMetallibResourceName = "Mesh2SplatMetal";
inline constexpr std::string_view kMetalShaderMetallibResourceExtension = "metallib";
inline constexpr std::string_view kMetalShaderMetallibBundleResourcePath = "Mesh2SplatMetal.metallib";
inline constexpr std::string_view kMetalShaderRuntimeFallbackSourceStringId =
    "mesh2splat.metal.runtime-source";

inline constexpr std::array<MetalShaderSourceFileEntry, 6> kMetalShaderSourceFiles = {{
    {
        "gpu-types",
        "GpuTypes.metal",
        "shaders/metal/GpuTypes.metal",
        "Shaders/GpuTypes.metal",
        "mesh2splat.metal.source.gpu-types",
        kMetalShaderChecksumAlgorithm,
        kMetalShaderChecksumPlaceholder,
    },
    {
        "clear",
        "Clear.metal",
        "shaders/metal/Clear.metal",
        "Shaders/Clear.metal",
        "mesh2splat.metal.source.clear",
        kMetalShaderChecksumAlgorithm,
        kMetalShaderChecksumPlaceholder,
    },
    {
        "mesh",
        "Mesh.metal",
        "shaders/metal/Mesh.metal",
        "Shaders/Mesh.metal",
        "mesh2splat.metal.source.mesh",
        kMetalShaderChecksumAlgorithm,
        kMetalShaderChecksumPlaceholder,
    },
    {
        "gaussian-preview",
        "Gaussian.metal",
        "shaders/metal/Gaussian.metal",
        "Shaders/Gaussian.metal",
        "mesh2splat.metal.source.gaussian",
        kMetalShaderChecksumAlgorithm,
        kMetalShaderChecksumPlaceholder,
    },
    {
        "mesh-conversion",
        "Conversion.metal",
        "shaders/metal/Conversion.metal",
        "Shaders/Conversion.metal",
        "mesh2splat.metal.source.conversion",
        kMetalShaderChecksumAlgorithm,
        kMetalShaderChecksumPlaceholder,
    },
    {
        "gaussian-sort",
        "Sort.metal",
        "shaders/metal/Sort.metal",
        "Shaders/Sort.metal",
        "mesh2splat.metal.source.sort",
        kMetalShaderChecksumAlgorithm,
        kMetalShaderChecksumPlaceholder,
    },
}};

inline constexpr std::array<MetalShaderExpectedFunction, 18> kMetalShaderExpectedFunctions = {{
    {
        "clear.vertex",
        "clearVertex",
        MetalShaderFunctionStage::Vertex,
        "fullscreen-clear-vertex",
        "clear",
        "clear",
    },
    {
        "clear.fragment",
        "clearFragment",
        MetalShaderFunctionStage::Fragment,
        "fullscreen-clear-fragment",
        "clear",
        "clear",
    },
    {
        "clear.buffer-uint",
        "clearBufferUintKernel",
        MetalShaderFunctionStage::Compute,
        "clear-uint-buffer",
        "clear",
        "clear",
    },
    {
        "clear.reset-counter",
        "resetCounterKernel",
        MetalShaderFunctionStage::Compute,
        "reset-counter",
        "clear",
        "clear",
    },
    {
        "clear.reset-gaussian-counter",
        "resetGaussianCounterKernel",
        MetalShaderFunctionStage::Compute,
        "reset-gaussian-counter",
        "clear",
        "clear",
    },
    {
        "clear.texture-float",
        "clearTexture2DFloatKernel",
        MetalShaderFunctionStage::Compute,
        "clear-float-texture",
        "clear",
        "clear",
    },
    {
        "clear.texture-uint",
        "clearTexture2DUintKernel",
        MetalShaderFunctionStage::Compute,
        "clear-uint-texture",
        "clear",
        "clear",
    },
    {
        "clear.pack-rgba8",
        "packTexture2DRgba8Kernel",
        MetalShaderFunctionStage::Compute,
        "pack-rgba8-texture",
        "clear",
        "clear",
    },
    {
        "clear.pack-gaussian-textures",
        "packGaussianTexturesKernel",
        MetalShaderFunctionStage::Compute,
        "pack-gaussian-textures",
        "clear",
        "clear",
    },
    {
        "mesh.vertex",
        "meshVertex",
        MetalShaderFunctionStage::Vertex,
        "mesh-render-vertex",
        "mesh",
        "mesh",
    },
    {
        "mesh.fragment",
        "meshFragment",
        MetalShaderFunctionStage::Fragment,
        "mesh-render-fragment",
        "mesh",
        "mesh",
    },
    {
        "gaussian-preview.vertex",
        "gaussianPreviewVertex",
        MetalShaderFunctionStage::Vertex,
        "gaussian-preview-vertex",
        "gaussian-preview",
        "gaussian-preview",
    },
    {
        "gaussian-preview.fragment",
        "gaussianPreviewFragment",
        MetalShaderFunctionStage::Fragment,
        "gaussian-preview-fragment",
        "gaussian-preview",
        "gaussian-preview",
    },
    {
        "mesh-conversion.kernel",
        "meshVertexConversionKernel",
        MetalShaderFunctionStage::Compute,
        "mesh-to-gaussian-conversion",
        "mesh-conversion",
        "mesh-conversion",
    },
    {
        "gaussian-sort.depth-key",
        "gaussianDepthKeyKernel",
        MetalShaderFunctionStage::Compute,
        "gaussian-depth-key",
        "gaussian-sort",
        "gaussian-sort",
    },
    {
        "gaussian-sort.radix-count",
        "gaussianRadixCountKernel",
        MetalShaderFunctionStage::Compute,
        "gaussian-radix-count",
        "gaussian-sort",
        "gaussian-sort",
    },
    {
        "gaussian-sort.radix-prefix",
        "gaussianRadixPrefixKernel",
        MetalShaderFunctionStage::Compute,
        "gaussian-radix-prefix",
        "gaussian-sort",
        "gaussian-sort",
    },
    {
        "gaussian-sort.radix-reorder",
        "gaussianRadixReorderKernel",
        MetalShaderFunctionStage::Compute,
        "gaussian-radix-reorder",
        "gaussian-sort",
        "gaussian-sort",
    },
}};

inline constexpr std::array<MetalShaderLogicalGroup, 6> kMetalShaderLogicalGroups = {{
    {
        "gpu-types",
        "Shared GPU Types",
        "gpu-types",
        0,
        0,
    },
    {
        "clear",
        "Clear and Packing",
        "clear",
        0,
        9,
    },
    {
        "mesh",
        "Mesh Render",
        "mesh",
        9,
        2,
    },
    {
        "gaussian-preview",
        "Gaussian Preview Render",
        "gaussian-preview",
        11,
        2,
    },
    {
        "mesh-conversion",
        "Mesh Conversion",
        "mesh-conversion",
        13,
        1,
    },
    {
        "gaussian-sort",
        "Gaussian Sort",
        "gaussian-sort",
        14,
        4,
    },
}};

inline constexpr MetalShaderSourcePackage kMetalShaderSourcePackage = {
    "mesh2splat.metal.shader-source-package",
    "Mesh2Splat Metal Shader Sources",
    kMetalShaderMetallibResourceName,
    kMetalShaderMetallibResourceExtension,
    kMetalShaderMetallibBundleResourcePath,
    kMetalShaderRepositoryDirectory,
    kMetalShaderResourceDirectory,
    kMetalShaderRuntimeFallbackSourceStringId,
    kMetalShaderChecksumAlgorithm,
    { kMetalShaderSourceFiles.data(), kMetalShaderSourceFiles.size() },
    { kMetalShaderLogicalGroups.data(), kMetalShaderLogicalGroups.size() },
    { kMetalShaderExpectedFunctions.data(), kMetalShaderExpectedFunctions.size() },
};

constexpr const char* metalShaderFunctionStageName(MetalShaderFunctionStage stage) noexcept
{
    switch (stage) {
    case MetalShaderFunctionStage::Vertex:
        return "vertex";
    case MetalShaderFunctionStage::Fragment:
        return "fragment";
    case MetalShaderFunctionStage::Compute:
        return "compute";
    }

    return "unknown";
}

constexpr const MetalShaderSourcePackage& metalShaderSourcePackage() noexcept
{
    return kMetalShaderSourcePackage;
}

constexpr MetalShaderPackageView<MetalShaderSourceFileEntry> metalShaderSourceFiles() noexcept
{
    return kMetalShaderSourcePackage.sourceFiles;
}

constexpr MetalShaderPackageView<MetalShaderLogicalGroup> metalShaderLogicalGroups() noexcept
{
    return kMetalShaderSourcePackage.logicalGroups;
}

constexpr MetalShaderPackageView<MetalShaderExpectedFunction> metalShaderExpectedFunctions() noexcept
{
    return kMetalShaderSourcePackage.expectedFunctions;
}

constexpr bool isMetalShaderFunctionStage(
    const MetalShaderExpectedFunction& function,
    MetalShaderFunctionStage stage) noexcept
{
    return function.stage == stage;
}

constexpr std::size_t metalShaderExpectedFunctionCount(MetalShaderFunctionStage stage) noexcept
{
    std::size_t count = 0;
    for (const MetalShaderExpectedFunction& function : kMetalShaderExpectedFunctions) {
        if (isMetalShaderFunctionStage(function, stage)) {
            ++count;
        }
    }
    return count;
}

constexpr MetalShaderExpectedFunctionSummary metalShaderExpectedFunctionSummary() noexcept
{
    MetalShaderExpectedFunctionSummary summary;
    summary.total = kMetalShaderExpectedFunctions.size();
    for (const MetalShaderExpectedFunction& function : kMetalShaderExpectedFunctions) {
        if (function.required) {
            ++summary.required;
        } else {
            ++summary.optional;
        }

        switch (function.stage) {
        case MetalShaderFunctionStage::Vertex:
            ++summary.vertex;
            break;
        case MetalShaderFunctionStage::Fragment:
            ++summary.fragment;
            break;
        case MetalShaderFunctionStage::Compute:
            ++summary.compute;
            break;
        }
    }
    return summary;
}

constexpr MetalShaderPackageView<MetalShaderExpectedFunction> metalShaderExpectedFunctionsForGroup(
    const MetalShaderLogicalGroup& group) noexcept
{
    return group.expectedFunctionOffset <= kMetalShaderExpectedFunctions.size() &&
            group.expectedFunctionCount <= kMetalShaderExpectedFunctions.size() - group.expectedFunctionOffset
        ? MetalShaderPackageView<MetalShaderExpectedFunction>{
            kMetalShaderExpectedFunctions.data() + group.expectedFunctionOffset,
            group.expectedFunctionCount,
        }
        : MetalShaderPackageView<MetalShaderExpectedFunction>{};
}

constexpr const MetalShaderSourceFileEntry* findMetalShaderSourceFile(std::string_view id) noexcept
{
    for (const MetalShaderSourceFileEntry& sourceFile : kMetalShaderSourceFiles) {
        if (sourceFile.id == id || sourceFile.fileName == id ||
            sourceFile.repositorySourcePath == id || sourceFile.bundleResourcePath == id) {
            return &sourceFile;
        }
    }

    return nullptr;
}

constexpr const MetalShaderLogicalGroup* findMetalShaderLogicalGroup(std::string_view id) noexcept
{
    for (const MetalShaderLogicalGroup& group : kMetalShaderLogicalGroups) {
        if (group.id == id || group.sourceFileId == id) {
            return &group;
        }
    }

    return nullptr;
}

constexpr const MetalShaderExpectedFunction* findMetalShaderExpectedFunction(std::string_view nameOrId) noexcept
{
    for (const MetalShaderExpectedFunction& function : kMetalShaderExpectedFunctions) {
        if (function.id == nameOrId || function.name == nameOrId) {
            return &function;
        }
    }

    return nullptr;
}

constexpr const MetalShaderExpectedFunction* findMetalShaderExpectedFunctionByRole(
    std::string_view role) noexcept
{
    for (const MetalShaderExpectedFunction& function : kMetalShaderExpectedFunctions) {
        if (function.role == role) {
            return &function;
        }
    }

    return nullptr;
}

constexpr bool metalShaderPackageHasExpectedFunction(std::string_view nameOrId) noexcept
{
    return findMetalShaderExpectedFunction(nameOrId) != nullptr;
}

constexpr bool metalShaderPackageHasSourceFile(std::string_view id) noexcept
{
    return findMetalShaderSourceFile(id) != nullptr;
}

constexpr bool metalShaderLogicalGroupContainsFunction(
    const MetalShaderLogicalGroup& group,
    std::string_view nameOrId) noexcept
{
    for (const MetalShaderExpectedFunction& function : metalShaderExpectedFunctionsForGroup(group)) {
        if (function.id == nameOrId || function.name == nameOrId || function.role == nameOrId) {
            return true;
        }
    }
    return false;
}

inline std::string metalShaderMetallibResourceFileName()
{
    std::string fileName(kMetalShaderMetallibResourceName);
    fileName.push_back('.');
    fileName += kMetalShaderMetallibResourceExtension;
    return fileName;
}

inline std::string metalShaderRepositorySourcePath(std::string_view fileName)
{
    std::string path(kMetalShaderRepositoryDirectory);
    if (!path.empty()) {
        path.push_back('/');
    }
    path += fileName;
    return path;
}

inline std::string metalShaderLegacyRepositorySourcePath(std::string_view fileName)
{
    std::string path(kMetalShaderLegacyRepositoryDirectory);
    if (!path.empty()) {
        path.push_back('/');
    }
    path += fileName;
    return path;
}

inline std::string metalShaderBundleResourcePath(std::string_view fileName)
{
    std::string path(kMetalShaderResourceDirectory);
    if (!path.empty()) {
        path.push_back('/');
    }
    path += fileName;
    return path;
}

inline MetalShaderSourcePackageCheck checkMetalShaderSourcePackageConsistency(
    const MetalShaderSourcePackage& package = kMetalShaderSourcePackage)
{
    MetalShaderSourcePackageCheck check;
    auto fail = [&check](std::string message) {
        check.valid = false;
        check.diagnostics.push_back(std::move(message));
    };

    if (package.id.empty()) {
        fail("Metal shader source package id is empty.");
    }
    if (package.metallibResourceName.empty() || package.metallibResourceExtension.empty()) {
        fail("Metal shader source package metallib resource name is incomplete.");
    }
    if (package.sourceFiles.empty()) {
        fail("Metal shader source package does not list source files.");
    }
    if (package.expectedFunctions.empty()) {
        fail("Metal shader source package does not list expected functions.");
    }

    for (const MetalShaderSourceFileEntry& sourceFile : package.sourceFiles) {
        if (sourceFile.id.empty()) {
            fail("Metal shader source file entry has an empty id.");
        }
        if (sourceFile.fileName.empty()) {
            fail("Metal shader source file entry has an empty file name.");
        }
        if (sourceFile.repositorySourcePath.empty()) {
            fail("Metal shader source file entry has an empty repository source path.");
        }
        if (sourceFile.bundleResourcePath.empty()) {
            fail("Metal shader source file entry has an empty bundle resource path.");
        }
    }

    for (const MetalShaderLogicalGroup& group : package.logicalGroups) {
        if (group.id.empty()) {
            fail("Metal shader logical group has an empty id.");
        }
        if (findMetalShaderSourceFile(group.sourceFileId) == nullptr) {
            fail("Metal shader logical group references an unknown source file.");
        }
        if (group.expectedFunctionOffset > package.expectedFunctions.count ||
            group.expectedFunctionCount > package.expectedFunctions.count - group.expectedFunctionOffset) {
            fail("Metal shader logical group expected-function range is out of bounds.");
        }
    }

    for (const MetalShaderExpectedFunction& function : package.expectedFunctions) {
        if (function.id.empty() || function.name.empty()) {
            fail("Metal shader expected function has an empty id or name.");
        }
        if (findMetalShaderSourceFile(function.sourceFileId) == nullptr) {
            fail("Metal shader expected function references an unknown source file.");
        }
        if (findMetalShaderLogicalGroup(function.logicalGroupId) == nullptr) {
            fail("Metal shader expected function references an unknown logical group.");
        }
    }

    return check;
}

} // namespace mesh2splat::metal
