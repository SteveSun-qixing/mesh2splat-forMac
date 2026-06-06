#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

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
    Unknown = 0,
    ShaderRead = 1 << 0,
    ShaderWrite = 1 << 1,
    RenderTarget = 1 << 2,
};

enum class MetalTextureType {
    Unknown,
    Texture2D,
    Cube,
};

enum class MetalTextureStorageMode : uint8_t {
    Unknown,
    Shared,
    Managed,
    Private,
    Memoryless,
};

enum class MetalTextureFallbackKind : uint8_t {
    OpaqueWhite,
    OpaqueBlack,
    TransparentBlack,
    FlatNormal,
    MetallicRoughness,
};

struct MetalTexturePixel {
    uint8_t red = 255;
    uint8_t green = 255;
    uint8_t blue = 255;
    uint8_t alpha = 255;
};

struct MetalTextureDesc {
    MetalTextureType type = MetalTextureType::Texture2D;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t depth = 1;
    uint32_t arrayLength = 1;
    uint32_t mipLevelCount = 1;
    MetalTextureFormat format = MetalTextureFormat::RGBA8Unorm;
    MetalTextureUsage usage = MetalTextureUsage::ShaderRead;
    MetalTextureStorageMode storageMode = MetalTextureStorageMode::Private;
    std::string label;
};

struct MetalTextureDiagnostics {
    bool valid = false;
    MetalTextureDesc descriptor;
    std::size_t sizeBytes = 0;
    std::string type;
    std::string format;
    std::string usage;
    std::string storageMode;
    std::string label;
    std::string lastErrorMessage;
};

constexpr MetalTextureUsage operator|(MetalTextureUsage lhs, MetalTextureUsage rhs)
{
    return static_cast<MetalTextureUsage>(static_cast<uint32_t>(lhs) | static_cast<uint32_t>(rhs));
}

constexpr MetalTextureUsage operator&(MetalTextureUsage lhs, MetalTextureUsage rhs)
{
    return static_cast<MetalTextureUsage>(static_cast<uint32_t>(lhs) & static_cast<uint32_t>(rhs));
}

class MetalTexture {
public:
    explicit MetalTexture(MetalDeviceContext& deviceContext);
    ~MetalTexture();

    MetalTexture(const MetalTexture&) = delete;
    MetalTexture& operator=(const MetalTexture&) = delete;

    MetalTexture(MetalTexture&&) noexcept;
    MetalTexture& operator=(MetalTexture&&) noexcept;

    bool create(const MetalTextureDesc& desc);
    bool create2D(
        uint32_t width,
        uint32_t height,
        MetalTextureFormat format,
        MetalTextureUsage usage,
        const char* label = nullptr);
    bool createRenderTarget2D(
        uint32_t width,
        uint32_t height,
        MetalTextureFormat format,
        const char* label = nullptr);
    bool createMipmapped2D(
        uint32_t width,
        uint32_t height,
        uint32_t mipLevelCount,
        MetalTextureFormat format,
        MetalTextureUsage usage,
        const char* label = nullptr);
    bool createCube(
        uint32_t edgeLength,
        MetalTextureFormat format,
        MetalTextureUsage usage,
        const char* label = nullptr);
    bool createDefault2D(
        MetalTextureFormat format,
        MetalTexturePixel pixel = {},
        const char* label = nullptr);
    bool createFallback2D(
        MetalTextureFallbackKind fallback,
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
    uint32_t depth() const;
    uint32_t arrayLength() const;
    uint32_t mipLevelCount() const;
    MetalTextureFormat format() const;
    MetalTextureUsage usage() const;
    MetalTextureStorageMode storageMode() const;
    MetalTextureType textureType() const;
    const MetalTextureDesc& descriptor() const;
    MetalTextureDiagnostics diagnostics() const;
    std::string description() const;
    std::size_t sizeBytes() const;
    bool hasUsage(MetalTextureUsage usage) const;
    bool isShaderReadable() const;
    bool isShaderWritable() const;
    bool isRenderTarget() const;
    bool isMipmapped() const;
    bool isCube() const;
    const std::string& label() const;
    const std::string& lastErrorMessage() const;
    void* nativeTexture() const;

    static const char* formatName(MetalTextureFormat format);
    static const char* storageModeName(MetalTextureStorageMode storageMode);
    static const char* textureTypeName(MetalTextureType type);
    static std::string usageDescription(MetalTextureUsage usage);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
