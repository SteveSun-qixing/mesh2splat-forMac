#include "MetalTexture.hpp"

#include "MetalDeviceContext.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

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

bool isDepthFormat(MetalTextureFormat format)
{
    return format == MetalTextureFormat::Depth32Float;
}

} // namespace

struct MetalTexture::Impl {
    id<MTLDevice> device = nil;
    id<MTLTexture> texture = nil;
    uint32_t width = 0;
    uint32_t height = 0;
    MetalTextureFormat format = MetalTextureFormat::RGBA8Unorm;
};

MetalTexture::MetalTexture(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)deviceContext.nativeDevice();
}

MetalTexture::~MetalTexture() = default;

MetalTexture::MetalTexture(MetalTexture&&) noexcept = default;

MetalTexture& MetalTexture::operator=(MetalTexture&&) noexcept = default;

bool MetalTexture::create2D(
    uint32_t width,
    uint32_t height,
    MetalTextureFormat format,
    MetalTextureUsage usage,
    const char* label)
{
    if (m_impl->device == nil || width == 0 || height == 0) {
        return false;
    }

    MTLTextureDescriptor* descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:toPixelFormat(format)
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    descriptor.usage = toTextureUsage(usage);
    descriptor.storageMode = MTLStorageModePrivate;

    const auto usageFlags = static_cast<uint32_t>(usage);
    const bool cpuUploadedTexture =
        !isDepthFormat(format) &&
        (usageFlags & static_cast<uint32_t>(MetalTextureUsage::ShaderRead)) != 0 &&
        (usageFlags & static_cast<uint32_t>(MetalTextureUsage::ShaderWrite)) == 0 &&
        (usageFlags & static_cast<uint32_t>(MetalTextureUsage::RenderTarget)) == 0;

    if (cpuUploadedTexture) {
        descriptor.storageMode = MTLStorageModeManaged;
    }

    m_impl->texture = [m_impl->device newTextureWithDescriptor:descriptor];
    if (m_impl->texture == nil) {
        m_impl->width = 0;
        m_impl->height = 0;
        return false;
    }

    if (label != nullptr) {
        m_impl->texture.label = [NSString stringWithUTF8String:label];
    }

    m_impl->width = width;
    m_impl->height = height;
    m_impl->format = format;
    return true;
}

bool MetalTexture::upload2D(
    const void* data,
    std::size_t bytesPerRow,
    uint32_t width,
    uint32_t height,
    uint32_t mipLevel)
{
    if (m_impl->texture == nil || data == nullptr || width == 0 || height == 0 ||
        width > m_impl->width || height > m_impl->height) {
        return false;
    }

    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [m_impl->texture replaceRegion:region
                        mipmapLevel:mipLevel
                          withBytes:data
                        bytesPerRow:bytesPerRow];
    return true;
}

bool MetalTexture::isValid() const
{
    return m_impl->texture != nil;
}

uint32_t MetalTexture::width() const
{
    return m_impl->width;
}

uint32_t MetalTexture::height() const
{
    return m_impl->height;
}

MetalTextureFormat MetalTexture::format() const
{
    return m_impl->format;
}

void* MetalTexture::nativeTexture() const
{
    return (__bridge void*)m_impl->texture;
}

} // namespace mesh2splat::metal
