#include "MetalShaderLibrary.hpp"

#include "MetalDeviceContext.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <sstream>
#include <unordered_map>

namespace mesh2splat::metal {

namespace {

std::string nsStringValue(NSString* value)
{
    if (value == nil) {
        return std::string{};
    }

    const char* text = value.UTF8String;
    return text == nullptr ? std::string{} : std::string(text);
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

NSString* toNSString(const std::string& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding];
}

const char* shaderSourceKindName(MetalShaderLibrarySource sourceKind)
{
    switch (sourceKind) {
    case MetalShaderLibrarySource::None:
        return "none";
    case MetalShaderLibrarySource::MetallibFile:
        return "metallib";
    case MetalShaderLibrarySource::DefaultLibrary:
        return "default";
    case MetalShaderLibrarySource::RuntimeSource:
        return "source";
    }

    return "unknown";
}

std::string formatByteCount(std::size_t byteCount)
{
    return std::to_string(byteCount) + (byteCount == 1 ? " byte" : " bytes");
}

std::string buildSourceDescription(
    MetalShaderLibrarySource sourceKind,
    const std::string& identifier,
    std::size_t byteCount,
    const std::string& debugLabel)
{
    std::string description = std::string("Metal shader library source=") + shaderSourceKindName(sourceKind);
    if (!identifier.empty()) {
        description += ", identifier=" + identifier;
    }
    if (!debugLabel.empty()) {
        description += ", label=" + debugLabel;
    }
    if (byteCount > 0) {
        description += ", size=" + formatByteCount(byteCount);
    }
    return description;
}

std::string joinFunctionNames(const std::vector<std::string>& names, std::size_t maxNames)
{
    std::ostringstream joined;
    const std::size_t nameCount = std::min(names.size(), maxNames);
    for (std::size_t index = 0; index < nameCount; ++index) {
        if (index != 0) {
            joined << ", ";
        }
        joined << names[index];
    }

    if (names.size() > maxNames) {
        joined << ", +" << (names.size() - maxNames) << " more";
    }

    return joined.str();
}

std::vector<std::string> captureFunctionNames(id<MTLLibrary> library)
{
    std::vector<std::string> names;
    if (library == nil) {
        return names;
    }

    NSArray<NSString*>* metalFunctionNames = library.functionNames;
    names.reserve(metalFunctionNames.count);
    for (NSString* functionName in metalFunctionNames) {
        names.push_back(nsStringValue(functionName));
    }
    std::sort(names.begin(), names.end());
    return names;
}

std::string fileStatusError(const std::string& path, NSString* nsPath)
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:nsPath isDirectory:&isDirectory]) {
        return "Bundled Metal shader metallib is missing: " + path;
    }
    if (isDirectory) {
        return "Bundled Metal shader metallib path is a directory, not a file: " + path;
    }
    if (![fileManager isReadableFileAtPath:nsPath]) {
        return "Bundled Metal shader metallib is not readable: " + path;
    }

    return std::string{};
}

std::size_t fileByteCount(NSString* nsPath)
{
    NSError* error = nil;
    NSDictionary<NSFileAttributeKey, id>* attributes =
        [[NSFileManager defaultManager] attributesOfItemAtPath:nsPath error:&error];
    if (attributes == nil) {
        return 0;
    }

    return static_cast<std::size_t>(attributes.fileSize);
}

std::string defaultDebugLabel(MetalShaderLibrarySource sourceKind, const char* requestedLabel)
{
    if (requestedLabel != nullptr && requestedLabel[0] != '\0') {
        return requestedLabel;
    }

    switch (sourceKind) {
    case MetalShaderLibrarySource::MetallibFile:
        return "Mesh2Splat Metal Library (metallib)";
    case MetalShaderLibrarySource::DefaultLibrary:
        return "Mesh2Splat Metal Library (default)";
    case MetalShaderLibrarySource::RuntimeSource:
        return "Mesh2Splat Metal Library (runtime source)";
    case MetalShaderLibrarySource::None:
        return std::string{};
    }

    return std::string{};
}

} // namespace

struct MetalShaderLibrary::Impl {
    id<MTLDevice> device = nil;
    id<MTLLibrary> library = nil;
    MetalShaderLibrarySource sourceKind = MetalShaderLibrarySource::None;
    std::string sourceIdentifier;
    std::string debugLabel;
    std::string lastErrorMessage;
    std::string sourceDescription =
        buildSourceDescription(MetalShaderLibrarySource::None, std::string{}, 0, std::string{});
    std::vector<std::string> functionNameCache;
    std::unordered_map<std::string, id<MTLFunction>> functionCache;
    std::size_t sourceByteCount = 0;

    void clearLoadedSource()
    {
        library = nil;
        sourceKind = MetalShaderLibrarySource::None;
        sourceIdentifier.clear();
        debugLabel.clear();
        sourceByteCount = 0;
        sourceDescription =
            buildSourceDescription(sourceKind, sourceIdentifier, sourceByteCount, debugLabel);
        functionNameCache.clear();
        functionCache.clear();
    }

    void setLoadFailure(const std::string& message, std::string* errorMessage)
    {
        clearLoadedSource();
        lastErrorMessage = message;
        setErrorMessage(lastErrorMessage, errorMessage);
    }

    void setLoadedSource(
        id<MTLLibrary> loadedLibrary,
        MetalShaderLibrarySource loadedSourceKind,
        const std::string& loadedSourceIdentifier,
        std::size_t loadedSourceByteCount,
        const std::string& loadedDebugLabel)
    {
        library = loadedLibrary;
        sourceKind = loadedSourceKind;
        sourceIdentifier = loadedSourceIdentifier;
        sourceByteCount = loadedSourceByteCount;
        debugLabel = loadedDebugLabel;
        if (library != nil && !debugLabel.empty()) {
            library.label = toNSString(debugLabel);
        }
        sourceDescription =
            buildSourceDescription(sourceKind, sourceIdentifier, sourceByteCount, debugLabel);
        functionNameCache = captureFunctionNames(library);
        functionCache.clear();
        lastErrorMessage.clear();
    }
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
        m_impl->setLoadFailure(
            "Metal device is unavailable; cannot load the default shader library.",
            nullptr);
        return false;
    }

    id<MTLLibrary> library = [m_impl->device newDefaultLibrary];
    if (library == nil) {
        m_impl->setLoadFailure(
            "Metal default shader library is unavailable; fallback should continue with bundled runtime .metal source.",
            nullptr);
        return false;
    }

    m_impl->setLoadedSource(
        library,
        MetalShaderLibrarySource::DefaultLibrary,
        "MTLDevice newDefaultLibrary",
        0,
        defaultDebugLabel(MetalShaderLibrarySource::DefaultLibrary, label));
    return true;
}

bool MetalShaderLibrary::loadFromFile(const std::string& path, std::string* errorMessage)
{
    if (m_impl->device == nil || path.empty()) {
        m_impl->setLoadFailure(
            path.empty()
                ? "Metal shader library path is empty."
                : "Metal device is unavailable; cannot load shader library from file.",
            errorMessage);
        return false;
    }

    NSError* error = nil;
    NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
    if (nsPath == nil) {
        m_impl->setLoadFailure(
            "Metal shader library path is not valid UTF-8; fallback should continue with the default library, "
            "then bundled runtime .metal source.",
            errorMessage);
        return false;
    }

    const std::string statusError = fileStatusError(path, nsPath);
    if (!statusError.empty()) {
        m_impl->setLoadFailure(
            statusError + "; fallback should continue with the default library, then bundled runtime .metal source.",
            errorMessage);
        return false;
    }

    NSURL* url = [NSURL fileURLWithPath:nsPath];
    id<MTLLibrary> library = [m_impl->device newLibraryWithURL:url error:&error];
    if (library == nil) {
        const std::string errorText = errorDescription(error);
        std::string message =
            "Failed to load bundled Metal shader metallib '" + path +
            "'; fallback should continue with the default library, then bundled runtime .metal source";
        if (!errorText.empty()) {
            message += ": " + errorText;
        }
        m_impl->setLoadFailure(message, errorMessage);
        return false;
    }

    m_impl->setLoadedSource(
        library,
        MetalShaderLibrarySource::MetallibFile,
        path,
        fileByteCount(nsPath),
        defaultDebugLabel(MetalShaderLibrarySource::MetallibFile, nullptr));
    setErrorMessage(m_impl->lastErrorMessage, errorMessage);
    return m_impl->library != nil;
}

bool MetalShaderLibrary::compileSource(const std::string& source, const char* label, std::string* errorMessage)
{
    if (m_impl->device == nil || source.empty()) {
        m_impl->setLoadFailure(
            source.empty()
                ? "Runtime Metal shader source is empty."
                : "Metal device is unavailable; cannot compile runtime shader source.",
            errorMessage);
        return false;
    }

    NSError* error = nil;
    NSString* nsSource = [[NSString alloc] initWithBytes:source.data()
                                                  length:source.size()
                                                encoding:NSUTF8StringEncoding];
    if (nsSource == nil) {
        m_impl->setLoadFailure(
            "Runtime Metal shader source is not valid UTF-8 (" + formatByteCount(source.size()) +
                "); no shader-library fallback remains.",
            errorMessage);
        return false;
    }

    MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
    options.languageVersion = MTLLanguageVersion3_1;
    id<MTLLibrary> library = [m_impl->device newLibraryWithSource:nsSource options:options error:&error];
    if (library == nil) {
        const std::string errorText = errorDescription(error);
        std::string message =
            "Failed to compile bundled runtime Metal shader source (" + formatByteCount(source.size()) +
            "); no shader-library fallback remains";
        if (!errorText.empty()) {
            message += ": " + errorText;
        }
        m_impl->setLoadFailure(message, errorMessage);
        return false;
    }

    m_impl->setLoadedSource(
        library,
        MetalShaderLibrarySource::RuntimeSource,
        "bundled runtime .metal source",
        source.size(),
        defaultDebugLabel(MetalShaderLibrarySource::RuntimeSource, label));
    setErrorMessage(m_impl->lastErrorMessage, errorMessage);
    return true;
}

bool MetalShaderLibrary::isValid() const
{
    return m_impl->library != nil;
}

MetalShaderLibrarySource MetalShaderLibrary::sourceKind() const
{
    return m_impl->sourceKind;
}

const char* MetalShaderLibrary::sourceKindName() const
{
    return shaderSourceKindName(m_impl->sourceKind);
}

const std::string& MetalShaderLibrary::sourceIdentifier() const
{
    return m_impl->sourceIdentifier;
}

std::size_t MetalShaderLibrary::sourceByteCount() const
{
    return m_impl->sourceByteCount;
}

const std::string& MetalShaderLibrary::debugLabel() const
{
    return m_impl->debugLabel;
}

const std::string& MetalShaderLibrary::lastError() const
{
    return m_impl->lastErrorMessage;
}

const std::string& MetalShaderLibrary::lastErrorMessage() const
{
    return m_impl->lastErrorMessage;
}

const std::string& MetalShaderLibrary::sourceDescription() const
{
    return m_impl->sourceDescription;
}

std::vector<std::string> MetalShaderLibrary::functionNames() const
{
    return m_impl->functionNameCache;
}

std::size_t MetalShaderLibrary::functionCount() const
{
    return m_impl->functionNameCache.size();
}

std::string MetalShaderLibrary::availableFunctionList(std::size_t maxNames) const
{
    return joinFunctionNames(m_impl->functionNameCache, maxNames);
}

bool MetalShaderLibrary::hasFunction(const std::string& functionName) const
{
    if (m_impl->library == nil || functionName.empty() || m_impl->functionNameCache.empty()) {
        return false;
    }

    return std::binary_search(
        m_impl->functionNameCache.begin(),
        m_impl->functionNameCache.end(),
        functionName);
}

void* MetalShaderLibrary::nativeFunction(const std::string& functionName, std::string* errorMessage)
{
    if (m_impl->library == nil || functionName.empty()) {
        m_impl->lastErrorMessage = functionName.empty()
            ? "Metal shader function name is empty."
            : "Metal shader library is invalid; cannot look up function '" + functionName + "'.";
        setErrorMessage(m_impl->lastErrorMessage, errorMessage);
        return nullptr;
    }

    auto cached = m_impl->functionCache.find(functionName);
    if (cached != m_impl->functionCache.end()) {
        m_impl->lastErrorMessage.clear();
        setErrorMessage(std::string{}, errorMessage);
        return (__bridge void*)cached->second;
    }

    if (!hasFunction(functionName)) {
        m_impl->lastErrorMessage = missingFunctionDiagnostic(functionName);
        setErrorMessage(m_impl->lastErrorMessage, errorMessage);
        return nullptr;
    }

    NSString* nativeFunctionName = toNSString(functionName);
    if (nativeFunctionName == nil) {
        m_impl->lastErrorMessage =
            "Metal shader function name is not valid UTF-8: '" + functionName + "'.";
        setErrorMessage(m_impl->lastErrorMessage, errorMessage);
        return nullptr;
    }

    id<MTLFunction> function = [m_impl->library newFunctionWithName:nativeFunctionName];
    if (function == nil) {
        m_impl->lastErrorMessage = missingFunctionDiagnostic(functionName);
        setErrorMessage(m_impl->lastErrorMessage, errorMessage);
        return nullptr;
    }

    m_impl->functionCache.emplace(functionName, function);
    m_impl->lastErrorMessage.clear();
    setErrorMessage(std::string{}, errorMessage);
    return (__bridge void*)function;
}

std::string MetalShaderLibrary::missingFunctionDiagnostic(
    const std::string& functionName,
    const std::string& functionRole,
    const std::string& pipelineLabel) const
{
    std::string message = "Missing Metal ";
    if (!functionRole.empty()) {
        message += functionRole + " ";
    }
    message += "function";
    if (!functionName.empty()) {
        message += " '" + functionName + "'";
    }
    if (!pipelineLabel.empty()) {
        message += " for pipeline '" + pipelineLabel + "'";
    }

    if (!isValid()) {
        message += ". Shader library is invalid";
        if (!m_impl->lastErrorMessage.empty()) {
            message += ": " + m_impl->lastErrorMessage;
        } else {
            message += ".";
        }
        return message;
    }

    message += ". Loaded " + m_impl->sourceDescription + ".";

    if (m_impl->functionNameCache.empty()) {
        message += " The loaded library reports no public shader functions.";
        return message;
    }

    message += " Available functions: " + availableFunctionList(16) + ".";
    return message;
}

void* MetalShaderLibrary::nativeLibrary() const
{
    return (__bridge void*)m_impl->library;
}

} // namespace mesh2splat::metal
