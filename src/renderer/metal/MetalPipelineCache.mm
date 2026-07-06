#include "MetalPipelineCache.hpp"

#include "MetalDeviceContext.hpp"
#include "MetalShaderLibrary.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <cstdint>
#include <iterator>
#include <sstream>
#include <unordered_map>
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
    const MTLPixelFormat metalFormat = toPixelFormat(format);
    std::ostringstream description;
    description << textureFormatName(format) << "(MTL=" << static_cast<unsigned long>(metalFormat) << ")";
    return description.str();
}

bool isDepthFormat(MetalTextureFormat format)
{
    return format == MetalTextureFormat::Depth32Float;
}

std::string blendModeName(MetalBlendMode blendMode)
{
    switch (blendMode) {
    case MetalBlendMode::Disabled:
        return "Disabled";
    case MetalBlendMode::Alpha:
        return "Alpha";
    case MetalBlendMode::PremultipliedAlpha:
        return "PremultipliedAlpha";
    case MetalBlendMode::Additive:
        return "Additive";
    }

    return "Unknown(" + std::to_string(static_cast<int>(blendMode)) + ")";
}

std::string renderDepthAttachmentName(const MetalRenderPipelineDesc& desc)
{
    return desc.depthEnabled ? pixelFormatDescription(desc.depthFormat) : "None";
}

std::string boolName(bool value)
{
    return value ? "true" : "false";
}

std::string pointerName(const void* value)
{
    std::ostringstream stream;
    stream << "0x" << std::hex << reinterpret_cast<std::uintptr_t>(value);
    return stream.str();
}

void appendKeyString(std::ostringstream& key, const char* name, const std::string& value)
{
    key << name << '[' << value.size() << "]=" << value << ';';
}

void appendKeyValue(std::ostringstream& key, const char* name, const std::string& value)
{
    key << name << '=' << value << ';';
}

void appendKeyValue(std::ostringstream& key, const char* name, const char* value)
{
    key << name << '=' << (value == nullptr ? "" : value) << ';';
}

void appendKeyValue(std::ostringstream& key, const char* name, uint32_t value)
{
    key << name << '=' << value << ';';
}

void appendKeyValue(std::ostringstream& key, const char* name, bool value)
{
    appendKeyValue(key, name, boolName(value));
}

bool isColorFormat(MetalTextureFormat format)
{
    return toPixelFormat(format) != MTLPixelFormatInvalid && !isDepthFormat(format);
}

std::string targetVariantKey(
    MetalTextureFormat colorFormat,
    MetalTextureFormat depthFormat,
    bool depthEnabled,
    uint32_t rasterSampleCount)
{
    std::ostringstream key;
    appendKeyValue(key, "color", textureFormatName(colorFormat));
    appendKeyValue(key, "depthEnabled", depthEnabled);
    appendKeyValue(key, "depth", depthEnabled ? textureFormatName(depthFormat) : "None");
    appendKeyValue(key, "samples", rasterSampleCount);
    return key.str();
}

std::string renderPipelineLabel(const MetalRenderPipelineDesc& desc)
{
    if (!desc.label.empty()) {
        return desc.label;
    }

    std::string label = "Render Pipeline " + desc.vertexFunction;
    if (!desc.fragmentFunction.empty()) {
        label += "/" + desc.fragmentFunction;
    }
    if (!desc.variantKey.empty()) {
        label += " [" + desc.variantKey + "]";
    }
    return label;
}

std::string computePipelineLabel(const MetalComputePipelineDesc& desc)
{
    if (!desc.label.empty()) {
        return desc.label;
    }

    std::string label = "Compute Pipeline " + desc.function;
    if (!desc.variantKey.empty()) {
        label += " [" + desc.variantKey + "]";
    }
    return label;
}

std::string renderKey(const MetalRenderPipelineDesc& desc, const void* libraryIdentity)
{
    std::ostringstream key;
    key << "render;";
    appendKeyValue(key, "library", pointerName(libraryIdentity));
    appendKeyString(key, "vertex", desc.vertexFunction);
    appendKeyString(key, "fragment", desc.fragmentFunction);
    appendKeyValue(key, "colorAttachment0Format", pixelFormatDescription(desc.colorFormat));
    appendKeyValue(key, "depthAttachmentEnabled", desc.depthEnabled);
    appendKeyValue(key, "depthAttachmentFormat", renderDepthAttachmentName(desc));
    appendKeyValue(key, "stencilAttachmentFormat", "None");
    appendKeyValue(key, "rasterSampleCount", desc.rasterSampleCount);
    appendKeyValue(key, "blendMode", blendModeName(desc.blendMode));
    appendKeyValue(key, "alphaToCoverageEnabled", false);
    appendKeyValue(key, "alphaToOneEnabled", false);
    appendKeyValue(key, "rasterizationEnabled", true);
    appendKeyString(key, "variant", desc.variantKey);
    return key.str();
}

std::string computeKey(const MetalComputePipelineDesc& desc, const void* libraryIdentity)
{
    std::ostringstream key;
    key << "compute;";
    appendKeyValue(key, "library", pointerName(libraryIdentity));
    appendKeyString(key, "function", desc.function);
    appendKeyString(key, "variant", desc.variantKey);
    appendKeyValue(key, "maxTotalThreadsPerThreadgroup", desc.maxTotalThreadsPerThreadgroup);
    appendKeyValue(
        key,
        "threadGroupSizeIsMultipleOfThreadExecutionWidth",
        desc.threadGroupSizeIsMultipleOfThreadExecutionWidth);
    appendKeyValue(key, "supportIndirectCommandBuffers", desc.supportIndirectCommandBuffers);
    return key.str();
}

std::string libraryDescription(const MetalShaderLibrary& library, const void* nativeLibrary)
{
    const std::string& sourceDescription = library.sourceDescription();
    if (!sourceDescription.empty()) {
        return sourceDescription + "@" + pointerName(nativeLibrary);
    }
    return pointerName(nativeLibrary);
}

std::string renderPipelineDiagnostics(
    const MetalShaderLibrary& library,
    const MetalRenderPipelineDesc& desc,
    const std::string& key,
    const void* nativeLibrary,
    const char* cacheStatus)
{
    std::ostringstream message;
    message << "label='" << renderPipelineLabel(desc)
            << "', library='" << libraryDescription(library, nativeLibrary)
            << "', vertex='" << desc.vertexFunction
            << "', fragment='" << desc.fragmentFunction
            << "', colorAttachment0Format=" << pixelFormatDescription(desc.colorFormat)
            << ", depthEnabled=" << boolName(desc.depthEnabled)
            << ", requestedDepthFormat=" << pixelFormatDescription(desc.depthFormat)
            << ", depthAttachmentFormat=" << renderDepthAttachmentName(desc)
            << ", stencilAttachmentFormat=None"
            << ", rasterSampleCount=" << desc.rasterSampleCount
            << ", blendMode=" << blendModeName(desc.blendMode)
            << ", alphaToCoverageEnabled=false"
            << ", alphaToOneEnabled=false"
            << ", rasterizationEnabled=true";
    if (cacheStatus != nullptr) {
        message << ", cacheStatus=" << cacheStatus;
    }
    if (!desc.variantKey.empty()) {
        message << ", variant='" << desc.variantKey << "'";
    }
    message << ", cacheKey='" << key << "'";
    return message.str();
}

std::string computePipelineDiagnostics(
    const MetalShaderLibrary& library,
    const MetalComputePipelineDesc& desc,
    const std::string& key,
    const void* nativeLibrary,
    const char* cacheStatus)
{
    std::ostringstream message;
    message << "label='" << computePipelineLabel(desc)
            << "', library='" << libraryDescription(library, nativeLibrary)
            << "', function='" << desc.function
            << "', maxTotalThreadsPerThreadgroup=" << desc.maxTotalThreadsPerThreadgroup
            << ", threadGroupSizeIsMultipleOfThreadExecutionWidth="
            << boolName(desc.threadGroupSizeIsMultipleOfThreadExecutionWidth)
            << ", supportIndirectCommandBuffers=" << boolName(desc.supportIndirectCommandBuffers);
    if (cacheStatus != nullptr) {
        message << ", cacheStatus=" << cacheStatus;
    }
    if (!desc.variantKey.empty()) {
        message << ", variant='" << desc.variantKey << "'";
    }
    message << ", cacheKey='" << key << "'";
    return message.str();
}

NSString* toNSString(const std::string& value)
{
    return [NSString stringWithUTF8String:value.c_str()];
}

std::string nsStringValue(NSString* value)
{
    if (value == nil || value.UTF8String == nullptr) {
        return std::string{};
    }
    return std::string(value.UTF8String);
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

std::string renderValidationError(id<MTLDevice> device, const MetalRenderPipelineDesc& desc)
{
    if (!isColorFormat(desc.colorFormat)) {
        return "Metal render pipeline color attachment 0 format must be a color pixel format: " +
            pixelFormatDescription(desc.colorFormat) + ".";
    }

    if (desc.rasterSampleCount == 0) {
        return "Metal render pipeline raster sample count must be greater than zero.";
    }

    if (device != nil && ![device supportsTextureSampleCount:desc.rasterSampleCount]) {
        return "Metal device does not support render pipeline raster sample count " +
            std::to_string(desc.rasterSampleCount) + ".";
    }

    if (desc.depthEnabled && !isDepthFormat(desc.depthFormat)) {
        return "Metal render pipeline depth attachment format must be a depth pixel format when depth is enabled: " +
            pixelFormatDescription(desc.depthFormat) + ".";
    }

    return std::string{};
}

std::string missingRenderFunctionMessage(
    const MetalShaderLibrary& library,
    const MetalRenderPipelineDesc& desc,
    const std::string& functionName,
    const std::string& functionRole,
    const std::string& key,
    const void* nativeLibrary)
{
    return library.missingFunctionDiagnostic(functionName, functionRole, renderPipelineLabel(desc)) + " " +
        renderPipelineDiagnostics(library, desc, key, nativeLibrary, "miss");
}

std::string missingComputeFunctionMessage(
    const MetalShaderLibrary& library,
    const MetalComputePipelineDesc& desc,
    const std::string& key,
    const void* nativeLibrary)
{
    return library.missingFunctionDiagnostic(desc.function, "compute", computePipelineLabel(desc)) + " " +
        computePipelineDiagnostics(library, desc, key, nativeLibrary, "miss");
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

MetalRenderPipelineDesc MetalPipelineCache::meshPipelineDesc(
    MetalTextureFormat colorFormat,
    MetalTextureFormat depthFormat,
    uint32_t rasterSampleCount)
{
    MetalRenderPipelineDesc desc;
    desc.label = "Mesh Preview Pipeline";
    desc.vertexFunction = "meshVertex";
    desc.fragmentFunction = "meshFragment";
    desc.colorFormat = colorFormat;
    desc.depthFormat = depthFormat;
    desc.depthEnabled = true;
    desc.blendMode = MetalBlendMode::Disabled;
    desc.variantKey = targetVariantKey(colorFormat, depthFormat, desc.depthEnabled, rasterSampleCount);
    desc.rasterSampleCount = rasterSampleCount;
    return desc;
}

MetalRenderPipelineDesc MetalPipelineCache::gaussianPipelineDesc(
    MetalTextureFormat colorFormat,
    MetalTextureFormat depthFormat,
    uint32_t rasterSampleCount)
{
    MetalRenderPipelineDesc desc;
    desc.label = "Gaussian Preview Pipeline";
    desc.vertexFunction = "gaussianPreviewVertex";
    desc.fragmentFunction = "gaussianPreviewFragment";
    desc.colorFormat = colorFormat;
    desc.depthFormat = depthFormat;
    desc.depthEnabled = true;
    desc.blendMode = MetalBlendMode::PremultipliedAlpha;
    desc.variantKey = targetVariantKey(colorFormat, depthFormat, desc.depthEnabled, rasterSampleCount);
    desc.rasterSampleCount = rasterSampleCount;
    return desc;
}

MetalComputePipelineDesc MetalPipelineCache::conversionPipelineDesc()
{
    MetalComputePipelineDesc desc;
    desc.label = "Mesh Vertex Conversion Pipeline";
    desc.function = "meshVertexConversionKernel";
    desc.variantKey = "conversion:meshVertex";
    return desc;
}

std::vector<MetalComputePipelineDesc> MetalPipelineCache::sortPipelineDescs()
{
    MetalComputePipelineDesc depthKeyDesc;
    depthKeyDesc.label = "Gaussian Depth Key Pipeline";
    depthKeyDesc.function = "gaussianDepthKeyKernel";
    depthKeyDesc.variantKey = "sort:depthKey";

    MetalComputePipelineDesc countDesc;
    countDesc.label = "Gaussian Radix Count Pipeline";
    countDesc.function = "gaussianRadixCountKernel";
    countDesc.variantKey = "sort:radixCount";

    MetalComputePipelineDesc prefixDesc;
    prefixDesc.label = "Gaussian Radix Prefix Pipeline";
    prefixDesc.function = "gaussianRadixPrefixKernel";
    prefixDesc.variantKey = "sort:radixPrefix";

    MetalComputePipelineDesc reorderDesc;
    reorderDesc.label = "Gaussian Radix Reorder Pipeline";
    reorderDesc.function = "gaussianRadixReorderKernel";
    reorderDesc.variantKey = "sort:radixReorder";

    return { std::move(depthKeyDesc), std::move(countDesc), std::move(prefixDesc), std::move(reorderDesc) };
}

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

    id<MTLLibrary> nativeLibrary = (__bridge id<MTLLibrary>)library.nativeLibrary();
    const std::string key = renderKey(desc, (__bridge const void*)nativeLibrary);
    auto cached = m_impl->renderPipelines.find(key);
    if (cached != m_impl->renderPipelines.end()) {
        setErrorMessage(std::string{}, errorMessage);
        return (__bridge void*)cached->second;
    }

    const std::string validationError = renderValidationError(m_impl->device, desc);
    if (!validationError.empty()) {
        setErrorMessage(
            validationError + " " +
                renderPipelineDiagnostics(library, desc, key, (__bridge const void*)nativeLibrary, "miss"),
            errorMessage);
        return nullptr;
    }

    id<MTLFunction> vertexFunction = (__bridge id<MTLFunction>)library.nativeFunction(desc.vertexFunction);
    if (vertexFunction == nil) {
        setErrorMessage(
            missingRenderFunctionMessage(
                library,
                desc,
                desc.vertexFunction,
                "vertex",
                key,
                (__bridge const void*)nativeLibrary),
            errorMessage);
        return nullptr;
    }

    id<MTLFunction> fragmentFunction = nil;
    if (!desc.fragmentFunction.empty()) {
        fragmentFunction = (__bridge id<MTLFunction>)library.nativeFunction(desc.fragmentFunction);
        if (fragmentFunction == nil) {
            setErrorMessage(
                missingRenderFunctionMessage(
                    library,
                    desc,
                    desc.fragmentFunction,
                    "fragment",
                    key,
                    (__bridge const void*)nativeLibrary),
                errorMessage);
            return nullptr;
        }
    }

    MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;
    pipelineDescriptor.rasterSampleCount = desc.rasterSampleCount;
    pipelineDescriptor.colorAttachments[0].pixelFormat = toPixelFormat(desc.colorFormat);
    pipelineDescriptor.label = toNSString(renderPipelineLabel(desc));

    if (desc.depthEnabled) {
        pipelineDescriptor.depthAttachmentPixelFormat = toPixelFormat(desc.depthFormat);
    }

    if (desc.blendMode != MetalBlendMode::Disabled) {
        MTLRenderPipelineColorAttachmentDescriptor* colorAttachment = pipelineDescriptor.colorAttachments[0];
        colorAttachment.blendingEnabled = YES;
        switch (desc.blendMode) {
        case MetalBlendMode::Alpha:
            colorAttachment.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
            colorAttachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            colorAttachment.sourceAlphaBlendFactor = MTLBlendFactorOne;
            colorAttachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            break;
        case MetalBlendMode::PremultipliedAlpha:
            colorAttachment.sourceRGBBlendFactor = MTLBlendFactorOne;
            colorAttachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            colorAttachment.sourceAlphaBlendFactor = MTLBlendFactorOne;
            colorAttachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            break;
        case MetalBlendMode::Additive:
            colorAttachment.sourceRGBBlendFactor = MTLBlendFactorOne;
            colorAttachment.destinationRGBBlendFactor = MTLBlendFactorOne;
            colorAttachment.sourceAlphaBlendFactor = MTLBlendFactorOne;
            colorAttachment.destinationAlphaBlendFactor = MTLBlendFactorOne;
            break;
        case MetalBlendMode::Disabled:
            break;
        }
        colorAttachment.rgbBlendOperation = MTLBlendOperationAdd;
        colorAttachment.alphaBlendOperation = MTLBlendOperationAdd;
    }

    NSError* error = nil;
    id<MTLRenderPipelineState> pipelineState =
        [m_impl->device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    if (pipelineState == nil) {
        std::string message = "Failed to create Metal render pipeline: " +
            renderPipelineDiagnostics(library, desc, key, (__bridge const void*)nativeLibrary, "miss");
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

    id<MTLLibrary> nativeLibrary = (__bridge id<MTLLibrary>)library.nativeLibrary();
    const std::string key = computeKey(desc, (__bridge const void*)nativeLibrary);
    auto cached = m_impl->computePipelines.find(key);
    if (cached != m_impl->computePipelines.end()) {
        setErrorMessage(std::string{}, errorMessage);
        return (__bridge void*)cached->second;
    }

    id<MTLFunction> function = (__bridge id<MTLFunction>)library.nativeFunction(desc.function);
    if (function == nil) {
        setErrorMessage(
            missingComputeFunctionMessage(library, desc, key, (__bridge const void*)nativeLibrary),
            errorMessage);
        return nullptr;
    }

    MTLComputePipelineDescriptor* pipelineDescriptor = [[MTLComputePipelineDescriptor alloc] init];
    pipelineDescriptor.computeFunction = function;
    pipelineDescriptor.label = toNSString(computePipelineLabel(desc));
    pipelineDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth =
        desc.threadGroupSizeIsMultipleOfThreadExecutionWidth ? YES : NO;
    pipelineDescriptor.supportIndirectCommandBuffers = desc.supportIndirectCommandBuffers ? YES : NO;
    if (desc.maxTotalThreadsPerThreadgroup > 0) {
        pipelineDescriptor.maxTotalThreadsPerThreadgroup = desc.maxTotalThreadsPerThreadgroup;
    }

    NSError* error = nil;
    id<MTLComputePipelineState> pipelineState =
        [m_impl->device newComputePipelineStateWithDescriptor:pipelineDescriptor
                                                      options:MTLPipelineOptionNone
                                                   reflection:nil
                                                        error:&error];
    if (pipelineState == nil) {
        std::string message = "Failed to create Metal compute pipeline: " +
            computePipelineDiagnostics(library, desc, key, (__bridge const void*)nativeLibrary, "miss");
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

bool MetalPipelineCache::rebuild(
    MetalShaderLibrary& library,
    const std::vector<MetalRenderPipelineDesc>& renderPipelineDescs,
    const std::vector<MetalComputePipelineDesc>& computePipelineDescs,
    std::string* errorMessage)
{
    clear();

    std::string pipelineError;
    for (std::size_t i = 0; i < renderPipelineDescs.size(); ++i) {
        pipelineError.clear();
        if (renderPipeline(library, renderPipelineDescs[i], &pipelineError) != nullptr) {
            continue;
        }

        std::ostringstream message;
        message << "Failed to rebuild Metal render pipeline " << (i + 1) << "/" << renderPipelineDescs.size();
        if (!renderPipelineDescs[i].label.empty()) {
            message << " ('" << renderPipelineDescs[i].label << "')";
        }
        if (!pipelineError.empty()) {
            message << ": " << pipelineError;
        } else {
            message << ": pipeline cache returned no diagnostic.";
        }
        setErrorMessage(message.str(), errorMessage);
        clear();
        return false;
    }

    for (std::size_t i = 0; i < computePipelineDescs.size(); ++i) {
        pipelineError.clear();
        if (computePipeline(library, computePipelineDescs[i], &pipelineError) != nullptr) {
            continue;
        }

        std::ostringstream message;
        message << "Failed to rebuild Metal compute pipeline " << (i + 1) << "/" << computePipelineDescs.size();
        if (!computePipelineDescs[i].label.empty()) {
            message << " ('" << computePipelineDescs[i].label << "')";
        }
        if (!pipelineError.empty()) {
            message << ": " << pipelineError;
        } else {
            message << ": pipeline cache returned no diagnostic.";
        }
        setErrorMessage(message.str(), errorMessage);
        clear();
        return false;
    }

    setErrorMessage(std::string{}, errorMessage);
    return true;
}

bool MetalPipelineCache::rebuildStandardPipelines(
    MetalShaderLibrary& library,
    MetalTextureFormat colorFormat,
    MetalTextureFormat depthFormat,
    uint32_t rasterSampleCount,
    std::string* errorMessage)
{
    std::vector<MetalRenderPipelineDesc> renderDescs;
    renderDescs.reserve(2);
    renderDescs.push_back(meshPipelineDesc(colorFormat, depthFormat, rasterSampleCount));
    renderDescs.push_back(gaussianPipelineDesc(colorFormat, depthFormat, rasterSampleCount));

    std::vector<MetalComputePipelineDesc> computeDescs;
    computeDescs.reserve(5);
    computeDescs.push_back(conversionPipelineDesc());
    std::vector<MetalComputePipelineDesc> sortDescs = sortPipelineDescs();
    computeDescs.insert(
        computeDescs.end(),
        std::make_move_iterator(sortDescs.begin()),
        std::make_move_iterator(sortDescs.end()));

    return rebuild(library, renderDescs, computeDescs, errorMessage);
}

} // namespace mesh2splat::metal
