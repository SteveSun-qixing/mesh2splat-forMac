#include "MetalShaderLibrary.hpp"

#include "MetalDeviceContext.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

namespace mesh2splat::metal {

namespace {

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

struct MetalShaderLibrary::Impl {
    id<MTLDevice> device = nil;
    id<MTLLibrary> library = nil;
    std::string lastErrorMessage;
    std::string sourceDescription;
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
        m_impl->lastErrorMessage = "Metal device is unavailable; cannot load the default shader library.";
        m_impl->sourceDescription.clear();
        return false;
    }

    m_impl->library = [m_impl->device newDefaultLibrary];
    if (m_impl->library == nil) {
        m_impl->lastErrorMessage =
            "Metal default shader library is unavailable. Bundle a metallib or ship .metal source files.";
        m_impl->sourceDescription.clear();
        return false;
    }

    if (label != nullptr) {
        m_impl->library.label = [NSString stringWithUTF8String:label];
    }
    m_impl->lastErrorMessage.clear();
    m_impl->sourceDescription = "Metal default shader library";
    return true;
}

bool MetalShaderLibrary::loadFromFile(const std::string& path, std::string* errorMessage)
{
    if (m_impl->device == nil || path.empty()) {
        m_impl->library = nil;
        m_impl->lastErrorMessage = path.empty()
            ? "Metal shader library path is empty."
            : "Metal device is unavailable; cannot load shader library from file.";
        m_impl->sourceDescription.clear();
        setErrorMessage(m_impl->lastErrorMessage, errorMessage);
        return false;
    }

    NSError* error = nil;
    NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
    NSURL* url = [NSURL fileURLWithPath:nsPath];
    m_impl->library = [m_impl->device newLibraryWithURL:url error:&error];
    if (m_impl->library == nil) {
        const std::string errorText = errorDescription(error);
        m_impl->lastErrorMessage = "Failed to load Metal shader library from " + path;
        if (!errorText.empty()) {
            m_impl->lastErrorMessage += ": " + errorText;
        }
        m_impl->sourceDescription.clear();
        setErrorMessage(m_impl->lastErrorMessage, errorMessage);
        return false;
    }

    m_impl->lastErrorMessage.clear();
    m_impl->sourceDescription = "Metal shader library file: " + path;
    setErrorMessage(m_impl->lastErrorMessage, errorMessage);
    return m_impl->library != nil;
}

bool MetalShaderLibrary::compileSource(const std::string& source, const char* label, std::string* errorMessage)
{
    if (m_impl->device == nil || source.empty()) {
        m_impl->library = nil;
        m_impl->lastErrorMessage = source.empty()
            ? "Runtime Metal shader source is empty."
            : "Metal device is unavailable; cannot compile runtime shader source.";
        m_impl->sourceDescription.clear();
        setErrorMessage(m_impl->lastErrorMessage, errorMessage);
        return false;
    }

    NSError* error = nil;
    NSString* nsSource = [NSString stringWithUTF8String:source.c_str()];
    MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
    options.languageVersion = MTLLanguageVersion3_1;
    m_impl->library = [m_impl->device newLibraryWithSource:nsSource options:options error:&error];
    if (m_impl->library == nil) {
        const std::string errorText = errorDescription(error);
        m_impl->lastErrorMessage =
            "Failed to compile runtime Metal shader source (" + std::to_string(source.size()) + " bytes)";
        if (!errorText.empty()) {
            m_impl->lastErrorMessage += ": " + errorText;
        }
        m_impl->sourceDescription.clear();
        setErrorMessage(m_impl->lastErrorMessage, errorMessage);
        return false;
    }

    if (m_impl->library != nil && label != nullptr) {
        m_impl->library.label = [NSString stringWithUTF8String:label];
    }

    m_impl->lastErrorMessage.clear();
    m_impl->sourceDescription =
        "Runtime Metal shader source (" + std::to_string(source.size()) + " bytes)";
    setErrorMessage(m_impl->lastErrorMessage, errorMessage);
    return true;
}

bool MetalShaderLibrary::isValid() const
{
    return m_impl->library != nil;
}

const std::string& MetalShaderLibrary::lastErrorMessage() const
{
    return m_impl->lastErrorMessage;
}

const std::string& MetalShaderLibrary::sourceDescription() const
{
    return m_impl->sourceDescription;
}

void* MetalShaderLibrary::nativeLibrary() const
{
    return (__bridge void*)m_impl->library;
}

} // namespace mesh2splat::metal
