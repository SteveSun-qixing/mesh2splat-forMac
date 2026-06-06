#include "MetalRenderStateCache.hpp"

#include "MetalDeviceContext.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <cstdint>
#include <sstream>
#include <unordered_map>
#include <utility>

namespace mesh2splat::metal {
namespace {

std::string boolName(bool value)
{
    return value ? "true" : "false";
}

NSString* toNSString(const std::string& value)
{
    return [NSString stringWithUTF8String:value.c_str()];
}

void setDiagnostic(std::string* diagnostic, const std::string& message)
{
    if (diagnostic != nullptr) {
        *diagnostic = message;
    }
}

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

bool isDepthFormat(MetalTextureFormat format)
{
    return format == MetalTextureFormat::Depth32Float;
}

bool isColorFormat(MetalTextureFormat format)
{
    return toPixelFormat(format) != MTLPixelFormatInvalid && !isDepthFormat(format);
}

std::string textureFormatName(MetalTextureFormat format)
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

    return "Unknown(" + std::to_string(static_cast<int>(format)) + ")";
}

std::string pixelFormatDescription(MetalTextureFormat format)
{
    std::ostringstream description;
    description << textureFormatName(format) << "(MTL=" << static_cast<unsigned long>(toPixelFormat(format)) << ")";
    return description.str();
}

MTLSamplerMinMagFilter toMinMagFilter(MetalSamplerFilter filter)
{
    switch (filter) {
    case MetalSamplerFilter::Nearest:
        return MTLSamplerMinMagFilterNearest;
    case MetalSamplerFilter::Linear:
        return MTLSamplerMinMagFilterLinear;
    }

    return MTLSamplerMinMagFilterLinear;
}

MTLSamplerMipFilter toMipFilter(MetalSamplerFilter filter)
{
    switch (filter) {
    case MetalSamplerFilter::Nearest:
        return MTLSamplerMipFilterNearest;
    case MetalSamplerFilter::Linear:
        return MTLSamplerMipFilterLinear;
    }

    return MTLSamplerMipFilterLinear;
}

MTLSamplerAddressMode toAddressMode(MetalSamplerAddressMode mode)
{
    switch (mode) {
    case MetalSamplerAddressMode::ClampToEdge:
        return MTLSamplerAddressModeClampToEdge;
    case MetalSamplerAddressMode::Repeat:
        return MTLSamplerAddressModeRepeat;
    case MetalSamplerAddressMode::MirrorRepeat:
        return MTLSamplerAddressModeMirrorRepeat;
    }

    return MTLSamplerAddressModeRepeat;
}

MTLCompareFunction toCompareFunction(MetalCompareFunction function)
{
    switch (function) {
    case MetalCompareFunction::Never:
        return MTLCompareFunctionNever;
    case MetalCompareFunction::Less:
        return MTLCompareFunctionLess;
    case MetalCompareFunction::LessEqual:
        return MTLCompareFunctionLessEqual;
    case MetalCompareFunction::Equal:
        return MTLCompareFunctionEqual;
    case MetalCompareFunction::Greater:
        return MTLCompareFunctionGreater;
    case MetalCompareFunction::GreaterEqual:
        return MTLCompareFunctionGreaterEqual;
    case MetalCompareFunction::Always:
        return MTLCompareFunctionAlways;
    }

    return MTLCompareFunctionAlways;
}

MTLStencilOperation toStencilOperation(MetalStencilOperation operation)
{
    switch (operation) {
    case MetalStencilOperation::Keep:
        return MTLStencilOperationKeep;
    case MetalStencilOperation::Zero:
        return MTLStencilOperationZero;
    case MetalStencilOperation::Replace:
        return MTLStencilOperationReplace;
    case MetalStencilOperation::IncrementClamp:
        return MTLStencilOperationIncrementClamp;
    case MetalStencilOperation::DecrementClamp:
        return MTLStencilOperationDecrementClamp;
    case MetalStencilOperation::Invert:
        return MTLStencilOperationInvert;
    case MetalStencilOperation::IncrementWrap:
        return MTLStencilOperationIncrementWrap;
    case MetalStencilOperation::DecrementWrap:
        return MTLStencilOperationDecrementWrap;
    }

    return MTLStencilOperationKeep;
}

MTLBlendFactor toBlendFactor(MetalRenderBlendFactor factor)
{
    switch (factor) {
    case MetalRenderBlendFactor::Zero:
        return MTLBlendFactorZero;
    case MetalRenderBlendFactor::One:
        return MTLBlendFactorOne;
    case MetalRenderBlendFactor::SourceColor:
        return MTLBlendFactorSourceColor;
    case MetalRenderBlendFactor::OneMinusSourceColor:
        return MTLBlendFactorOneMinusSourceColor;
    case MetalRenderBlendFactor::SourceAlpha:
        return MTLBlendFactorSourceAlpha;
    case MetalRenderBlendFactor::OneMinusSourceAlpha:
        return MTLBlendFactorOneMinusSourceAlpha;
    case MetalRenderBlendFactor::DestinationColor:
        return MTLBlendFactorDestinationColor;
    case MetalRenderBlendFactor::OneMinusDestinationColor:
        return MTLBlendFactorOneMinusDestinationColor;
    case MetalRenderBlendFactor::DestinationAlpha:
        return MTLBlendFactorDestinationAlpha;
    case MetalRenderBlendFactor::OneMinusDestinationAlpha:
        return MTLBlendFactorOneMinusDestinationAlpha;
    case MetalRenderBlendFactor::SourceAlphaSaturated:
        return MTLBlendFactorSourceAlphaSaturated;
    case MetalRenderBlendFactor::BlendColor:
        return MTLBlendFactorBlendColor;
    case MetalRenderBlendFactor::OneMinusBlendColor:
        return MTLBlendFactorOneMinusBlendColor;
    case MetalRenderBlendFactor::BlendAlpha:
        return MTLBlendFactorBlendAlpha;
    case MetalRenderBlendFactor::OneMinusBlendAlpha:
        return MTLBlendFactorOneMinusBlendAlpha;
    }

    return MTLBlendFactorOne;
}

MTLBlendOperation toBlendOperation(MetalRenderBlendOperation operation)
{
    switch (operation) {
    case MetalRenderBlendOperation::Add:
        return MTLBlendOperationAdd;
    case MetalRenderBlendOperation::Subtract:
        return MTLBlendOperationSubtract;
    case MetalRenderBlendOperation::ReverseSubtract:
        return MTLBlendOperationReverseSubtract;
    case MetalRenderBlendOperation::Min:
        return MTLBlendOperationMin;
    case MetalRenderBlendOperation::Max:
        return MTLBlendOperationMax;
    }

    return MTLBlendOperationAdd;
}

MTLColorWriteMask toColorWriteMask(MetalColorWriteMask writeMask)
{
    const uint8_t flags = static_cast<uint8_t>(writeMask);
    MTLColorWriteMask nativeMask = MTLColorWriteMaskNone;
    if ((flags & static_cast<uint8_t>(MetalColorWriteMask::Red)) != 0) {
        nativeMask |= MTLColorWriteMaskRed;
    }
    if ((flags & static_cast<uint8_t>(MetalColorWriteMask::Green)) != 0) {
        nativeMask |= MTLColorWriteMaskGreen;
    }
    if ((flags & static_cast<uint8_t>(MetalColorWriteMask::Blue)) != 0) {
        nativeMask |= MTLColorWriteMaskBlue;
    }
    if ((flags & static_cast<uint8_t>(MetalColorWriteMask::Alpha)) != 0) {
        nativeMask |= MTLColorWriteMaskAlpha;
    }
    return nativeMask;
}

std::string samplerFilterName(MetalSamplerFilter filter)
{
    switch (filter) {
    case MetalSamplerFilter::Nearest:
        return "Nearest";
    case MetalSamplerFilter::Linear:
        return "Linear";
    }

    return "Unknown(" + std::to_string(static_cast<int>(filter)) + ")";
}

std::string addressModeName(MetalSamplerAddressMode mode)
{
    switch (mode) {
    case MetalSamplerAddressMode::ClampToEdge:
        return "ClampToEdge";
    case MetalSamplerAddressMode::Repeat:
        return "Repeat";
    case MetalSamplerAddressMode::MirrorRepeat:
        return "MirrorRepeat";
    }

    return "Unknown(" + std::to_string(static_cast<int>(mode)) + ")";
}

std::string compareFunctionName(MetalCompareFunction function)
{
    switch (function) {
    case MetalCompareFunction::Never:
        return "Never";
    case MetalCompareFunction::Less:
        return "Less";
    case MetalCompareFunction::LessEqual:
        return "LessEqual";
    case MetalCompareFunction::Equal:
        return "Equal";
    case MetalCompareFunction::Greater:
        return "Greater";
    case MetalCompareFunction::GreaterEqual:
        return "GreaterEqual";
    case MetalCompareFunction::Always:
        return "Always";
    }

    return "Unknown(" + std::to_string(static_cast<int>(function)) + ")";
}

std::string stencilOperationName(MetalStencilOperation operation)
{
    switch (operation) {
    case MetalStencilOperation::Keep:
        return "Keep";
    case MetalStencilOperation::Zero:
        return "Zero";
    case MetalStencilOperation::Replace:
        return "Replace";
    case MetalStencilOperation::IncrementClamp:
        return "IncrementClamp";
    case MetalStencilOperation::DecrementClamp:
        return "DecrementClamp";
    case MetalStencilOperation::Invert:
        return "Invert";
    case MetalStencilOperation::IncrementWrap:
        return "IncrementWrap";
    case MetalStencilOperation::DecrementWrap:
        return "DecrementWrap";
    }

    return "Unknown(" + std::to_string(static_cast<int>(operation)) + ")";
}

std::string blendFactorName(MetalRenderBlendFactor factor)
{
    switch (factor) {
    case MetalRenderBlendFactor::Zero:
        return "Zero";
    case MetalRenderBlendFactor::One:
        return "One";
    case MetalRenderBlendFactor::SourceColor:
        return "SourceColor";
    case MetalRenderBlendFactor::OneMinusSourceColor:
        return "OneMinusSourceColor";
    case MetalRenderBlendFactor::SourceAlpha:
        return "SourceAlpha";
    case MetalRenderBlendFactor::OneMinusSourceAlpha:
        return "OneMinusSourceAlpha";
    case MetalRenderBlendFactor::DestinationColor:
        return "DestinationColor";
    case MetalRenderBlendFactor::OneMinusDestinationColor:
        return "OneMinusDestinationColor";
    case MetalRenderBlendFactor::DestinationAlpha:
        return "DestinationAlpha";
    case MetalRenderBlendFactor::OneMinusDestinationAlpha:
        return "OneMinusDestinationAlpha";
    case MetalRenderBlendFactor::SourceAlphaSaturated:
        return "SourceAlphaSaturated";
    case MetalRenderBlendFactor::BlendColor:
        return "BlendColor";
    case MetalRenderBlendFactor::OneMinusBlendColor:
        return "OneMinusBlendColor";
    case MetalRenderBlendFactor::BlendAlpha:
        return "BlendAlpha";
    case MetalRenderBlendFactor::OneMinusBlendAlpha:
        return "OneMinusBlendAlpha";
    }

    return "Unknown(" + std::to_string(static_cast<int>(factor)) + ")";
}

std::string blendOperationName(MetalRenderBlendOperation operation)
{
    switch (operation) {
    case MetalRenderBlendOperation::Add:
        return "Add";
    case MetalRenderBlendOperation::Subtract:
        return "Subtract";
    case MetalRenderBlendOperation::ReverseSubtract:
        return "ReverseSubtract";
    case MetalRenderBlendOperation::Min:
        return "Min";
    case MetalRenderBlendOperation::Max:
        return "Max";
    }

    return "Unknown(" + std::to_string(static_cast<int>(operation)) + ")";
}

std::string writeMaskName(MetalColorWriteMask writeMask)
{
    const uint8_t flags = static_cast<uint8_t>(writeMask);
    if (flags == static_cast<uint8_t>(MetalColorWriteMask::None)) {
        return "None";
    }
    if (flags == static_cast<uint8_t>(MetalColorWriteMask::All)) {
        return "All";
    }

    std::string name;
    const auto appendChannel = [&name](const char* channel) {
        if (!name.empty()) {
            name += "|";
        }
        name += channel;
    };
    if ((flags & static_cast<uint8_t>(MetalColorWriteMask::Red)) != 0) {
        appendChannel("Red");
    }
    if ((flags & static_cast<uint8_t>(MetalColorWriteMask::Green)) != 0) {
        appendChannel("Green");
    }
    if ((flags & static_cast<uint8_t>(MetalColorWriteMask::Blue)) != 0) {
        appendChannel("Blue");
    }
    if ((flags & static_cast<uint8_t>(MetalColorWriteMask::Alpha)) != 0) {
        appendChannel("Alpha");
    }
    return name.empty() ? "None" : name;
}

void appendKeyString(std::ostringstream& key, const char* name, const std::string& value)
{
    key << name << '[' << value.size() << "]=" << value << ';';
}

void appendKeyValue(std::ostringstream& key, const char* name, const std::string& value)
{
    key << name << '=' << value << ';';
}

void appendKeyValue(std::ostringstream& key, const char* name, uint32_t value)
{
    key << name << '=' << value << ';';
}

void appendKeyValue(std::ostringstream& key, const char* name, bool value)
{
    appendKeyValue(key, name, boolName(value));
}

std::string stencilFaceKey(const MetalStencilFaceDesc& desc)
{
    std::ostringstream key;
    appendKeyValue(key, "compare", compareFunctionName(desc.compareFunction));
    appendKeyValue(key, "stencilFail", stencilOperationName(desc.stencilFailureOperation));
    appendKeyValue(key, "depthFail", stencilOperationName(desc.depthFailureOperation));
    appendKeyValue(key, "depthStencilPass", stencilOperationName(desc.depthStencilPassOperation));
    appendKeyValue(key, "readMask", desc.readMask);
    appendKeyValue(key, "writeMask", desc.writeMask);
    return key.str();
}

std::string samplerKey(const MetalSamplerDesc& desc)
{
    std::ostringstream key;
    key << "sampler;";
    appendKeyValue(key, "minFilter", samplerFilterName(desc.minFilter));
    appendKeyValue(key, "magFilter", samplerFilterName(desc.magFilter));
    appendKeyValue(key, "mipFilter", samplerFilterName(desc.mipFilter));
    appendKeyValue(key, "addressU", addressModeName(desc.addressU));
    appendKeyValue(key, "addressV", addressModeName(desc.addressV));
    appendKeyValue(key, "addressW", addressModeName(desc.addressW));
    appendKeyValue(key, "maxAnisotropy", std::max<uint32_t>(desc.maxAnisotropy, 1));
    appendKeyValue(key, "normalizedCoordinates", desc.normalizedCoordinates);
    return key.str();
}

std::string depthStencilKey(const MetalDepthStencilDesc& desc)
{
    std::ostringstream key;
    key << "depthStencil;";
    appendKeyValue(key, "depthTestEnabled", desc.depthTestEnabled);
    appendKeyValue(key, "depthWriteEnabled", desc.depthTestEnabled && desc.depthWriteEnabled);
    appendKeyValue(
        key,
        "depthCompareFunction",
        desc.depthTestEnabled ? compareFunctionName(desc.depthCompareFunction) : "Always");
    appendKeyValue(key, "stencilEnabled", desc.stencilEnabled);
    if (desc.stencilEnabled) {
        appendKeyString(key, "frontFaceStencil", stencilFaceKey(desc.frontFaceStencil));
        appendKeyString(key, "backFaceStencil", stencilFaceKey(desc.backFaceStencil));
    }
    return key.str();
}

std::string blendAttachmentKey(const MetalBlendAttachmentDesc& desc)
{
    std::ostringstream key;
    appendKeyValue(key, "blendingEnabled", desc.blendingEnabled);
    appendKeyValue(key, "writeMask", writeMaskName(desc.writeMask));
    if (desc.blendingEnabled) {
        appendKeyValue(key, "sourceRGBBlendFactor", blendFactorName(desc.sourceRGBBlendFactor));
        appendKeyValue(key, "destinationRGBBlendFactor", blendFactorName(desc.destinationRGBBlendFactor));
        appendKeyValue(key, "rgbBlendOperation", blendOperationName(desc.rgbBlendOperation));
        appendKeyValue(key, "sourceAlphaBlendFactor", blendFactorName(desc.sourceAlphaBlendFactor));
        appendKeyValue(key, "destinationAlphaBlendFactor", blendFactorName(desc.destinationAlphaBlendFactor));
        appendKeyValue(key, "alphaBlendOperation", blendOperationName(desc.alphaBlendOperation));
    }
    return key.str();
}

std::string makeColorAttachmentKey(const MetalColorAttachmentStateDesc& desc)
{
    std::ostringstream key;
    key << "colorAttachment;";
    appendKeyValue(key, "enabled", desc.enabled);
    appendKeyValue(key, "pixelFormat", desc.enabled ? pixelFormatDescription(desc.pixelFormat) : "None");
    appendKeyString(key, "blend", blendAttachmentKey(desc.blend));
    return key.str();
}

std::string makeRenderAttachmentKey(const MetalRenderAttachmentStateDesc& desc)
{
    std::ostringstream key;
    key << "renderAttachments;";
    appendKeyString(key, "colorAttachment0", makeColorAttachmentKey(desc.colorAttachment0));
    appendKeyValue(key, "depthAttachmentEnabled", desc.depthAttachmentEnabled);
    appendKeyValue(
        key,
        "depthAttachmentFormat",
        desc.depthAttachmentEnabled ? pixelFormatDescription(desc.depthAttachmentFormat) : "None");
    appendKeyValue(key, "rasterSampleCount", desc.rasterSampleCount);
    appendKeyValue(key, "alphaToCoverageEnabled", desc.alphaToCoverageEnabled);
    appendKeyValue(key, "alphaToOneEnabled", desc.alphaToOneEnabled);
    appendKeyValue(key, "rasterizationEnabled", desc.rasterizationEnabled);
    appendKeyString(key, "variant", desc.variantKey);
    return key.str();
}

std::string samplerDescription(const MetalSamplerDesc& desc, const std::string& key, const char* cacheStatus)
{
    std::ostringstream message;
    message << "label='" << (desc.label.empty() ? "Sampler State" : desc.label)
            << "', minFilter=" << samplerFilterName(desc.minFilter)
            << ", magFilter=" << samplerFilterName(desc.magFilter)
            << ", mipFilter=" << samplerFilterName(desc.mipFilter)
            << ", addressU=" << addressModeName(desc.addressU)
            << ", addressV=" << addressModeName(desc.addressV)
            << ", addressW=" << addressModeName(desc.addressW)
            << ", maxAnisotropy=" << std::max<uint32_t>(desc.maxAnisotropy, 1)
            << ", normalizedCoordinates=" << boolName(desc.normalizedCoordinates);
    if (cacheStatus != nullptr) {
        message << ", cacheStatus=" << cacheStatus;
    }
    message << ", cacheKey='" << key << "'";
    return message.str();
}

std::string depthStencilDescription(const MetalDepthStencilDesc& desc, const std::string& key, const char* cacheStatus)
{
    std::ostringstream message;
    message << "label='" << (desc.label.empty() ? "Depth Stencil State" : desc.label)
            << "', depthTestEnabled=" << boolName(desc.depthTestEnabled)
            << ", depthWriteEnabled=" << boolName(desc.depthTestEnabled && desc.depthWriteEnabled)
            << ", depthCompareFunction="
            << (desc.depthTestEnabled ? compareFunctionName(desc.depthCompareFunction) : "Always")
            << ", stencilEnabled=" << boolName(desc.stencilEnabled);
    if (desc.stencilEnabled) {
        message << ", frontFaceStencil='" << stencilFaceKey(desc.frontFaceStencil)
                << "', backFaceStencil='" << stencilFaceKey(desc.backFaceStencil) << "'";
    }
    if (cacheStatus != nullptr) {
        message << ", cacheStatus=" << cacheStatus;
    }
    message << ", cacheKey='" << key << "'";
    return message.str();
}

void configureStencilDescriptor(MTLStencilDescriptor* stencilDescriptor, const MetalStencilFaceDesc& desc)
{
    stencilDescriptor.stencilCompareFunction = toCompareFunction(desc.compareFunction);
    stencilDescriptor.stencilFailureOperation = toStencilOperation(desc.stencilFailureOperation);
    stencilDescriptor.depthFailureOperation = toStencilOperation(desc.depthFailureOperation);
    stencilDescriptor.depthStencilPassOperation = toStencilOperation(desc.depthStencilPassOperation);
    stencilDescriptor.readMask = desc.readMask;
    stencilDescriptor.writeMask = desc.writeMask;
}

} // namespace

struct MetalRenderStateCache::Impl {
    id<MTLDevice> device = nil;
    std::unordered_map<std::string, id<MTLSamplerState>> samplerStates;
    std::unordered_map<std::string, id<MTLDepthStencilState>> depthStencilStates;
    MetalRenderStateCacheDiagnostics diagnostics;
    std::string lastDiagnostic;

    void recordEvent(std::string message, std::string* output = nullptr)
    {
        diagnostics.lastEvent = message;
        lastDiagnostic = std::move(message);
        setDiagnostic(output, lastDiagnostic);
    }
};

MetalRenderStateCache::MetalRenderStateCache(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)deviceContext.nativeDevice();
}

MetalRenderStateCache::~MetalRenderStateCache() = default;

MetalRenderStateCache::MetalRenderStateCache(MetalRenderStateCache&&) noexcept = default;

MetalRenderStateCache& MetalRenderStateCache::operator=(MetalRenderStateCache&&) noexcept = default;

void* MetalRenderStateCache::samplerState(const MetalSamplerDesc& desc, std::string* diagnostic)
{
    if (m_impl->device == nil) {
        m_impl->recordEvent("Metal sampler state cache unavailable: device is nil.", diagnostic);
        return nullptr;
    }

    const std::string key = samplerKey(desc);
    auto existing = m_impl->samplerStates.find(key);
    if (existing != m_impl->samplerStates.end()) {
        ++m_impl->diagnostics.samplerHits;
        m_impl->recordEvent(samplerDescription(desc, key, "hit"), diagnostic);
        return (__bridge void*)existing->second;
    }

    ++m_impl->diagnostics.samplerMisses;
    MTLSamplerDescriptor* samplerDescriptor = [[MTLSamplerDescriptor alloc] init];
    samplerDescriptor.minFilter = toMinMagFilter(desc.minFilter);
    samplerDescriptor.magFilter = toMinMagFilter(desc.magFilter);
    samplerDescriptor.mipFilter = toMipFilter(desc.mipFilter);
    samplerDescriptor.sAddressMode = toAddressMode(desc.addressU);
    samplerDescriptor.tAddressMode = toAddressMode(desc.addressV);
    samplerDescriptor.rAddressMode = toAddressMode(desc.addressW);
    samplerDescriptor.maxAnisotropy = std::max<uint32_t>(desc.maxAnisotropy, 1);
    samplerDescriptor.normalizedCoordinates = desc.normalizedCoordinates ? YES : NO;
    samplerDescriptor.label = toNSString(desc.label.empty() ? "Mesh2Splat Sampler State" : desc.label);

    id<MTLSamplerState> state = [m_impl->device newSamplerStateWithDescriptor:samplerDescriptor];
    if (state == nil) {
        m_impl->recordEvent("Failed to create Metal sampler state: " + samplerDescription(desc, key, "miss"), diagnostic);
        return nullptr;
    }

    m_impl->samplerStates.insert_or_assign(key, state);
    m_impl->recordEvent(samplerDescription(desc, key, "miss"), diagnostic);
    return (__bridge void*)state;
}

void* MetalRenderStateCache::depthStencilState(const MetalDepthStencilDesc& desc, std::string* diagnostic)
{
    if (m_impl->device == nil) {
        m_impl->recordEvent("Metal depth stencil state cache unavailable: device is nil.", diagnostic);
        return nullptr;
    }

    const std::string key = depthStencilKey(desc);
    auto existing = m_impl->depthStencilStates.find(key);
    if (existing != m_impl->depthStencilStates.end()) {
        ++m_impl->diagnostics.depthStencilHits;
        m_impl->recordEvent(depthStencilDescription(desc, key, "hit"), diagnostic);
        return (__bridge void*)existing->second;
    }

    ++m_impl->diagnostics.depthStencilMisses;
    MTLDepthStencilDescriptor* depthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
    depthDescriptor.depthWriteEnabled = desc.depthTestEnabled && desc.depthWriteEnabled;
    depthDescriptor.depthCompareFunction =
        desc.depthTestEnabled ? toCompareFunction(desc.depthCompareFunction) : MTLCompareFunctionAlways;
    depthDescriptor.label = toNSString(desc.label.empty() ? "Mesh2Splat Depth Stencil State" : desc.label);
    if (desc.stencilEnabled) {
        MTLStencilDescriptor* frontFaceStencil = [[MTLStencilDescriptor alloc] init];
        MTLStencilDescriptor* backFaceStencil = [[MTLStencilDescriptor alloc] init];
        configureStencilDescriptor(frontFaceStencil, desc.frontFaceStencil);
        configureStencilDescriptor(backFaceStencil, desc.backFaceStencil);
        depthDescriptor.frontFaceStencil = frontFaceStencil;
        depthDescriptor.backFaceStencil = backFaceStencil;
    }

    id<MTLDepthStencilState> state = [m_impl->device newDepthStencilStateWithDescriptor:depthDescriptor];
    if (state == nil) {
        m_impl->recordEvent(
            "Failed to create Metal depth stencil state: " + depthStencilDescription(desc, key, "miss"),
            diagnostic);
        return nullptr;
    }

    m_impl->depthStencilStates.insert_or_assign(key, state);
    m_impl->recordEvent(depthStencilDescription(desc, key, "miss"), diagnostic);
    return (__bridge void*)state;
}

std::string MetalRenderStateCache::colorAttachmentKey(const MetalColorAttachmentStateDesc& desc)
{
    ++m_impl->diagnostics.attachmentKeyRequests;
    const std::string key = makeColorAttachmentKey(desc);
    m_impl->recordEvent("Metal color attachment state key requested: " + colorAttachmentDescription(desc) +
        ", cacheKey='" + key + "'");
    return key;
}

std::string MetalRenderStateCache::renderAttachmentKey(const MetalRenderAttachmentStateDesc& desc)
{
    ++m_impl->diagnostics.attachmentKeyRequests;
    const std::string key = makeRenderAttachmentKey(desc);
    m_impl->recordEvent("Metal render attachment state key requested: " + renderAttachmentDescription(desc) +
        ", cacheKey='" + key + "'");
    return key;
}

std::string MetalRenderStateCache::colorAttachmentDescription(const MetalColorAttachmentStateDesc& desc) const
{
    std::ostringstream message;
    message << "label='" << (desc.label.empty() ? "Color Attachment 0" : desc.label)
            << "', enabled=" << boolName(desc.enabled)
            << ", pixelFormat=" << (desc.enabled ? pixelFormatDescription(desc.pixelFormat) : "None")
            << ", blendingEnabled=" << boolName(desc.blend.blendingEnabled)
            << ", writeMask=" << writeMaskName(desc.blend.writeMask);
    if (desc.blend.blendingEnabled) {
        message << ", sourceRGBBlendFactor=" << blendFactorName(desc.blend.sourceRGBBlendFactor)
                << ", destinationRGBBlendFactor=" << blendFactorName(desc.blend.destinationRGBBlendFactor)
                << ", rgbBlendOperation=" << blendOperationName(desc.blend.rgbBlendOperation)
                << ", sourceAlphaBlendFactor=" << blendFactorName(desc.blend.sourceAlphaBlendFactor)
                << ", destinationAlphaBlendFactor=" << blendFactorName(desc.blend.destinationAlphaBlendFactor)
                << ", alphaBlendOperation=" << blendOperationName(desc.blend.alphaBlendOperation);
    }
    return message.str();
}

std::string MetalRenderStateCache::renderAttachmentDescription(const MetalRenderAttachmentStateDesc& desc) const
{
    std::ostringstream message;
    message << "label='" << (desc.label.empty() ? "Render Attachment State" : desc.label)
            << "', colorAttachment0={" << colorAttachmentDescription(desc.colorAttachment0) << "}"
            << ", depthAttachmentEnabled=" << boolName(desc.depthAttachmentEnabled)
            << ", depthAttachmentFormat="
            << (desc.depthAttachmentEnabled ? pixelFormatDescription(desc.depthAttachmentFormat) : "None")
            << ", rasterSampleCount=" << desc.rasterSampleCount
            << ", alphaToCoverageEnabled=" << boolName(desc.alphaToCoverageEnabled)
            << ", alphaToOneEnabled=" << boolName(desc.alphaToOneEnabled)
            << ", rasterizationEnabled=" << boolName(desc.rasterizationEnabled);
    if (!desc.variantKey.empty()) {
        message << ", variant='" << desc.variantKey << "'";
    }
    return message.str();
}

bool MetalRenderStateCache::applyColorAttachmentState(
    void* colorAttachmentDescriptor,
    const MetalColorAttachmentStateDesc& desc,
    std::string* errorMessage) const
{
    MTLRenderPipelineColorAttachmentDescriptor* attachment =
        (__bridge MTLRenderPipelineColorAttachmentDescriptor*)colorAttachmentDescriptor;
    if (attachment == nil) {
        setDiagnostic(errorMessage, "Cannot apply Metal color attachment state: descriptor is nil.");
        return false;
    }

    if (!desc.enabled) {
        attachment.pixelFormat = MTLPixelFormatInvalid;
        attachment.blendingEnabled = NO;
        attachment.writeMask = MTLColorWriteMaskNone;
        setDiagnostic(errorMessage, std::string{});
        return true;
    }

    if (!isColorFormat(desc.pixelFormat)) {
        setDiagnostic(
            errorMessage,
            "Cannot apply Metal color attachment state: pixel format is not a color format: " +
                pixelFormatDescription(desc.pixelFormat) + ".");
        return false;
    }

    attachment.pixelFormat = toPixelFormat(desc.pixelFormat);
    attachment.writeMask = toColorWriteMask(desc.blend.writeMask);
    attachment.blendingEnabled = desc.blend.blendingEnabled ? YES : NO;
    attachment.sourceRGBBlendFactor = toBlendFactor(desc.blend.sourceRGBBlendFactor);
    attachment.destinationRGBBlendFactor = toBlendFactor(desc.blend.destinationRGBBlendFactor);
    attachment.rgbBlendOperation = toBlendOperation(desc.blend.rgbBlendOperation);
    attachment.sourceAlphaBlendFactor = toBlendFactor(desc.blend.sourceAlphaBlendFactor);
    attachment.destinationAlphaBlendFactor = toBlendFactor(desc.blend.destinationAlphaBlendFactor);
    attachment.alphaBlendOperation = toBlendOperation(desc.blend.alphaBlendOperation);
    setDiagnostic(errorMessage, std::string{});
    return true;
}

void MetalRenderStateCache::clear()
{
    const std::size_t samplerCount = m_impl->samplerStates.size();
    const std::size_t depthStencilCount = m_impl->depthStencilStates.size();
    m_impl->samplerStates.clear();
    m_impl->depthStencilStates.clear();
    m_impl->recordEvent(
        "Metal render state cache cleared: samplerStates=" + std::to_string(samplerCount) +
        ", depthStencilStates=" + std::to_string(depthStencilCount) + ".");
}

void MetalRenderStateCache::reset()
{
    clear();
    resetDiagnostics();
}

void MetalRenderStateCache::resetDiagnostics()
{
    m_impl->diagnostics = MetalRenderStateCacheDiagnostics{};
    m_impl->lastDiagnostic.clear();
}

std::size_t MetalRenderStateCache::samplerStateCount() const
{
    return m_impl->samplerStates.size();
}

std::size_t MetalRenderStateCache::depthStencilStateCount() const
{
    return m_impl->depthStencilStates.size();
}

MetalRenderStateCacheDiagnostics MetalRenderStateCache::diagnostics() const
{
    MetalRenderStateCacheDiagnostics diagnostics = m_impl->diagnostics;
    diagnostics.samplerStateCount = m_impl->samplerStates.size();
    diagnostics.depthStencilStateCount = m_impl->depthStencilStates.size();
    diagnostics.lastEvent = m_impl->lastDiagnostic;
    return diagnostics;
}

const std::string& MetalRenderStateCache::lastDiagnostic() const
{
    return m_impl->lastDiagnostic;
}

} // namespace mesh2splat::metal
