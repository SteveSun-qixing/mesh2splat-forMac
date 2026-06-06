#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>

namespace mesh2splat::metal {

class MetalDeviceContext;

enum class MetalTextureFormat {
    BGRA8Unorm,
    BGRA8UnormSrgb,
    RGBA8Unorm,
    RGBA8UnormSrgb,
    R8Unorm,
    Depth32Float,
};

enum class MetalTextureUsage : uint32_t {
    ShaderRead = 1 << 0,
    ShaderWrite = 1 << 1,
    RenderTarget = 1 << 2,
};

inline MetalTextureUsage operator|(MetalTextureUsage lhs, MetalTextureUsage rhs)
{
    return static_cast<MetalTextureUsage>(static_cast<uint32_t>(lhs) | static_cast<uint32_t>(rhs));
}

class MetalTexture {
public:
    explicit MetalTexture(MetalDeviceContext& deviceContext);
    ~MetalTexture();

    MetalTexture(const MetalTexture&) = delete;
    MetalTexture& operator=(const MetalTexture&) = delete;

    MetalTexture(MetalTexture&&) noexcept;
    MetalTexture& operator=(MetalTexture&&) noexcept;

    bool create2D(
        uint32_t width,
        uint32_t height,
        MetalTextureFormat format,
        MetalTextureUsage usage,
        const char* label = nullptr);

    bool upload2D(
        const void* data,
        std::size_t bytesPerRow,
        uint32_t width,
        uint32_t height,
        uint32_t mipLevel = 0);

    bool isValid() const;
    uint32_t width() const;
    uint32_t height() const;
    MetalTextureFormat format() const;
    std::size_t sizeBytes() const;
    void* nativeTexture() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
