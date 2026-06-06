#pragma once

#include <cstddef>
#include <memory>
#include <string>
#include <vector>

namespace mesh2splat::metal {

class MetalDeviceContext;

enum class MetalShaderLibrarySource {
    None,
    MetallibFile,
    DefaultLibrary,
    RuntimeSource,
};

class MetalShaderLibrary {
public:
    explicit MetalShaderLibrary(MetalDeviceContext& deviceContext);
    ~MetalShaderLibrary();

    MetalShaderLibrary(const MetalShaderLibrary&) = delete;
    MetalShaderLibrary& operator=(const MetalShaderLibrary&) = delete;

    MetalShaderLibrary(MetalShaderLibrary&&) noexcept;
    MetalShaderLibrary& operator=(MetalShaderLibrary&&) noexcept;

    bool loadDefault(const char* label = nullptr);
    bool loadFromFile(const std::string& path, std::string* errorMessage = nullptr);
    bool compileSource(const std::string& source, const char* label = nullptr, std::string* errorMessage = nullptr);

    bool isValid() const;
    MetalShaderLibrarySource sourceKind() const;
    const char* sourceKindName() const;
    const std::string& sourceIdentifier() const;
    std::size_t sourceByteCount() const;
    const std::string& debugLabel() const;
    const std::string& lastError() const;
    const std::string& lastErrorMessage() const;
    const std::string& sourceDescription() const;
    std::vector<std::string> functionNames() const;
    std::size_t functionCount() const;
    std::string availableFunctionList(std::size_t maxNames = 16) const;
    bool hasFunction(const std::string& functionName) const;
    void* nativeFunction(const std::string& functionName, std::string* errorMessage = nullptr);
    std::string missingFunctionDiagnostic(
        const std::string& functionName,
        const std::string& functionRole = std::string(),
        const std::string& pipelineLabel = std::string()) const;
    void* nativeLibrary() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
