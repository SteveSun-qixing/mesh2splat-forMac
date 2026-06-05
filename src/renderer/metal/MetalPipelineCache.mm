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
        << desc.blendingEnabled;
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

void setErrorMessage(NSError* error, std::string* errorMessage)
{
    if (errorMessage == nullptr) {
        return;
    }

    if (error == nil) {
        errorMessage->clear();
        return;
    }

    *errorMessage = error.localizedDescription.UTF8String;
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
        return nullptr;
    }

    const std::string key = renderKey(desc);
    auto cached = m_impl->renderPipelines.find(key);
    if (cached != m_impl->renderPipelines.end()) {
        return (__bridge void*)cached->second;
    }

    id<MTLLibrary> nativeLibrary = (__bridge id<MTLLibrary>)library.nativeLibrary();
    id<MTLFunction> vertexFunction = [nativeLibrary newFunctionWithName:toNSString(desc.vertexFunction)];
    if (vertexFunction == nil) {
        if (errorMessage != nullptr) {
            *errorMessage = "Missing Metal vertex function: " + desc.vertexFunction;
        }
        return nullptr;
    }

    id<MTLFunction> fragmentFunction = nil;
    if (!desc.fragmentFunction.empty()) {
        fragmentFunction = [nativeLibrary newFunctionWithName:toNSString(desc.fragmentFunction)];
        if (fragmentFunction == nil) {
            if (errorMessage != nullptr) {
                *errorMessage = "Missing Metal fragment function: " + desc.fragmentFunction;
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

    if (desc.blendingEnabled) {
        MTLRenderPipelineColorAttachmentDescriptor* colorAttachment = pipelineDescriptor.colorAttachments[0];
        colorAttachment.blendingEnabled = YES;
        colorAttachment.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        colorAttachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        colorAttachment.rgbBlendOperation = MTLBlendOperationAdd;
        colorAttachment.sourceAlphaBlendFactor = MTLBlendFactorOne;
        colorAttachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        colorAttachment.alphaBlendOperation = MTLBlendOperationAdd;
    }

    NSError* error = nil;
    id<MTLRenderPipelineState> pipelineState =
        [m_impl->device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    setErrorMessage(error, errorMessage);
    if (pipelineState == nil) {
        return nullptr;
    }

    m_impl->renderPipelines.emplace(key, pipelineState);
    return (__bridge void*)pipelineState;
}

void* MetalPipelineCache::computePipeline(
    MetalShaderLibrary& library,
    const MetalComputePipelineDesc& desc,
    std::string* errorMessage)
{
    if (m_impl->device == nil || !library.isValid() || desc.function.empty()) {
        return nullptr;
    }

    const std::string key = computeKey(desc);
    auto cached = m_impl->computePipelines.find(key);
    if (cached != m_impl->computePipelines.end()) {
        return (__bridge void*)cached->second;
    }

    id<MTLLibrary> nativeLibrary = (__bridge id<MTLLibrary>)library.nativeLibrary();
    id<MTLFunction> function = [nativeLibrary newFunctionWithName:toNSString(desc.function)];
    if (function == nil) {
        if (errorMessage != nullptr) {
            *errorMessage = "Missing Metal compute function: " + desc.function;
        }
        return nullptr;
    }

    NSError* error = nil;
    id<MTLComputePipelineState> pipelineState =
        [m_impl->device newComputePipelineStateWithFunction:function error:&error];
    setErrorMessage(error, errorMessage);
    if (pipelineState == nil) {
        return nullptr;
    }

    m_impl->computePipelines.emplace(key, pipelineState);
    return (__bridge void*)pipelineState;
}

void MetalPipelineCache::clear()
{
    m_impl->renderPipelines.clear();
    m_impl->computePipelines.clear();
}

} // namespace mesh2splat::metal
