#pragma once

#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalDeviceContext;

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
    void* nativeLibrary() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
