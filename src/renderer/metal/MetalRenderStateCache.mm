#include "MetalRenderStateCache.hpp"

#include "MetalDeviceContext.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <sstream>
#include <unordered_map>
#include <utility>

namespace mesh2splat::metal {
namespace {

MTLSamplerMinMagFilter toMinMagFilter(MetalSamplerFilter filter)
{
    switch (filter) {
    case MetalSamplerFilter::Nearest:
        return MTLSamplerMinMagFilterNearest;
    case MetalSamplerFilter::Linear:
        return MTLSamplerMinMagFilterLinear;
    }
}

MTLSamplerMipFilter toMipFilter(MetalSamplerFilter filter)
{
    switch (filter) {
    case MetalSamplerFilter::Nearest:
        return MTLSamplerMipFilterNearest;
    case MetalSamplerFilter::Linear:
        return MTLSamplerMipFilterLinear;
    }
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
}

NSString* toNSString(const std::string& value)
{
    return [NSString stringWithUTF8String:value.c_str()];
}

std::string samplerKey(const MetalSamplerDesc& desc)
{
    std::ostringstream key;
    key << static_cast<int>(desc.minFilter) << '|'
        << static_cast<int>(desc.magFilter) << '|'
        << static_cast<int>(desc.mipFilter) << '|'
        << static_cast<int>(desc.addressU) << '|'
        << static_cast<int>(desc.addressV) << '|'
        << static_cast<int>(desc.addressW);
    return key.str();
}

std::string depthStencilKey(const MetalDepthStencilDesc& desc)
{
    std::ostringstream key;
    key << desc.depthTestEnabled << '|'
        << desc.depthWriteEnabled << '|'
        << static_cast<int>(desc.depthCompareFunction);
    return key.str();
}

} // namespace

struct MetalRenderStateCache::Impl {
    id<MTLDevice> device = nil;
    std::unordered_map<std::string, id<MTLSamplerState>> samplerStates;
    std::unordered_map<std::string, id<MTLDepthStencilState>> depthStencilStates;
};

MetalRenderStateCache::MetalRenderStateCache(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)deviceContext.nativeDevice();
}

MetalRenderStateCache::~MetalRenderStateCache() = default;

MetalRenderStateCache::MetalRenderStateCache(MetalRenderStateCache&&) noexcept = default;

MetalRenderStateCache& MetalRenderStateCache::operator=(MetalRenderStateCache&&) noexcept = default;

void* MetalRenderStateCache::samplerState(const MetalSamplerDesc& desc)
{
    if (m_impl->device == nil) {
        return nullptr;
    }

    const std::string key = samplerKey(desc);
    auto existing = m_impl->samplerStates.find(key);
    if (existing != m_impl->samplerStates.end()) {
        return (__bridge void*)existing->second;
    }

    MTLSamplerDescriptor* samplerDescriptor = [[MTLSamplerDescriptor alloc] init];
    samplerDescriptor.minFilter = toMinMagFilter(desc.minFilter);
    samplerDescriptor.magFilter = toMinMagFilter(desc.magFilter);
    samplerDescriptor.mipFilter = toMipFilter(desc.mipFilter);
    samplerDescriptor.sAddressMode = toAddressMode(desc.addressU);
    samplerDescriptor.tAddressMode = toAddressMode(desc.addressV);
    samplerDescriptor.rAddressMode = toAddressMode(desc.addressW);
    if (!desc.label.empty()) {
        samplerDescriptor.label = toNSString(desc.label);
    }

    id<MTLSamplerState> state = [m_impl->device newSamplerStateWithDescriptor:samplerDescriptor];
    if (state == nil) {
        return nullptr;
    }

    m_impl->samplerStates.insert_or_assign(key, state);
    return (__bridge void*)state;
}

void* MetalRenderStateCache::depthStencilState(const MetalDepthStencilDesc& desc)
{
    if (m_impl->device == nil) {
        return nullptr;
    }

    const std::string key = depthStencilKey(desc);
    auto existing = m_impl->depthStencilStates.find(key);
    if (existing != m_impl->depthStencilStates.end()) {
        return (__bridge void*)existing->second;
    }

    MTLDepthStencilDescriptor* depthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
    depthDescriptor.depthWriteEnabled = desc.depthTestEnabled && desc.depthWriteEnabled;
    depthDescriptor.depthCompareFunction =
        desc.depthTestEnabled ? toCompareFunction(desc.depthCompareFunction) : MTLCompareFunctionAlways;
    if (!desc.label.empty()) {
        depthDescriptor.label = toNSString(desc.label);
    }

    id<MTLDepthStencilState> state = [m_impl->device newDepthStencilStateWithDescriptor:depthDescriptor];
    if (state == nil) {
        return nullptr;
    }

    m_impl->depthStencilStates.insert_or_assign(key, state);
    return (__bridge void*)state;
}

void MetalRenderStateCache::clear()
{
    m_impl->samplerStates.clear();
    m_impl->depthStencilStates.clear();
}

std::size_t MetalRenderStateCache::samplerStateCount() const
{
    return m_impl->samplerStates.size();
}

std::size_t MetalRenderStateCache::depthStencilStateCount() const
{
    return m_impl->depthStencilStates.size();
}

} // namespace mesh2splat::metal
