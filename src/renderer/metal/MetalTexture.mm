#include "MetalTexture.hpp"

#include "MetalDeviceContext.hpp"
#include "MetalResourceUploader.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <limits>
#include <string>
#include <utility>

namespace mesh2splat::metal {

namespace {

MTLPixelFormat toPixelFormat(MetalTextureFormat format)
{
    switch (format) {
    case MetalTextureFormat::BGRA8Unorm:
        return MTLPixelFormatBGRA8Unorm;
    case MetalTextureFormat::BGRA8UnormSrgb:
        return MTLPixelFormatBGRA8Unorm_sRGB;
    case MetalTextureFormat::RGBA8Unorm:
        return MTLPixelFormatRGBA8Unorm;
    case MetalTextureFormat::RGBA8UnormSrgb:
        return MTLPixelFormatRGBA8Unorm_sRGB;
    case MetalTextureFormat::R8Unorm:
        return MTLPixelFormatR8Unorm;
    case MetalTextureFormat::Depth32Float:
        return MTLPixelFormatDepth32Float;
    }

    return MTLPixelFormatInvalid;
}

MTLTextureUsage toTextureUsage(MetalTextureUsage usage)
{
    MTLTextureUsage nativeUsage = MTLTextureUsageUnknown;
    const auto flags = static_cast<uint32_t>(usage);

    if ((flags & static_cast<uint32_t>(MetalTextureUsage::ShaderRead)) != 0) {
        nativeUsage |= MTLTextureUsageShaderRead;
    }
    if ((flags & static_cast<uint32_t>(MetalTextureUsage::ShaderWrite)) != 0) {
        nativeUsage |= MTLTextureUsageShaderWrite;
    }
    if ((flags & static_cast<uint32_t>(MetalTextureUsage::RenderTarget)) != 0) {
        nativeUsage |= MTLTextureUsageRenderTarget;
    }

    return nativeUsage;
}

MTLStorageMode toStorageMode(MetalTextureStorageMode storageMode)
{
    switch (storageMode) {
    case MetalTextureStorageMode::Shared:
        return MTLStorageModeShared;
    case MetalTextureStorageMode::Managed:
        return MTLStorageModeManaged;
    case MetalTextureStorageMode::Private:
        return MTLStorageModePrivate;
    case MetalTextureStorageMode::Memoryless:
        return MTLStorageModeMemoryless;
    case MetalTextureStorageMode::Unknown:
        break;
    }

    return MTLStorageModePrivate;
}

MetalTextureStorageMode fromStorageMode(MTLStorageMode storageMode)
{
    switch (storageMode) {
    case MTLStorageModeShared:
        return MetalTextureStorageMode::Shared;
    case MTLStorageModeManaged:
        return MetalTextureStorageMode::Managed;
    case MTLStorageModePrivate:
        return MetalTextureStorageMode::Private;
    case MTLStorageModeMemoryless:
        return MetalTextureStorageMode::Memoryless;
    default:
        return MetalTextureStorageMode::Unknown;
    }
}

bool checkedMultiply(std::size_t lhs, std::size_t rhs, std::size_t& result)
{
    if (lhs != 0 && rhs > std::numeric_limits<std::size_t>::max() / lhs) {
        return false;
    }

    result = lhs * rhs;
    return true;
}

std::size_t bytesPerPixel(MetalTextureFormat format)
{
    switch (format) {
    case MetalTextureFormat::R8Unorm:
        return 1;
    case MetalTextureFormat::BGRA8Unorm:
    case MetalTextureFormat::BGRA8UnormSrgb:
    case MetalTextureFormat::RGBA8Unorm:
    case MetalTextureFormat::RGBA8UnormSrgb:
    case MetalTextureFormat::Depth32Float:
        return 4;
    }

    return 0;
}

MetalTextureDesc emptyTextureDesc()
{
    MetalTextureDesc desc;
    desc.type = MetalTextureType::Unknown;
    desc.width = 0;
    desc.height = 0;
    desc.depth = 0;
    desc.arrayLength = 0;
    desc.mipLevelCount = 0;
    desc.usage = MetalTextureUsage::Unknown;
    desc.storageMode = MetalTextureStorageMode::Unknown;
    desc.label.clear();
    return desc;
}

std::string labelString(const char* label)
{
    return label == nullptr ? std::string{} : std::string(label);
}

NSString* stringFromUtf8(const std::string& value)
{
    return value.empty() ? nil : [NSString stringWithUTF8String:value.c_str()];
}

bool containsUsage(MetalTextureUsage usage, MetalTextureUsage requested)
{
    const auto usageFlags = static_cast<uint32_t>(usage);
    const auto requestedFlags = static_cast<uint32_t>(requested);
    return requestedFlags != 0 && (usageFlags & requestedFlags) == requestedFlags;
}

uint32_t maxMipLevelCount(uint32_t width, uint32_t height)
{
    uint32_t dimension = std::max(width, height);
    uint32_t levels = 1;
    while (dimension > 1) {
        dimension >>= 1;
        ++levels;
    }

    return levels;
}

std::size_t alignUp(std::size_t value, std::size_t alignment)
{
    if (alignment <= 1) {
        return value;
    }

    const std::size_t remainder = value % alignment;
    return remainder == 0 ? value : value + (alignment - remainder);
}

uint32_t dimensionForMipLevel(uint32_t dimension, uint32_t mipLevel)
{
    if (mipLevel >= std::numeric_limits<uint32_t>::digits) {
        return 1;
    }

    return std::max(1U, dimension >> mipLevel);
}

bool validateTextureDesc(const MetalTextureDesc& desc, std::string& errorMessage)
{
    if (desc.type == MetalTextureType::Unknown) {
        errorMessage = "Metal texture creation failed: texture type is unknown.";
        return false;
    }

    if (desc.type != MetalTextureType::Texture2D && desc.type != MetalTextureType::Cube) {
        errorMessage = "Metal texture creation failed: unsupported texture type.";
        return false;
    }

    if (desc.width == 0 || desc.height == 0) {
        errorMessage = "Metal texture creation failed: width and height must be non-zero.";
        return false;
    }

    if (desc.depth == 0 || desc.arrayLength == 0) {
        errorMessage = "Metal texture creation failed: depth and array length must be non-zero.";
        return false;
    }

    if (desc.mipLevelCount == 0) {
        errorMessage = "Metal texture creation failed: mip level count must be non-zero.";
        return false;
    }

    if (toPixelFormat(desc.format) == MTLPixelFormatInvalid || bytesPerPixel(desc.format) == 0) {
        errorMessage = "Metal texture creation failed: pixel format is unsupported.";
        return false;
    }

    if (desc.storageMode == MetalTextureStorageMode::Unknown) {
        errorMessage = "Metal texture creation failed: storage mode is unknown.";
        return false;
    }

    if (desc.type == MetalTextureType::Texture2D && (desc.depth != 1 || desc.arrayLength != 1)) {
        errorMessage = "Metal texture creation failed: 2D textures require depth and array length of 1.";
        return false;
    }

    if (desc.type == MetalTextureType::Cube) {
        if (desc.width != desc.height) {
            errorMessage = "Metal cube texture creation failed: width and height must match.";
            return false;
        }
        if (desc.depth != 1 || desc.arrayLength != 6) {
            errorMessage = "Metal cube texture creation failed: depth must be 1 and array length must resolve to 6.";
            return false;
        }
    }

    if (desc.mipLevelCount > maxMipLevelCount(desc.width, desc.height)) {
        errorMessage = "Metal texture creation failed: mip level count exceeds the texture dimensions.";
        return false;
    }

    if (desc.storageMode == MetalTextureStorageMode::Memoryless &&
        !containsUsage(desc.usage, MetalTextureUsage::RenderTarget)) {
        errorMessage = "Metal texture creation failed: memoryless textures must be render targets.";
        return false;
    }

    if (desc.storageMode == MetalTextureStorageMode::Memoryless &&
        containsUsage(desc.usage, MetalTextureUsage::ShaderRead)) {
        errorMessage = "Metal texture creation failed: memoryless textures cannot be shader-readable.";
        return false;
    }

    return true;
}

bool pixelBytesForFormat(MetalTextureFormat format, MetalTexturePixel pixel, uint8_t bytes[4], std::size_t& byteCount)
{
    switch (format) {
    case MetalTextureFormat::R8Unorm:
        bytes[0] = pixel.red;
        byteCount = 1;
        return true;
    case MetalTextureFormat::BGRA8Unorm:
    case MetalTextureFormat::BGRA8UnormSrgb:
        bytes[0] = pixel.blue;
        bytes[1] = pixel.green;
        bytes[2] = pixel.red;
        bytes[3] = pixel.alpha;
        byteCount = 4;
        return true;
    case MetalTextureFormat::RGBA8Unorm:
    case MetalTextureFormat::RGBA8UnormSrgb:
        bytes[0] = pixel.red;
        bytes[1] = pixel.green;
        bytes[2] = pixel.blue;
        bytes[3] = pixel.alpha;
        byteCount = 4;
        return true;
    case MetalTextureFormat::Depth32Float:
        break;
    }

    byteCount = 0;
    return false;
}

} // namespace

struct MetalTexture::Impl {
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> commandQueue = nil;
    id<MTLTexture> texture = nil;
    MetalTextureDesc descriptor = emptyTextureDesc();
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t depth = 1;
    uint32_t arrayLength = 1;
    uint32_t mipLevelCount = 1;
    MetalTextureFormat format = MetalTextureFormat::RGBA8Unorm;
    MetalTextureUsage usage = MetalTextureUsage::Unknown;
    MetalTextureType textureType = MetalTextureType::Unknown;
    MTLStorageMode storageMode = MTLStorageModePrivate;
    std::string label;
    std::string lastErrorMessage;

    void clearTextureState()
    {
        texture = nil;
        width = 0;
        height = 0;
        depth = 1;
        arrayLength = 1;
        mipLevelCount = 1;
        format = MetalTextureFormat::RGBA8Unorm;
        usage = MetalTextureUsage::Unknown;
        textureType = MetalTextureType::Unknown;
        storageMode = MTLStorageModePrivate;
        label.clear();
        descriptor = emptyTextureDesc();
    }

    void recordTextureState(id<MTLTexture> sourceTexture, MetalTextureDesc sourceDesc)
    {
        texture = sourceTexture;
        descriptor = std::move(sourceDesc);
        width = descriptor.width;
        height = descriptor.height;
        depth = descriptor.depth;
        arrayLength = descriptor.arrayLength;
        mipLevelCount = descriptor.mipLevelCount;
        format = descriptor.format;
        usage = descriptor.usage;
        textureType = descriptor.type;
        storageMode = sourceTexture == nil ? toStorageMode(descriptor.storageMode) : sourceTexture.storageMode;
        descriptor.storageMode = fromStorageMode(storageMode);
        label = descriptor.label;
    }

    void setError(std::string message)
    {
        lastErrorMessage = std::move(message);
    }

    void clearError()
    {
        lastErrorMessage.clear();
    }

    bool hasConsistentNativeState() const
    {
        if (texture == nil) {
            return false;
        }
        if (width == 0 || height == 0 || depth == 0 || arrayLength == 0 || mipLevelCount == 0) {
            return false;
        }
        if (texture.width != width ||
            texture.height != height ||
            texture.depth != depth ||
            texture.arrayLength != arrayLength ||
            texture.mipmapLevelCount != mipLevelCount ||
            texture.pixelFormat != toPixelFormat(format) ||
            texture.storageMode != storageMode) {
            return false;
        }
        if (textureType == MetalTextureType::Texture2D && texture.textureType != MTLTextureType2D) {
            return false;
        }
        if (textureType == MetalTextureType::Cube && texture.textureType != MTLTextureTypeCube) {
            return false;
        }

        return true;
    }
};

MetalTexture::MetalTexture(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)deviceContext.nativeDevice();
    m_impl->commandQueue = (__bridge id<MTLCommandQueue>)deviceContext.nativeCommandQueue();
}

MetalTexture::~MetalTexture() = default;

MetalTexture::MetalTexture(MetalTexture&&) noexcept = default;

MetalTexture& MetalTexture::operator=(MetalTexture&&) noexcept = default;

bool MetalTexture::create(const MetalTextureDesc& desc)
{
    if (m_impl->device == nil) {
        m_impl->setError("Metal texture creation failed: Metal device is unavailable.");
        return false;
    }

    MetalTextureDesc normalizedDesc = desc;
    if (normalizedDesc.type == MetalTextureType::Cube && normalizedDesc.arrayLength == 1) {
        normalizedDesc.arrayLength = 6;
    }
    if (normalizedDesc.label.empty()) {
        normalizedDesc.label = "Metal Texture";
    }

    std::string validationError;
    if (!validateTextureDesc(normalizedDesc, validationError)) {
        m_impl->setError(std::move(validationError));
        return false;
    }

    const MTLPixelFormat pixelFormat = toPixelFormat(normalizedDesc.format);
    MTLTextureDescriptor* nativeDescriptor = nil;
    if (normalizedDesc.type == MetalTextureType::Cube) {
        nativeDescriptor =
            [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:pixelFormat
                                                                  size:normalizedDesc.width
                                                             mipmapped:normalizedDesc.mipLevelCount > 1];
    } else {
        nativeDescriptor =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
                                                               width:normalizedDesc.width
                                                              height:normalizedDesc.height
                                                           mipmapped:normalizedDesc.mipLevelCount > 1];
    }

    nativeDescriptor.mipmapLevelCount = normalizedDesc.mipLevelCount;
    nativeDescriptor.usage = toTextureUsage(normalizedDesc.usage);
    nativeDescriptor.storageMode = toStorageMode(normalizedDesc.storageMode);

    id<MTLTexture> nativeTexture = [m_impl->device newTextureWithDescriptor:nativeDescriptor];
    if (nativeTexture == nil) {
        m_impl->clearTextureState();
        m_impl->setError(
            "Metal texture creation failed: MTLDevice returned nil for descriptor " +
            std::to_string(normalizedDesc.width) + "x" + std::to_string(normalizedDesc.height) +
            ", format=" + formatName(normalizedDesc.format) +
            ", usage=" + usageDescription(normalizedDesc.usage) +
            ", storage=" + storageModeName(normalizedDesc.storageMode) + ".");
        return false;
    }

    nativeTexture.label = stringFromUtf8(normalizedDesc.label);

    m_impl->recordTextureState(nativeTexture, std::move(normalizedDesc));
    m_impl->clearError();
    return true;
}

bool MetalTexture::create2D(
    uint32_t width,
    uint32_t height,
    MetalTextureFormat format,
    MetalTextureUsage usage,
    const char* label)
{
    MetalTextureDesc desc;
    desc.type = MetalTextureType::Texture2D;
    desc.width = width;
    desc.height = height;
    desc.depth = 1;
    desc.arrayLength = 1;
    desc.mipLevelCount = 1;
    desc.format = format;
    desc.usage = usage;
    desc.storageMode = MetalTextureStorageMode::Private;
    desc.label = labelString(label);
    return create(desc);
}

bool MetalTexture::createRenderTarget2D(
    uint32_t width,
    uint32_t height,
    MetalTextureFormat format,
    const char* label)
{
    return create2D(
        width,
        height,
        format,
        MetalTextureUsage::ShaderRead | MetalTextureUsage::RenderTarget,
        label);
}

bool MetalTexture::createMipmapped2D(
    uint32_t width,
    uint32_t height,
    uint32_t mipLevelCount,
    MetalTextureFormat format,
    MetalTextureUsage usage,
    const char* label)
{
    MetalTextureDesc desc;
    desc.type = MetalTextureType::Texture2D;
    desc.width = width;
    desc.height = height;
    desc.depth = 1;
    desc.arrayLength = 1;
    desc.mipLevelCount = mipLevelCount;
    desc.format = format;
    desc.usage = usage;
    desc.storageMode = MetalTextureStorageMode::Private;
    desc.label = labelString(label);
    return create(desc);
}

bool MetalTexture::createCube(
    uint32_t edgeLength,
    MetalTextureFormat format,
    MetalTextureUsage usage,
    const char* label)
{
    MetalTextureDesc desc;
    desc.type = MetalTextureType::Cube;
    desc.width = edgeLength;
    desc.height = edgeLength;
    desc.depth = 1;
    desc.arrayLength = 6;
    desc.mipLevelCount = 1;
    desc.format = format;
    desc.usage = usage;
    desc.storageMode = MetalTextureStorageMode::Private;
    desc.label = labelString(label);
    return create(desc);
}

bool MetalTexture::createDefault2D(
    MetalTextureFormat format,
    MetalTexturePixel pixel,
    const char* label)
{
    uint8_t bytes[4] = {};
    std::size_t byteCount = 0;
    if (!pixelBytesForFormat(format, pixel, bytes, byteCount)) {
        m_impl->setError("Metal default texture creation failed: pixel format cannot be filled from RGBA8 data.");
        return false;
    }

    const std::string debugLabel = labelString(label);
    if (!create2D(
            1,
            1,
            format,
            MetalTextureUsage::ShaderRead,
            debugLabel.empty() ? "Metal Default Texture" : debugLabel.c_str())) {
        return false;
    }

    return upload2D(bytes, byteCount, 1, 1);
}

bool MetalTexture::createFallback2D(
    MetalTextureFallbackKind fallback,
    const char* label)
{
    MetalTexturePixel pixel;
    const char* fallbackLabel = "Metal Fallback Texture";
    switch (fallback) {
    case MetalTextureFallbackKind::OpaqueWhite:
        pixel = {255, 255, 255, 255};
        fallbackLabel = "Metal Opaque White Fallback Texture";
        break;
    case MetalTextureFallbackKind::OpaqueBlack:
        pixel = {0, 0, 0, 255};
        fallbackLabel = "Metal Opaque Black Fallback Texture";
        break;
    case MetalTextureFallbackKind::TransparentBlack:
        pixel = {0, 0, 0, 0};
        fallbackLabel = "Metal Transparent Black Fallback Texture";
        break;
    case MetalTextureFallbackKind::FlatNormal:
        pixel = {128, 128, 255, 255};
        fallbackLabel = "Metal Flat Normal Fallback Texture";
        break;
    case MetalTextureFallbackKind::MetallicRoughness:
        pixel = {255, 255, 255, 255};
        fallbackLabel = "Metal Metallic Roughness Fallback Texture";
        break;
    }

    return createDefault2D(
        MetalTextureFormat::RGBA8Unorm,
        pixel,
        label == nullptr ? fallbackLabel : label);
}

bool MetalTexture::upload2D(
    const void* data,
    std::size_t bytesPerRow,
    uint32_t width,
    uint32_t height,
    uint32_t mipLevel)
{
    if (m_impl->texture == nil) {
        m_impl->setError("Metal texture upload failed: texture is not valid.");
        return false;
    }
    if (data == nullptr) {
        m_impl->setError("Metal texture upload failed: source data is null.");
        return false;
    }
    if (bytesPerRow == 0) {
        m_impl->setError("Metal texture upload failed: bytesPerRow must be non-zero.");
        return false;
    }
    if (width == 0 || height == 0) {
        m_impl->setError("Metal texture upload failed: width and height must be non-zero.");
        return false;
    }
    if (m_impl->textureType != MetalTextureType::Texture2D) {
        m_impl->setError("Metal texture upload failed: upload2D only supports 2D textures.");
        return false;
    }

    if (mipLevel >= m_impl->mipLevelCount) {
        m_impl->setError(
            "Metal texture upload failed: mip level " + std::to_string(mipLevel) +
            " exceeds texture mip count " + std::to_string(m_impl->mipLevelCount) + ".");
        return false;
    }

    const uint32_t mipWidth = dimensionForMipLevel(m_impl->width, mipLevel);
    const uint32_t mipHeight = dimensionForMipLevel(m_impl->height, mipLevel);
    if (width > mipWidth || height > mipHeight) {
        m_impl->setError("Metal texture upload failed: upload region exceeds the texture dimensions.");
        return false;
    }

    std::size_t rowBytes = 0;
    if (!checkedMultiply(bytesPerPixel(m_impl->format), static_cast<std::size_t>(width), rowBytes)) {
        m_impl->setError("Metal texture upload failed: row byte count overflowed.");
        return false;
    }
    if (rowBytes == 0 || bytesPerRow < rowBytes) {
        m_impl->setError("Metal texture upload failed: bytesPerRow is smaller than the format row size.");
        return false;
    }

    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    if (storageMode() == MetalTextureStorageMode::Memoryless) {
        m_impl->setError("Metal texture upload failed: memoryless render-target textures are not uploadable.");
        return false;
    }

    if (m_impl->storageMode != MTLStorageModePrivate) {
        [m_impl->texture replaceRegion:region
                            mipmapLevel:mipLevel
                              withBytes:data
                            bytesPerRow:bytesPerRow];
        m_impl->clearError();
        return true;
    }

    if (m_impl->device == nil || m_impl->commandQueue == nil) {
        m_impl->setError("Metal texture upload failed: Metal device or command queue is unavailable.");
        return false;
    }

    constexpr std::size_t kTextureUploadRowAlignment = 256;
    const std::size_t alignedBytesPerRow = alignUp(rowBytes, kTextureUploadRowAlignment);
    if (height > 0 && alignedBytesPerRow > std::numeric_limits<std::size_t>::max() / height) {
        m_impl->setError("Metal texture upload failed: aligned upload size overflowed.");
        return false;
    }

    const std::size_t uploadSize = alignedBytesPerRow * static_cast<std::size_t>(height);
    MetalResourceUploader uploader((__bridge void*)m_impl->device, (__bridge void*)m_impl->commandQueue);
    NSString* textureLabel = m_impl->texture.label == nil ? @"MetalTexture" : m_impl->texture.label;
    std::string uploadError;
    const bool uploaded = uploader.uploadTexture2DToPrivate(
        data,
        bytesPerRow,
        rowBytes,
        alignedBytesPerRow,
        uploadSize,
        width,
        height,
        mipLevel,
        (__bridge void*)m_impl->texture,
        textureLabel.UTF8String,
        &uploadError);
    if (!uploaded) {
        m_impl->setError(
            uploadError.empty()
                ? "Metal texture upload failed: private texture staging upload did not complete."
                : uploadError);
        return false;
    }

    m_impl->clearError();
    return true;
}

bool MetalTexture::isValid() const
{
    return m_impl->hasConsistentNativeState();
}

uint32_t MetalTexture::width() const
{
    return m_impl->width;
}

uint32_t MetalTexture::height() const
{
    return m_impl->height;
}

uint32_t MetalTexture::depth() const
{
    return m_impl->depth;
}

uint32_t MetalTexture::arrayLength() const
{
    return m_impl->arrayLength;
}

uint32_t MetalTexture::mipLevelCount() const
{
    return m_impl->mipLevelCount;
}

MetalTextureFormat MetalTexture::format() const
{
    return m_impl->format;
}

MetalTextureUsage MetalTexture::usage() const
{
    return m_impl->usage;
}

MetalTextureStorageMode MetalTexture::storageMode() const
{
    return fromStorageMode(m_impl->storageMode);
}

MetalTextureType MetalTexture::textureType() const
{
    return m_impl->textureType;
}

const MetalTextureDesc& MetalTexture::descriptor() const
{
    return m_impl->descriptor;
}

MetalTextureDiagnostics MetalTexture::diagnostics() const
{
    MetalTextureDiagnostics diagnostics;
    diagnostics.valid = isValid();
    diagnostics.descriptor = m_impl->descriptor;
    diagnostics.sizeBytes = sizeBytes();
    diagnostics.type = textureTypeName(m_impl->textureType);
    diagnostics.format = formatName(m_impl->format);
    diagnostics.usage = usageDescription(m_impl->usage);
    diagnostics.storageMode = storageModeName(storageMode());
    diagnostics.label = m_impl->label;
    diagnostics.lastErrorMessage = m_impl->lastErrorMessage;
    return diagnostics;
}

std::string MetalTexture::description() const
{
    std::string result = "MetalTexture(";
    result += isValid() ? "valid" : "invalid";
    result += ", type=";
    result += textureTypeName(m_impl->textureType);
    result += ", size=";
    result += std::to_string(m_impl->width);
    result += "x";
    result += std::to_string(m_impl->height);
    result += ", mips=";
    result += std::to_string(m_impl->mipLevelCount);
    result += ", format=";
    result += formatName(m_impl->format);
    result += ", usage=";
    result += usageDescription(m_impl->usage);
    result += ", storage=";
    result += storageModeName(storageMode());
    if (!m_impl->label.empty()) {
        result += ", label=";
        result += m_impl->label;
    }
    if (!m_impl->lastErrorMessage.empty()) {
        result += ", lastError=";
        result += m_impl->lastErrorMessage;
    }
    result += ")";
    return result;
}

std::size_t MetalTexture::sizeBytes() const
{
    if (m_impl->texture == nil || m_impl->width == 0 || m_impl->height == 0) {
        return 0;
    }

    const std::size_t pixelBytes = bytesPerPixel(m_impl->format);
    if (pixelBytes == 0 ||
        m_impl->width > std::numeric_limits<std::size_t>::max() / pixelBytes) {
        return 0;
    }

    std::size_t total = 0;
    for (uint32_t mipLevel = 0; mipLevel < m_impl->mipLevelCount; ++mipLevel) {
        const std::size_t mipWidth = dimensionForMipLevel(m_impl->width, mipLevel);
        const std::size_t mipHeight = dimensionForMipLevel(m_impl->height, mipLevel);
        if (mipWidth > std::numeric_limits<std::size_t>::max() / pixelBytes) {
            return 0;
        }

        std::size_t rowBytes = 0;
        if (!checkedMultiply(mipWidth, pixelBytes, rowBytes)) {
            return 0;
        }
        if (mipHeight > std::numeric_limits<std::size_t>::max() / rowBytes) {
            return 0;
        }

        std::size_t sliceBytes = 0;
        if (!checkedMultiply(rowBytes, mipHeight, sliceBytes)) {
            return 0;
        }

        std::size_t layerCount = 0;
        if (!checkedMultiply(
                static_cast<std::size_t>(std::max(1U, m_impl->depth)),
                static_cast<std::size_t>(std::max(1U, m_impl->arrayLength)),
                layerCount)) {
            return 0;
        }

        std::size_t mipBytes = 0;
        if (!checkedMultiply(sliceBytes, layerCount, mipBytes)) {
            return 0;
        }
        if (mipBytes > std::numeric_limits<std::size_t>::max() - total) {
            return 0;
        }

        total += mipBytes;
    }

    return total;
}

bool MetalTexture::hasUsage(MetalTextureUsage usage) const
{
    return containsUsage(m_impl->usage, usage);
}

bool MetalTexture::isShaderReadable() const
{
    return hasUsage(MetalTextureUsage::ShaderRead);
}

bool MetalTexture::isShaderWritable() const
{
    return hasUsage(MetalTextureUsage::ShaderWrite);
}

bool MetalTexture::isRenderTarget() const
{
    return hasUsage(MetalTextureUsage::RenderTarget);
}

bool MetalTexture::isMipmapped() const
{
    return m_impl->mipLevelCount > 1;
}

bool MetalTexture::isCube() const
{
    return m_impl->textureType == MetalTextureType::Cube;
}

const std::string& MetalTexture::label() const
{
    return m_impl->label;
}

const std::string& MetalTexture::lastErrorMessage() const
{
    return m_impl->lastErrorMessage;
}

void* MetalTexture::nativeTexture() const
{
    return (__bridge void*)m_impl->texture;
}

const char* MetalTexture::formatName(MetalTextureFormat format)
{
    switch (format) {
    case MetalTextureFormat::BGRA8Unorm:
        return "BGRA8Unorm";
    case MetalTextureFormat::BGRA8UnormSrgb:
        return "BGRA8UnormSrgb";
    case MetalTextureFormat::RGBA8Unorm:
        return "RGBA8Unorm";
    case MetalTextureFormat::RGBA8UnormSrgb:
        return "RGBA8UnormSrgb";
    case MetalTextureFormat::R8Unorm:
        return "R8Unorm";
    case MetalTextureFormat::Depth32Float:
        return "Depth32Float";
    }

    return "Unknown";
}

const char* MetalTexture::storageModeName(MetalTextureStorageMode storageMode)
{
    switch (storageMode) {
    case MetalTextureStorageMode::Shared:
        return "shared";
    case MetalTextureStorageMode::Managed:
        return "managed";
    case MetalTextureStorageMode::Private:
        return "private";
    case MetalTextureStorageMode::Memoryless:
        return "memoryless";
    case MetalTextureStorageMode::Unknown:
        break;
    }

    return "unknown";
}

const char* MetalTexture::textureTypeName(MetalTextureType type)
{
    switch (type) {
    case MetalTextureType::Texture2D:
        return "2d";
    case MetalTextureType::Cube:
        return "cube";
    case MetalTextureType::Unknown:
        break;
    }

    return "unknown";
}

std::string MetalTexture::usageDescription(MetalTextureUsage usage)
{
    const auto flags = static_cast<uint32_t>(usage);
    if (flags == 0) {
        return "unknown";
    }

    std::string result;
    auto append = [&result](const char* name) {
        if (!result.empty()) {
            result += "|";
        }
        result += name;
    };

    if ((flags & static_cast<uint32_t>(MetalTextureUsage::ShaderRead)) != 0) {
        append("shader-read");
    }
    if ((flags & static_cast<uint32_t>(MetalTextureUsage::ShaderWrite)) != 0) {
        append("shader-write");
    }
    if ((flags & static_cast<uint32_t>(MetalTextureUsage::RenderTarget)) != 0) {
        append("render-target");
    }

    return result.empty() ? "unknown" : result;
}

} // namespace mesh2splat::metal
