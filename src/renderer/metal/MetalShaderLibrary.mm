#include "MetalShaderLibrary.hpp"

#include "MetalDeviceContext.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

namespace mesh2splat::metal {

namespace {

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

struct MetalShaderLibrary::Impl {
    id<MTLDevice> device = nil;
    id<MTLLibrary> library = nil;
};

MetalShaderLibrary::MetalShaderLibrary(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)deviceContext.nativeDevice();
}

MetalShaderLibrary::~MetalShaderLibrary() = default;

MetalShaderLibrary::MetalShaderLibrary(MetalShaderLibrary&&) noexcept = default;

MetalShaderLibrary& MetalShaderLibrary::operator=(MetalShaderLibrary&&) noexcept = default;

bool MetalShaderLibrary::loadDefault(const char* label)
{
    if (m_impl->device == nil) {
        return false;
    }

    m_impl->library = [m_impl->device newDefaultLibrary];
    if (m_impl->library == nil) {
        return false;
    }

    if (label != nullptr) {
        m_impl->library.label = [NSString stringWithUTF8String:label];
    }
    return true;
}

bool MetalShaderLibrary::loadFromFile(const std::string& path, std::string* errorMessage)
{
    if (m_impl->device == nil || path.empty()) {
        return false;
    }

    NSError* error = nil;
    NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
    NSURL* url = [NSURL fileURLWithPath:nsPath];
    m_impl->library = [m_impl->device newLibraryWithURL:url error:&error];
    setErrorMessage(error, errorMessage);
    return m_impl->library != nil;
}

bool MetalShaderLibrary::compileSource(const std::string& source, const char* label, std::string* errorMessage)
{
    if (m_impl->device == nil || source.empty()) {
        return false;
    }

    NSError* error = nil;
    NSString* nsSource = [NSString stringWithUTF8String:source.c_str()];
    MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
    options.languageVersion = MTLLanguageVersion3_1;
    m_impl->library = [m_impl->device newLibraryWithSource:nsSource options:options error:&error];
    setErrorMessage(error, errorMessage);

    if (m_impl->library != nil && label != nullptr) {
        m_impl->library.label = [NSString stringWithUTF8String:label];
    }

    return m_impl->library != nil;
}

bool MetalShaderLibrary::isValid() const
{
    return m_impl->library != nil;
}

void* MetalShaderLibrary::nativeLibrary() const
{
    return (__bridge void*)m_impl->library;
}

} // namespace mesh2splat::metal
