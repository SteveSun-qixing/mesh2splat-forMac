#include "MetalPipelineCache.hpp"

#include "MetalDeviceContext.hpp"
#include "MetalShaderLibrary.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <sstream>
#include <unordered_map>

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

std::string renderKey(const MetalRenderPipelineDesc& desc)
{
    std::ostringstream key;
    key << desc.vertexFunction << '|'
        << desc.fragmentFunction << '|'
        << static_cast<int>(desc.colorFormat) << '|'
        << static_cast<int>(desc.depthFormat) << '|'
        << desc.depthEnabled << '|'
        << static_cast<int>(desc.blendMode);
    return key.str();
}

std::string computeKey(const MetalComputePipelineDesc& desc)
{
    return desc.function;
}

NSString* toNSString(const std::string& value)
{
    return [NSString stringWithUTF8String:value.c_str()];
}

std::string nsStringValue(NSString* value)
{
    return value == nil ? std::string{} : std::string(value.UTF8String);
}

std::string errorDescription(NSError* error)
{
    return error == nil ? std::string{} : nsStringValue(error.localizedDescription);
}

void setErrorMessage(const std::string& error, std::string* errorMessage)
{
    if (errorMessage == nullptr) {
        return;
    }

    *errorMessage = error;
}

} // namespace

struct MetalPipelineCache::Impl {
    id<MTLDevice> device = nil;
    std::unordered_map<std::string, id<MTLRenderPipelineState>> renderPipelines;
    std::unordered_map<std::string, id<MTLComputePipelineState>> computePipelines;
};

MetalPipelineCache::MetalPipelineCache(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)deviceContext.nativeDevice();
}

MetalPipelineCache::~MetalPipelineCache() = default;

void* MetalPipelineCache::renderPipeline(
    MetalShaderLibrary& library,
    const MetalRenderPipelineDesc& desc,
    std::string* errorMessage)
{
    if (m_impl->device == nil || !library.isValid() || desc.vertexFunction.empty()) {
        if (errorMessage != nullptr) {
            if (m_impl->device == nil) {
                *errorMessage = "Metal device is unavailable.";
            } else if (!library.isValid()) {
                *errorMessage = "Metal shader library is invalid.";
            } else {
                *errorMessage = "Metal render pipeline vertex function is empty.";
            }
        }
        return nullptr;
    }

    const std::string key = renderKey(desc);
    auto cached = m_impl->renderPipelines.find(key);
    if (cached != m_impl->renderPipelines.end()) {
        setErrorMessage(std::string{}, errorMessage);
        return (__bridge void*)cached->second;
    }

    id<MTLLibrary> nativeLibrary = (__bridge id<MTLLibrary>)library.nativeLibrary();
    id<MTLFunction> vertexFunction = [nativeLibrary newFunctionWithName:toNSString(desc.vertexFunction)];
    if (vertexFunction == nil) {
        if (errorMessage != nullptr) {
            *errorMessage = "Missing Metal vertex function '" + desc.vertexFunction +
                "' for render pipeline '" + desc.label + "'.";
        }
        return nullptr;
    }

    id<MTLFunction> fragmentFunction = nil;
    if (!desc.fragmentFunction.empty()) {
        fragmentFunction = [nativeLibrary newFunctionWithName:toNSString(desc.fragmentFunction)];
        if (fragmentFunction == nil) {
            if (errorMessage != nullptr) {
                *errorMessage = "Missing Metal fragment function '" + desc.fragmentFunction +
                    "' for render pipeline '" + desc.label + "'.";
            }
            return nullptr;
        }
    }

    MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;
    pipelineDescriptor.colorAttachments[0].pixelFormat = toPixelFormat(desc.colorFormat);
    if (!desc.label.empty()) {
        pipelineDescriptor.label = toNSString(desc.label);
    }

    if (desc.depthEnabled) {
        pipelineDescriptor.depthAttachmentPixelFormat = toPixelFormat(desc.depthFormat);
    }

    if (desc.blendMode != MetalBlendMode::Disabled) {
        MTLRenderPipelineColorAttachmentDescriptor* colorAttachment = pipelineDescriptor.colorAttachments[0];
        colorAttachment.blendingEnabled = YES;
        colorAttachment.sourceRGBBlendFactor =
            desc.blendMode == MetalBlendMode::PremultipliedAlpha ? MTLBlendFactorOne : MTLBlendFactorSourceAlpha;
        colorAttachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        colorAttachment.rgbBlendOperation = MTLBlendOperationAdd;
        colorAttachment.sourceAlphaBlendFactor = MTLBlendFactorOne;
        colorAttachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        colorAttachment.alphaBlendOperation = MTLBlendOperationAdd;
    }

    NSError* error = nil;
    id<MTLRenderPipelineState> pipelineState =
        [m_impl->device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    if (pipelineState == nil) {
        std::string message = "Failed to create Metal render pipeline '" + desc.label +
            "' (vertex='" + desc.vertexFunction + "', fragment='" + desc.fragmentFunction + "')";
        const std::string errorText = errorDescription(error);
        if (!errorText.empty()) {
            message += ": " + errorText;
        }
        setErrorMessage(message, errorMessage);
        return nullptr;
    }

    setErrorMessage(std::string{}, errorMessage);
    m_impl->renderPipelines.emplace(key, pipelineState);
    return (__bridge void*)pipelineState;
}

void* MetalPipelineCache::computePipeline(
    MetalShaderLibrary& library,
    const MetalComputePipelineDesc& desc,
    std::string* errorMessage)
{
    if (m_impl->device == nil || !library.isValid() || desc.function.empty()) {
        if (errorMessage != nullptr) {
            if (m_impl->device == nil) {
                *errorMessage = "Metal device is unavailable.";
            } else if (!library.isValid()) {
                *errorMessage = "Metal shader library is invalid.";
            } else {
                *errorMessage = "Metal compute pipeline function is empty.";
            }
        }
        return nullptr;
    }

    const std::string key = computeKey(desc);
    auto cached = m_impl->computePipelines.find(key);
    if (cached != m_impl->computePipelines.end()) {
        setErrorMessage(std::string{}, errorMessage);
        return (__bridge void*)cached->second;
    }

    id<MTLLibrary> nativeLibrary = (__bridge id<MTLLibrary>)library.nativeLibrary();
    id<MTLFunction> function = [nativeLibrary newFunctionWithName:toNSString(desc.function)];
    if (function == nil) {
        if (errorMessage != nullptr) {
            *errorMessage = "Missing Metal compute function '" + desc.function +
                "' for compute pipeline '" + desc.label + "'.";
        }
        return nullptr;
    }

    NSError* error = nil;
    id<MTLComputePipelineState> pipelineState =
        [m_impl->device newComputePipelineStateWithFunction:function error:&error];
    if (pipelineState == nil) {
        std::string message = "Failed to create Metal compute pipeline '" + desc.label +
            "' (function='" + desc.function + "')";
        const std::string errorText = errorDescription(error);
        if (!errorText.empty()) {
            message += ": " + errorText;
        }
        setErrorMessage(message, errorMessage);
        return nullptr;
    }

    setErrorMessage(std::string{}, errorMessage);
    m_impl->computePipelines.emplace(key, pipelineState);
    return (__bridge void*)pipelineState;
}

void MetalPipelineCache::clear()
{
    m_impl->renderPipelines.clear();
    m_impl->computePipelines.clear();
}

} // namespace mesh2splat::metal
