#include "MetalRenderer.hpp"

#include "core/AssetFileTypes.hpp"
#include "core/ConversionSettings.hpp"
#include "core/FrameData.hpp"
#include "core/GaussianData.hpp"
#include "core/CameraController.hpp"
#include "core/PrimitiveMeshFactory.hpp"
#include "core/RenderSettings.hpp"
#include "io/GltfLoader.hpp"
#include "io/PlyWriter.hpp"
#include "MetalCommandScheduler.hpp"
#include "MetalConversionPass.hpp"
#include "MetalDeviceContext.hpp"
#include "MetalFrameCapture.hpp"
#include "MetalFrameUniformBuffer.hpp"
#include "MetalFrameResources.hpp"
#include "MetalGaussianBuffer.hpp"
#include "MetalGaussianRenderPass.hpp"
#include "MetalGaussianSortBuffer.hpp"
#include "MetalGaussianSortPass.hpp"
#include "MetalMeshRenderPass.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalRenderStateCache.hpp"
#include "MetalRenderTarget.hpp"
#include "MetalSceneResources.hpp"
#include "MetalShaderLibrary.hpp"
#include "renderer/RendererAssetSession.hpp"
#include "renderer/event.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <dispatch/dispatch.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <limits>
#include <mutex>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace mesh2splat::metal {
namespace {

using Clock = std::chrono::steady_clock;

constexpr uint32_t kDefaultMetalConversionSamplesPerTriangle = core::kDefaultConversionSamplesPerTriangle;
constexpr float kCompletedProgress = 1.0f;

const char* rendererStateName(mesh2splat::renderer::RendererRuntimeState state)
{
    using mesh2splat::renderer::RendererRuntimeState;
    switch (state) {
    case RendererRuntimeState::Unknown:
        return "unknown";
    case RendererRuntimeState::Ready:
        return "ready";
    case RendererRuntimeState::Loading:
        return "loading";
    case RendererRuntimeState::Converting:
        return "converting";
    case RendererRuntimeState::Rendering:
        return "rendering";
    case RendererRuntimeState::Failed:
        return "failed";
    case RendererRuntimeState::Exporting:
        return "exporting";
    }
    return "unknown";
}

mesh2splat::renderer::RendererDiagnosticSeverity severityForState(
    mesh2splat::renderer::RendererRuntimeState state,
    const std::string& diagnostic)
{
    if (state == mesh2splat::renderer::RendererRuntimeState::Failed) {
        return mesh2splat::renderer::RendererDiagnosticSeverity::Error;
    }
    return diagnostic.empty()
        ? mesh2splat::renderer::RendererDiagnosticSeverity::Info
        : mesh2splat::renderer::RendererDiagnosticSeverity::Warning;
}

bool sceneKindCanLoadAsMesh(mesh2splat::renderer::RendererSceneKind requestedKind, const std::string& filePath)
{
    if (requestedKind == mesh2splat::renderer::RendererSceneKind::GaussianPly) {
        return false;
    }

    return core::assetFilePathSupportsIntent(filePath, core::AssetFileIntent::LoadMesh);
}

MetalRenderTargetDesc makeDrawableDepthTargetDesc(uint32_t width, uint32_t height)
{
    MetalRenderTargetDesc desc;
    desc.width = width;
    desc.height = height;
    desc.colorEnabled = false;
    desc.depthEnabled = true;
    desc.depthFormat = MetalTextureFormat::Depth32Float;
    desc.clearDepth = 1.0;
    desc.role = MetalRenderTargetRole::Depth;
    desc.label = "Mesh2Splat Drawable Depth Target";
    return desc;
}

std::string bundledMetallibPath()
{
    NSString* path = [[NSBundle mainBundle] pathForResource:@"Mesh2SplatMetal" ofType:@"metallib"];
    return path == nil ? std::string{} : std::string(path.UTF8String);
}

std::string bundledShaderSource()
{
    NSArray<NSString*>* shaderPaths = [[NSBundle mainBundle] pathsForResourcesOfType:@"metal" inDirectory:@"Shaders"];
    std::vector<std::string> paths;
    paths.reserve(shaderPaths.count);
    for (NSString* path in shaderPaths) {
        paths.push_back(path.UTF8String);
    }
    std::sort(paths.begin(), paths.end());

    std::string source;
    for (const std::string& path : paths) {
        NSError* error = nil;
        NSString* fileSource = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:path.c_str()]
                                                         encoding:NSUTF8StringEncoding
                                                            error:&error];
        if (fileSource == nil) {
            continue;
        }

        source += "\n#line 1 \"";
        source += path;
        source += "\"\n";
        source += fileSource.UTF8String;
        source += "\n";
    }

    return source;
}

void appendDiagnostic(std::vector<std::string>& diagnostics, std::string message)
{
    if (!message.empty()) {
        diagnostics.push_back(std::move(message));
    }
}

std::string joinDiagnostics(const std::vector<std::string>& diagnostics)
{
    std::string joined;
    for (const std::string& diagnostic : diagnostics) {
        if (diagnostic.empty()) {
            continue;
        }

        if (!joined.empty()) {
            joined += "\n";
        }
        joined += diagnostic;
    }

    return joined;
}

void setDiagnostic(std::string* output, const std::vector<std::string>& diagnostics)
{
    if (output != nullptr) {
        *output = joinDiagnostics(diagnostics);
    }
}

bool loadRendererShaderLibrary(MetalShaderLibrary& shaderLibrary, std::string* diagnostic)
{
    std::vector<std::string> diagnostics;
    const std::string metallibPath = bundledMetallibPath();
    if (!metallibPath.empty()) {
        std::string errorMessage;
        if (shaderLibrary.loadFromFile(metallibPath, &errorMessage)) {
            appendDiagnostic(diagnostics, "Loaded Metal shaders from bundled metallib: " + metallibPath);
            setDiagnostic(diagnostic, diagnostics);
            return true;
        }

        appendDiagnostic(diagnostics, errorMessage);
    } else {
        appendDiagnostic(diagnostics, "Bundled Mesh2SplatMetal.metallib was not found.");
    }

    if (shaderLibrary.loadDefault("Mesh2Splat Default Metal Library")) {
        appendDiagnostic(diagnostics, "Loaded Metal shaders from default library: " + shaderLibrary.sourceDescription());
        setDiagnostic(diagnostic, diagnostics);
        return true;
    }
    appendDiagnostic(diagnostics, shaderLibrary.lastErrorMessage());

    const std::string source = bundledShaderSource();
    if (source.empty()) {
        appendDiagnostic(diagnostics, "No bundled .metal shader source files were found under Shaders.");
        setDiagnostic(diagnostic, diagnostics);
        return false;
    }

    std::string compileError;
    if (shaderLibrary.compileSource(source, "Mesh2Splat Runtime Metal Library", &compileError)) {
        appendDiagnostic(diagnostics, "Compiled Metal shaders from bundled runtime source: " + shaderLibrary.sourceDescription());
        setDiagnostic(diagnostic, diagnostics);
        return true;
    }

    appendDiagnostic(diagnostics, compileError);
    setDiagnostic(diagnostic, diagnostics);
    return false;
}

std::string environmentString(const char* name)
{
    const char* value = std::getenv(name);
    return value == nullptr ? std::string{} : std::string(value);
}

bool environmentFlagEnabled(const char* name)
{
    const std::string value = environmentString(name);
    if (value.empty() ||
        value == "0" ||
        value == "false" ||
        value == "FALSE" ||
        value == "no" ||
        value == "NO" ||
        value == "off" ||
        value == "OFF") {
        return false;
    }
    return true;
}

uint64_t environmentUInt64(const char* name, uint64_t fallback, bool* parsed = nullptr)
{
    if (parsed != nullptr) {
        *parsed = false;
    }

    const std::string value = environmentString(name);
    if (value.empty()) {
        return fallback;
    }

    char* end = nullptr;
    errno = 0;
    const unsigned long long result = std::strtoull(value.c_str(), &end, 10);
    if (errno != 0 || end == value.c_str() || (end != nullptr && *end != '\0')) {
        return fallback;
    }

    if (parsed != nullptr) {
        *parsed = true;
    }
    return static_cast<uint64_t>(result);
}

MetalFrameCaptureScope captureScopeFromEnvironment()
{
    const std::string value = environmentString("MESH2SPLAT_METAL_CAPTURE_SCOPE");
    if (value == "pass" || value == "PASS") {
        return MetalFrameCaptureScope::Pass;
    }
    if (value == "command-buffer" ||
        value == "command_buffer" ||
        value == "commandBuffer" ||
        value == "COMMAND_BUFFER") {
        return MetalFrameCaptureScope::CommandBuffer;
    }
    return MetalFrameCaptureScope::Frame;
}

MetalFrameCaptureRequest captureRequestFromEnvironment()
{
    if (!environmentFlagEnabled("MESH2SPLAT_METAL_CAPTURE")) {
        return {};
    }

    bool parsedFrameIndex = false;
    const uint64_t frameIndex = environmentUInt64(
        "MESH2SPLAT_METAL_CAPTURE_FRAME",
        MetalFrameCapture::kAnyFrameIndex,
        &parsedFrameIndex);
    std::string reason = environmentString("MESH2SPLAT_METAL_CAPTURE_REASON");
    if (reason.empty()) {
        reason = "environment request";
    }
    std::string label = environmentString("MESH2SPLAT_METAL_CAPTURE_LABEL");
    if (label.empty()) {
        label = "Mesh2Splat Metal Frame";
    }

    return makeMetalFrameCaptureRequest(
        parsedFrameIndex ? frameIndex : MetalFrameCapture::kAnyFrameIndex,
        std::move(reason),
        true,
        captureScopeFromEnvironment(),
        std::move(label));
}

NSString* stringFromStdString(const std::string& value)
{
    return [NSString stringWithUTF8String:value.c_str()];
}

std::string captureRequestDescription(const MetalFrameCaptureRequest& request)
{
    std::string description = "Metal frame capture armed";
    description += " scope=";
    description += metalFrameCaptureScopeName(request.scope);
    if (request.hasSpecificFrame()) {
        description += " frame=" + std::to_string(request.frameIndex);
    } else {
        description += " frame=next";
    }
    if (!request.reason.empty()) {
        description += " reason=" + request.reason;
    }
    return description;
}

bool startMetalCapture(
    id<MTLCommandQueue> commandQueue,
    const MetalFrameCaptureMarkerMetadata& marker,
    std::string* diagnostic)
{
    if (commandQueue == nil) {
        if (diagnostic != nullptr) {
            *diagnostic = "Cannot start Metal capture: command queue is unavailable.";
        }
        return false;
    }

    MTLCaptureDescriptor* descriptor = [[MTLCaptureDescriptor alloc] init];
    descriptor.captureObject = commandQueue;

    const std::string outputPath = environmentString("MESH2SPLAT_METAL_CAPTURE_PATH");
    if (!outputPath.empty()) {
        descriptor.destination = MTLCaptureDestinationGPUTraceDocument;
        descriptor.outputURL = [NSURL fileURLWithPath:stringFromStdString(outputPath)];
    } else {
        descriptor.destination = MTLCaptureDestinationDeveloperTools;
    }

    NSError* error = nil;
    if (![[MTLCaptureManager sharedCaptureManager] startCaptureWithDescriptor:descriptor error:&error]) {
        if (diagnostic != nullptr) {
            *diagnostic = "Cannot start Metal capture";
            if (error != nil && error.localizedDescription.UTF8String != nullptr) {
                *diagnostic += ": ";
                *diagnostic += error.localizedDescription.UTF8String;
            }
        }
        return false;
    }

    if (diagnostic != nullptr) {
        *diagnostic = "Started Metal capture for " + marker.debugGroupLabel();
        if (!outputPath.empty()) {
            *diagnostic += " -> " + outputPath;
        }
    }
    return true;
}

void stopMetalCapture()
{
    MTLCaptureManager* captureManager = [MTLCaptureManager sharedCaptureManager];
    if (captureManager.isCapturing) {
        [captureManager stopCapture];
    }
}

uint32_t normalizedConversionSamples(uint32_t samplesPerTriangle)
{
    return core::normalizeConversionSamplesPerTriangle(samplesPerTriangle);
}

float clampedFinite(float value, float minimum, float maximum, float fallback)
{
    if (!std::isfinite(value)) {
        return fallback;
    }
    return std::clamp(value, minimum, maximum);
}

bool matrixApproximatelyEquals(
    const core::Matrix4& lhs,
    const core::Matrix4& rhs,
    float absoluteEpsilon = 1.0e-5f,
    float relativeEpsilon = 1.0e-5f)
{
    for (std::size_t i = 0; i < 16; ++i) {
        const float diff = std::fabs(lhs.values[i] - rhs.values[i]);
        const float scale = std::max(std::fabs(lhs.values[i]), std::fabs(rhs.values[i]));
        if (diff > absoluteEpsilon + scale * relativeEpsilon) {
            return false;
        }
    }

    return true;
}

double elapsedMilliseconds(Clock::time_point start, Clock::time_point end)
{
    return std::chrono::duration<double, std::milli>(end - start).count();
}

double commandBufferGpuMilliseconds(id<MTLCommandBuffer> commandBuffer)
{
    if (commandBuffer == nil || commandBuffer.status != MTLCommandBufferStatusCompleted) {
        return 0.0;
    }

    const CFTimeInterval startTime = commandBuffer.GPUStartTime;
    const CFTimeInterval endTime = commandBuffer.GPUEndTime;
    if (startTime <= 0.0 || endTime <= startTime) {
        return 0.0;
    }

    return static_cast<double>(endTime - startTime) * 1000.0;
}

std::string commandBufferStatusDescription(MTLCommandBufferStatus status)
{
    switch (status) {
    case MTLCommandBufferStatusNotEnqueued:
        return "not enqueued";
    case MTLCommandBufferStatusEnqueued:
        return "enqueued";
    case MTLCommandBufferStatusCommitted:
        return "committed";
    case MTLCommandBufferStatusScheduled:
        return "scheduled";
    case MTLCommandBufferStatusCompleted:
        return "completed";
    case MTLCommandBufferStatusError:
        return "error";
    }

    return "unknown";
}

std::string commandBufferErrorDescription(id<MTLCommandBuffer> commandBuffer)
{
    if (commandBuffer == nil || commandBuffer.error == nil) {
        return std::string{};
    }

    return commandBuffer.error.localizedDescription.UTF8String;
}

double exponentialAverage(double currentAverage, double sample)
{
    constexpr double kAlpha = 0.12;
    return currentAverage <= 0.0 ? sample : currentAverage + (sample - currentAverage) * kAlpha;
}

uint64_t toResourceBytes(std::size_t size)
{
    if (size > static_cast<std::size_t>(std::numeric_limits<uint64_t>::max())) {
        return std::numeric_limits<uint64_t>::max();
    }

    return static_cast<uint64_t>(size);
}

void addResourceBytes(uint64_t& total, uint64_t size)
{
    if (size > std::numeric_limits<uint64_t>::max() - total) {
        total = std::numeric_limits<uint64_t>::max();
        return;
    }

    total += size;
}

uint32_t textureWidth(id<MTLTexture> texture)
{
    if (texture == nil) {
        return 0;
    }
    if (texture.width > std::numeric_limits<uint32_t>::max()) {
        return std::numeric_limits<uint32_t>::max();
    }
    return static_cast<uint32_t>(texture.width);
}

uint32_t textureHeight(id<MTLTexture> texture)
{
    if (texture == nil) {
        return 0;
    }
    if (texture.height > std::numeric_limits<uint32_t>::max()) {
        return std::numeric_limits<uint32_t>::max();
    }
    return static_cast<uint32_t>(texture.height);
}

} // namespace

struct MetalRendererTimingState {
    mutable std::mutex mutex;
    MetalRendererStats stats;

    MetalRendererStats snapshot() const
    {
        std::lock_guard<std::mutex> lock(mutex);
        return stats;
    }

    void recordFrameSubmitted(
        double cpuEncodeMs,
        uint32_t gaussianCount,
        bool sortedGaussians,
        bool renderedMesh,
        bool renderedGaussians)
    {
        std::lock_guard<std::mutex> lock(mutex);
        ++stats.submittedFrameCount;
        stats.lastFrameCpuEncodeMs = cpuEncodeMs;
        stats.averageFrameCpuEncodeMs = exponentialAverage(stats.averageFrameCpuEncodeMs, cpuEncodeMs);
        stats.lastFrameGaussianCount = gaussianCount;
        stats.lastFrameSortedGaussians = sortedGaussians;
        stats.lastFrameRenderedMesh = renderedMesh;
        stats.lastFrameRenderedGaussians = renderedGaussians;
    }

    void recordFrameCompleted(bool succeeded, double gpuMs)
    {
        std::lock_guard<std::mutex> lock(mutex);
        ++stats.completedFrameCount;
        if (!succeeded) {
            ++stats.failedFrameCount;
            return;
        }

        stats.lastFrameGpuMs = gpuMs;
        if (gpuMs > 0.0) {
            stats.averageFrameGpuMs = exponentialAverage(stats.averageFrameGpuMs, gpuMs);
        }
    }

    void recordConversionSubmitted(double cpuSubmitMs)
    {
        std::lock_guard<std::mutex> lock(mutex);
        ++stats.submittedConversionCount;
        stats.lastConversionCpuSubmitMs = cpuSubmitMs;
        stats.averageConversionCpuSubmitMs =
            exponentialAverage(stats.averageConversionCpuSubmitMs, cpuSubmitMs);
    }

    void recordConversionCompleted(bool succeeded, double gpuMs)
    {
        std::lock_guard<std::mutex> lock(mutex);
        ++stats.completedConversionCount;
        if (!succeeded) {
            ++stats.failedConversionCount;
            return;
        }

        stats.lastConversionGpuMs = gpuMs;
        if (gpuMs > 0.0) {
            stats.averageConversionGpuMs = exponentialAverage(stats.averageConversionGpuMs, gpuMs);
        }
    }

    void recordFrameEncodeFailed(
        double cpuEncodeMs,
        uint32_t gaussianCount,
        bool sortedGaussians,
        bool renderedMesh,
        bool renderedGaussians)
    {
        std::lock_guard<std::mutex> lock(mutex);
        ++stats.failedFrameCount;
        stats.lastFrameCpuEncodeMs = cpuEncodeMs;
        stats.averageFrameCpuEncodeMs = exponentialAverage(stats.averageFrameCpuEncodeMs, cpuEncodeMs);
        stats.lastFrameGaussianCount = gaussianCount;
        stats.lastFrameSortedGaussians = sortedGaussians;
        stats.lastFrameRenderedMesh = renderedMesh;
        stats.lastFrameRenderedGaussians = renderedGaussians;
    }
};

struct PendingGaussianConversion {
    std::unique_ptr<MetalSceneResources> nextSceneResources;
    std::unique_ptr<MetalGaussianBuffer> gaussianBuffer;
    std::unique_ptr<MetalGaussianSortBuffer> sortBuffer;
    core::MeshBounds nextMeshBounds;
    std::string nextLoadedMeshPath;
    std::string completionDiagnostic;
    std::atomic<bool> completed{false};
    std::atomic<bool> succeeded{false};
    std::atomic<uint32_t> convertedCount{0};
    bool updatesScene = false;
    bool revertsSamplesOnFailure = false;
    uint32_t previousSamplesPerTriangle = kDefaultMetalConversionSamplesPerTriangle;
};

struct MetalRenderer::Impl {
    bool submitSceneConversion(
        const MetalSceneResources& conversionSceneResources,
        std::unique_ptr<MetalSceneResources>* nextSceneResources,
        const core::MeshBounds& nextMeshBounds,
        std::string nextLoadedMeshPath,
        bool revertsSamplesOnFailure = false,
        uint32_t previousSamplesPerTriangle = kDefaultMetalConversionSamplesPerTriangle);
    bool submitCurrentSceneConversion(bool revertsSamplesOnFailure = false, uint32_t previousSamplesPerTriangle = 0);
    void finalizePendingConversion();
    void updateDrawableSize(uint32_t width, uint32_t height);
    bool attachDrawableColorTarget(MTLRenderPassDescriptor* descriptor, id<MTLTexture> colorTexture);
    bool ensureDrawableDepthTarget(uint32_t width, uint32_t height);
    bool attachDrawableDepthTarget(MTLRenderPassDescriptor* descriptor, uint32_t width, uint32_t height);
    bool prepareDrawableRenderPassDescriptor(
        MTLRenderPassDescriptor* descriptor,
        id<MTLTexture> colorTexture,
        uint32_t width,
        uint32_t height);
    void markFrameSubmitted(uint32_t frameIndex);
    uint32_t currentGaussianCount() const;
    void recordFrameEncodeFailure(
        Clock::time_point frameCpuStart,
        bool sortedGaussians,
        bool renderedMesh,
        bool renderedGaussians);
    void recordDiagnostic(const std::string& message);
    void transitionTo(mesh2splat::renderer::RendererRuntimeState nextState);
    void markFailed(const std::string& message);
    void markTrackedConversionFailed(const std::string& message);
    mesh2splat::renderer::RendererRuntimeState effectiveRuntimeState() const;
    float currentConversionProgress() const;

    std::unique_ptr<MetalDeviceContext> deviceContext;
    std::shared_ptr<MetalFrameResources> frameResources = std::make_shared<MetalFrameResources>();
    dispatch_semaphore_t frameSemaphore = nil;
    std::shared_ptr<MetalFrameUniformBuffer> frameUniformBuffer;
    std::unique_ptr<MetalShaderLibrary> shaderLibrary;
    std::unique_ptr<MetalPipelineCache> pipelineCache;
    std::unique_ptr<MetalRenderStateCache> renderStateCache;
    std::unique_ptr<MetalSceneResources> sceneResources;
    std::unique_ptr<MetalGaussianBuffer> gaussianBuffer;
    std::unique_ptr<MetalGaussianSortBuffer> gaussianSortBuffer;
    std::shared_ptr<PendingGaussianConversion> pendingConversion;
    std::unique_ptr<MetalConversionPass> conversionPass;
    std::unique_ptr<MetalGaussianRenderPass> gaussianRenderPass;
    std::unique_ptr<MetalGaussianSortPass> gaussianSortPass;
    std::unique_ptr<MetalMeshRenderPass> meshRenderPass;
    std::unique_ptr<MetalRenderTarget> drawableDepthTarget;
    MetalFrameCapture frameCapture;
    core::FrameUniforms frameUniforms;
    core::Matrix4 lastSortedViewMatrix;
    core::CameraController camera;
    mesh2splat::renderer::RendererAssetSession assetSession;
    std::string loadedMeshPath;
    std::string lastDiagnostic;
    std::string lastErrorMessage;
    std::string pendingExportPath;
    RenderViewMode viewMode = RenderViewMode::Combined;
    GaussianVisualizationMode gaussianVisualizationMode = GaussianVisualizationMode::Final;
    mesh2splat::renderer::RendererRuntimeState runtimeState =
        mesh2splat::renderer::RendererRuntimeState::Unknown;
    bool hasSortedGaussianDepths = false;
    bool gaussianSortingEnabled = true;
    bool meshToGaussianConversionEnabled = true;
    bool depthTestEnabled = true;
    bool initialized = false;
    bool renderingFrame = false;
    bool exportPending = false;
    float gaussianScale = 1.0f;
    float exposure = 1.0f;
    float gamma = 2.2f;
    float backgroundBrightness = 0.04f;
    bool lightingEnabled = true;
    float lightPosition[3] = {3.0f, 4.0f, 2.5f};
    float lightIntensity = 1.0f;
    float lightColor[3] = {1.0f, 0.95f, 0.85f};
    uint32_t debugFlags = 0;
    uint32_t conversionSamplesPerTriangle = kDefaultMetalConversionSamplesPerTriangle;
    uint32_t convertedGaussianCount = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    float backingScale = 1.0f;
    std::shared_ptr<MetalRendererTimingState> timingState = std::make_shared<MetalRendererTimingState>();
};

void MetalRenderer::Impl::transitionTo(mesh2splat::renderer::RendererRuntimeState nextState)
{
    runtimeState = nextState;
    if (nextState != mesh2splat::renderer::RendererRuntimeState::Failed) {
        lastErrorMessage.clear();
    }
}

void MetalRenderer::Impl::markFailed(const std::string& message)
{
    runtimeState = mesh2splat::renderer::RendererRuntimeState::Failed;
    lastErrorMessage = message;
    recordDiagnostic(message);
}

void MetalRenderer::Impl::markTrackedConversionFailed(const std::string& message)
{
    if (assetSession.hasScene()) {
        assetSession.conversionFailed(message);
    }
}

mesh2splat::renderer::RendererRuntimeState MetalRenderer::Impl::effectiveRuntimeState() const
{
    if (runtimeState == mesh2splat::renderer::RendererRuntimeState::Failed ||
        runtimeState == mesh2splat::renderer::RendererRuntimeState::Loading ||
        runtimeState == mesh2splat::renderer::RendererRuntimeState::Exporting) {
        return runtimeState;
    }
    if (pendingConversion != nullptr) {
        return mesh2splat::renderer::RendererRuntimeState::Converting;
    }
    if (renderingFrame) {
        return mesh2splat::renderer::RendererRuntimeState::Rendering;
    }
    return initialized
        ? mesh2splat::renderer::RendererRuntimeState::Ready
        : mesh2splat::renderer::RendererRuntimeState::Unknown;
}

float MetalRenderer::Impl::currentConversionProgress() const
{
    std::shared_ptr<PendingGaussianConversion> conversion = pendingConversion;
    if (conversion == nullptr) {
        return convertedGaussianCount == 0 ? 0.0f : kCompletedProgress;
    }
    return conversion->completed.load(std::memory_order_acquire) ? kCompletedProgress : 0.0f;
}

void MetalRenderer::Impl::recordDiagnostic(const std::string& message)
{
    if (message.empty()) {
        return;
    }

    if (lastDiagnostic == message) {
        return;
    }
    if (lastDiagnostic.size() > message.size() &&
        lastDiagnostic.compare(lastDiagnostic.size() - message.size(), message.size(), message) == 0 &&
        lastDiagnostic[lastDiagnostic.size() - message.size() - 1] == '\n') {
        return;
    }

    if (!lastDiagnostic.empty()) {
        lastDiagnostic += "\n";
    }
    lastDiagnostic += message;
    NSLog(@"%s", message.c_str());
}

void MetalRenderer::Impl::updateDrawableSize(uint32_t nextWidth, uint32_t nextHeight)
{
    width = nextWidth;
    height = nextHeight;
    camera.resize(nextWidth, nextHeight);
    frameUniforms.viewport[0] = static_cast<float>(nextWidth);
    frameUniforms.viewport[1] = static_cast<float>(nextHeight);
    frameUniforms.viewport[2] = nextWidth == 0 ? 1.0f : 1.0f / static_cast<float>(nextWidth);
    frameUniforms.viewport[3] = nextHeight == 0 ? 1.0f : 1.0f / static_cast<float>(nextHeight);
}

bool MetalRenderer::Impl::attachDrawableColorTarget(MTLRenderPassDescriptor* descriptor, id<MTLTexture> colorTexture)
{
    if (descriptor == nil) {
        recordDiagnostic("Cannot attach Metal drawable color target: render pass descriptor is nil.");
        return false;
    }
    if (colorTexture == nil) {
        recordDiagnostic("Cannot attach Metal drawable color target: drawable texture is nil.");
        return false;
    }

    MTLRenderPassColorAttachmentDescriptor* colorAttachment = descriptor.colorAttachments[0];
    if (colorAttachment == nil) {
        recordDiagnostic("Cannot attach Metal drawable color target: descriptor has no color attachment.");
        return false;
    }

    colorAttachment.texture = colorTexture;
    if (colorAttachment.loadAction == MTLLoadActionDontCare) {
        colorAttachment.loadAction = MTLLoadActionClear;
    }
    colorAttachment.storeAction = MTLStoreActionStore;
    return true;
}

bool MetalRenderer::Impl::ensureDrawableDepthTarget(uint32_t targetWidth, uint32_t targetHeight)
{
    if (targetWidth == 0 || targetHeight == 0) {
        recordDiagnostic("Cannot prepare Metal drawable depth target: drawable size is zero.");
        return false;
    }
    if (deviceContext == nullptr || !deviceContext->isValid()) {
        recordDiagnostic("Cannot prepare Metal drawable depth target: device context is invalid.");
        return false;
    }

    const MetalRenderTargetDesc desc = makeDrawableDepthTargetDesc(targetWidth, targetHeight);
    if (drawableDepthTarget == nullptr) {
        drawableDepthTarget = std::make_unique<MetalRenderTarget>(*deviceContext);
        if (!drawableDepthTarget->create(desc)) {
            recordDiagnostic(drawableDepthTarget->lastErrorMessage());
            drawableDepthTarget.reset();
            return false;
        }
        return true;
    }

    if (drawableDepthTarget->width() == targetWidth &&
        drawableDepthTarget->height() == targetHeight &&
        drawableDepthTarget->isValid()) {
        return true;
    }

    if (!drawableDepthTarget->resize(desc)) {
        recordDiagnostic(drawableDepthTarget->lastErrorMessage());
        return false;
    }
    return true;
}

bool MetalRenderer::Impl::attachDrawableDepthTarget(
    MTLRenderPassDescriptor* descriptor,
    uint32_t targetWidth,
    uint32_t targetHeight)
{
    if (descriptor == nil) {
        recordDiagnostic("Cannot attach Metal drawable depth target: render pass descriptor is nil.");
        return false;
    }
    if (!ensureDrawableDepthTarget(targetWidth, targetHeight) || drawableDepthTarget == nullptr) {
        return false;
    }

    id<MTLTexture> depthTexture = (__bridge id<MTLTexture>)drawableDepthTarget->depthTexture();
    if (depthTexture == nil) {
        recordDiagnostic("Cannot attach Metal drawable depth target: depth texture is nil.");
        return false;
    }

    MTLRenderPassDepthAttachmentDescriptor* depthAttachment = descriptor.depthAttachment;
    if (depthAttachment == nil) {
        recordDiagnostic("Cannot attach Metal drawable depth target: descriptor has no depth attachment.");
        return false;
    }

    depthAttachment.texture = depthTexture;
    depthAttachment.loadAction = MTLLoadActionClear;
    depthAttachment.storeAction = MTLStoreActionDontCare;
    depthAttachment.clearDepth = drawableDepthTarget->clearDepthValue();
    return true;
}

bool MetalRenderer::Impl::prepareDrawableRenderPassDescriptor(
    MTLRenderPassDescriptor* descriptor,
    id<MTLTexture> colorTexture,
    uint32_t targetWidth,
    uint32_t targetHeight)
{
    return attachDrawableColorTarget(descriptor, colorTexture) &&
        attachDrawableDepthTarget(descriptor, targetWidth, targetHeight);
}

void MetalRenderer::Impl::markFrameSubmitted(uint32_t frameIndex)
{
    if (frameResources != nullptr) {
        frameResources->markFrameSubmitted(frameIndex);
    }
    if (frameUniformBuffer != nullptr) {
        frameUniformBuffer->markFrameSubmitted(frameIndex);
    }
}

uint32_t MetalRenderer::Impl::currentGaussianCount() const
{
    return gaussianBuffer == nullptr ? 0 : gaussianBuffer->count();
}

void MetalRenderer::Impl::recordFrameEncodeFailure(
    Clock::time_point frameCpuStart,
    bool sortedGaussians,
    bool renderedMesh,
    bool renderedGaussians)
{
    if (timingState == nullptr) {
        return;
    }

    timingState->recordFrameEncodeFailed(
        elapsedMilliseconds(frameCpuStart, Clock::now()),
        currentGaussianCount(),
        sortedGaussians,
        renderedMesh,
        renderedGaussians);
}

bool MetalRenderer::Impl::submitSceneConversion(
    const MetalSceneResources& conversionSceneResources,
    std::unique_ptr<MetalSceneResources>* nextSceneResources,
    const core::MeshBounds& nextMeshBounds,
    std::string nextLoadedMeshPath,
    bool revertsSamplesOnFailure,
    uint32_t previousSamplesPerTriangle)
{
    if (deviceContext == nullptr || !deviceContext->isValid()) {
        markFailed("Cannot submit Metal mesh conversion: device context is invalid.");
        markTrackedConversionFailed("Cannot submit Metal mesh conversion: device context is invalid.");
        return false;
    }
    if (conversionPass == nullptr || !conversionPass->isReady()) {
        recordDiagnostic("Cannot submit Metal mesh conversion: conversion pass is not ready.");
        markTrackedConversionFailed("Cannot submit Metal mesh conversion: conversion pass is not ready.");
        return false;
    }
    if (!conversionSceneResources.isValid()) {
        recordDiagnostic("Cannot submit Metal mesh conversion: scene resources are invalid.");
        markTrackedConversionFailed("Cannot submit Metal mesh conversion: scene resources are invalid.");
        return false;
    }
    if (!core::gaussianCountFitsBuffer(conversionSceneResources.totalVertexCount())) {
        recordDiagnostic("Cannot submit Metal mesh conversion: scene vertex count exceeds gaussian buffer limits.");
        markTrackedConversionFailed("Cannot submit Metal mesh conversion: scene vertex count exceeds gaussian buffer limits.");
        return false;
    }

    const Clock::time_point conversionCpuStart = Clock::now();
    const std::size_t gaussianCapacity =
        conversionSceneResources.conversionCapacity(conversionSamplesPerTriangle);
    if (gaussianCapacity == 0) {
        recordDiagnostic("Cannot submit Metal mesh conversion: planned gaussian capacity is zero.");
        markTrackedConversionFailed("Cannot submit Metal mesh conversion: planned gaussian capacity is zero.");
        return false;
    }

    if (!core::gaussianCountFitsBuffer(gaussianCapacity)) {
        recordDiagnostic("Cannot submit Metal mesh conversion: planned gaussian capacity exceeds buffer limits.");
        markTrackedConversionFailed("Cannot submit Metal mesh conversion: planned gaussian capacity exceeds buffer limits.");
        return false;
    }

    auto nextConversion = std::make_shared<PendingGaussianConversion>();
    nextConversion->nextMeshBounds = nextMeshBounds;
    nextConversion->nextLoadedMeshPath = std::move(nextLoadedMeshPath);
    nextConversion->updatesScene = nextSceneResources != nullptr && *nextSceneResources != nullptr;
    nextConversion->revertsSamplesOnFailure = revertsSamplesOnFailure;
    nextConversion->previousSamplesPerTriangle = previousSamplesPerTriangle;
    nextConversion->gaussianBuffer = std::make_unique<MetalGaussianBuffer>(*deviceContext);
    if (!nextConversion->gaussianBuffer->create(gaussianCapacity, "Mesh2Splat Converted Gaussians")) {
        recordDiagnostic("Cannot submit Metal mesh conversion: failed to allocate gaussian output buffers.");
        markTrackedConversionFailed("Cannot submit Metal mesh conversion: failed to allocate gaussian output buffers.");
        return false;
    }

    nextConversion->sortBuffer = std::make_unique<MetalGaussianSortBuffer>(*deviceContext);
    if (!nextConversion->sortBuffer->create(gaussianCapacity, "Mesh2Splat Gaussian Sort")) {
        recordDiagnostic("Cannot submit Metal mesh conversion: failed to allocate gaussian sort buffers.");
        markTrackedConversionFailed("Cannot submit Metal mesh conversion: failed to allocate gaussian sort buffers.");
        return false;
    }

    MetalCommandScheduler commandScheduler(deviceContext->nativeCommandQueue());
    id<MTLCommandBuffer> commandBuffer =
        (__bridge id<MTLCommandBuffer>)commandScheduler.createCommandBuffer("Mesh2Splat Mesh Conversion");
    if (commandBuffer == nil) {
        recordDiagnostic("Cannot submit Metal mesh conversion: failed to create command buffer.");
        markTrackedConversionFailed("Cannot submit Metal mesh conversion: failed to create command buffer.");
        return false;
    }

    std::string conversionError;
    if (!conversionPass->encode(
            (__bridge void*)commandBuffer,
            conversionSceneResources,
            *nextConversion->gaussianBuffer,
            conversionSamplesPerTriangle,
            &conversionError)) {
        recordDiagnostic(
            conversionError.empty()
                ? "Cannot submit Metal mesh conversion: failed to encode conversion pass."
                : "Cannot submit Metal mesh conversion: " + conversionError);
        markTrackedConversionFailed(
            conversionError.empty()
                ? "Cannot submit Metal mesh conversion: failed to encode conversion pass."
                : "Cannot submit Metal mesh conversion: " + conversionError);
        return false;
    }

    if (nextConversion->updatesScene) {
        nextConversion->nextSceneResources = std::move(*nextSceneResources);
    }
    std::shared_ptr<MetalRendererTimingState> conversionTimingState = timingState;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> completedCommandBuffer) {
        bool didSucceed = true;
        if (completedCommandBuffer.status != MTLCommandBufferStatusCompleted) {
            didSucceed = false;
            nextConversion->completionDiagnostic =
                "Metal mesh conversion command finished with status " +
                commandBufferStatusDescription(completedCommandBuffer.status);
            const std::string commandError = commandBufferErrorDescription(completedCommandBuffer);
            if (!commandError.empty()) {
                nextConversion->completionDiagnostic += ": " + commandError;
            }
        } else if (nextConversion->gaussianBuffer == nullptr) {
            didSucceed = false;
            nextConversion->completionDiagnostic =
                "Metal mesh conversion completed without a gaussian output buffer.";
        } else if (!nextConversion->gaussianBuffer->readGpuCounter()) {
            didSucceed = false;
            nextConversion->completionDiagnostic =
                "Metal mesh conversion completed but the gaussian counter could not be read back.";
        }

        const uint32_t nextConvertedCount =
            didSucceed && nextConversion->gaussianBuffer != nullptr ? nextConversion->gaussianBuffer->count() : 0;
        if (didSucceed && nextConvertedCount == 0) {
            didSucceed = false;
            nextConversion->completionDiagnostic =
                "Metal mesh conversion completed but produced zero gaussians.";
        } else if (didSucceed && nextConversion->sortBuffer == nullptr) {
            didSucceed = false;
            nextConversion->completionDiagnostic =
                "Metal mesh conversion completed without gaussian sort buffers.";
        } else if (didSucceed && nextConvertedCount > nextConversion->sortBuffer->capacity()) {
            didSucceed = false;
            nextConversion->completionDiagnostic =
                "Metal mesh conversion output exceeds gaussian sort buffer capacity.";
        }

        nextConversion->convertedCount.store(nextConvertedCount, std::memory_order_relaxed);
        nextConversion->succeeded.store(didSucceed, std::memory_order_relaxed);
        if (conversionTimingState != nullptr) {
            conversionTimingState->recordConversionCompleted(
                didSucceed,
                commandBufferGpuMilliseconds(completedCommandBuffer));
        }
        nextConversion->completed.store(true, std::memory_order_release);
    }];

    if (!commandScheduler.commit((__bridge void*)commandBuffer)) {
        if (nextConversion->updatesScene && nextSceneResources != nullptr) {
            *nextSceneResources = std::move(nextConversion->nextSceneResources);
        }
        recordDiagnostic("Cannot submit Metal mesh conversion: failed to commit command buffer.");
        markTrackedConversionFailed("Cannot submit Metal mesh conversion: failed to commit command buffer.");
        return false;
    }

    if (timingState != nullptr) {
        timingState->recordConversionSubmitted(elapsedMilliseconds(conversionCpuStart, Clock::now()));
    }
    pendingConversion = nextConversion;
    if (assetSession.hasScene()) {
        assetSession.conversionSubmitted();
        assetSession.conversionRunning();
    }
    transitionTo(mesh2splat::renderer::RendererRuntimeState::Converting);
    return true;
}

bool MetalRenderer::Impl::submitCurrentSceneConversion(bool revertsSamplesOnFailure, uint32_t previousSamplesPerTriangle)
{
    if (sceneResources == nullptr || !sceneResources->isValid()) {
        return false;
    }

    return submitSceneConversion(
        *sceneResources,
        nullptr,
        core::MeshBounds{},
        std::string{},
        revertsSamplesOnFailure,
        previousSamplesPerTriangle);
}

void MetalRenderer::Impl::finalizePendingConversion()
{
    std::shared_ptr<PendingGaussianConversion> conversion = pendingConversion;
    if (conversion == nullptr || !conversion->completed.load(std::memory_order_acquire)) {
        return;
    }

    pendingConversion.reset();
    if (!conversion->succeeded.load(std::memory_order_acquire)) {
        if (conversion->revertsSamplesOnFailure) {
            conversionSamplesPerTriangle = conversion->previousSamplesPerTriangle;
        }
        markFailed(
            conversion->completionDiagnostic.empty()
                ? "Metal mesh conversion command did not produce gaussians."
                : conversion->completionDiagnostic);
        markTrackedConversionFailed(
            conversion->completionDiagnostic.empty()
                ? "Metal mesh conversion command did not produce gaussians."
                : conversion->completionDiagnostic);
        return;
    }

    if (conversion->updatesScene && conversion->nextSceneResources != nullptr) {
        sceneResources = std::move(conversion->nextSceneResources);
        camera.frameBounds(conversion->nextMeshBounds);
        loadedMeshPath = std::move(conversion->nextLoadedMeshPath);
    }

    convertedGaussianCount = conversion->convertedCount.load(std::memory_order_relaxed);
    gaussianBuffer = std::move(conversion->gaussianBuffer);
    gaussianSortBuffer = std::move(conversion->sortBuffer);
    if (assetSession.hasScene()) {
        assetSession.conversionCompleted(convertedGaussianCount > 0);
    }
    hasSortedGaussianDepths = false;
    transitionTo(mesh2splat::renderer::RendererRuntimeState::Ready);
}

MetalRenderer::MetalRenderer(void* metalDevice)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = std::make_unique<MetalDeviceContext>(metalDevice);
}

MetalRenderer::~MetalRenderer() = default;

bool MetalRenderer::initialize()
{
    if (m_impl->deviceContext == nullptr) {
        m_impl->lastDiagnostic = "Metal renderer has no device context.";
        m_impl->lastErrorMessage = m_impl->lastDiagnostic;
        m_impl->runtimeState = mesh2splat::renderer::RendererRuntimeState::Failed;
        return false;
    }

    m_impl->lastDiagnostic.clear();
    m_impl->lastErrorMessage.clear();
    m_impl->transitionTo(mesh2splat::renderer::RendererRuntimeState::Loading);
    auto appendRendererDiagnostic = [this](const std::string& message) {
        if (message.empty()) {
            return;
        }

        if (!m_impl->lastDiagnostic.empty()) {
            m_impl->lastDiagnostic += "\n";
        }
        m_impl->lastDiagnostic += message;
        NSLog(@"%s", message.c_str());
    };

    if (!m_impl->deviceContext->initialize()) {
        appendRendererDiagnostic("Failed to initialize Metal device context.");
        m_impl->markFailed("Failed to initialize Metal device context.");
        return false;
    }

    MetalFrameCaptureRequest frameCaptureRequest = captureRequestFromEnvironment();
    if (frameCaptureRequest.requested) {
        appendRendererDiagnostic(captureRequestDescription(frameCaptureRequest));
        m_impl->frameCapture.setRequest(std::move(frameCaptureRequest));
    }

    m_impl->frameSemaphore = dispatch_semaphore_create(m_impl->frameResources->frameCount());
    if (m_impl->frameSemaphore == nil) {
        appendRendererDiagnostic("Failed to create Metal frame semaphore.");
        m_impl->markFailed("Failed to create Metal frame semaphore.");
        return false;
    }

    m_impl->frameUniformBuffer = std::make_shared<MetalFrameUniformBuffer>(*m_impl->deviceContext);
    if (!m_impl->frameUniformBuffer->initialize("Mesh2Splat Frame Uniforms")) {
        appendRendererDiagnostic("Failed to initialize Metal frame uniform buffers.");
        m_impl->markFailed("Failed to initialize Metal frame uniform buffers.");
        return false;
    }

    m_impl->frameResources->setDebugLabel("Mesh2Splat Frame Resources");
    m_impl->renderStateCache = std::make_unique<MetalRenderStateCache>(*m_impl->deviceContext);
    m_impl->pipelineCache = std::make_unique<MetalPipelineCache>(*m_impl->deviceContext);
    m_impl->shaderLibrary = std::make_unique<MetalShaderLibrary>(*m_impl->deviceContext);
    m_impl->sceneResources = std::make_unique<MetalSceneResources>(*m_impl->deviceContext);
    m_impl->drawableDepthTarget = std::make_unique<MetalRenderTarget>(*m_impl->deviceContext);

    std::vector<core::MeshData> previewMeshes;
    previewMeshes.push_back(core::createPreviewTriangleMesh());
    if (!m_impl->sceneResources->uploadMeshes(previewMeshes)) {
        appendRendererDiagnostic("Failed to upload Metal preview mesh resources.");
    }

    std::string shaderDiagnostic;
    if (loadRendererShaderLibrary(*m_impl->shaderLibrary, &shaderDiagnostic)) {
        appendRendererDiagnostic(shaderDiagnostic);
        m_impl->conversionPass = std::make_unique<MetalConversionPass>();
        std::string passError;
        if (!m_impl->conversionPass->initialize(
                *m_impl->shaderLibrary,
                *m_impl->pipelineCache,
                *m_impl->renderStateCache,
                &passError)) {
            appendRendererDiagnostic(passError);
            m_impl->conversionPass.reset();
        } else if (!m_impl->submitCurrentSceneConversion()) {
            appendRendererDiagnostic("Initial Metal mesh conversion could not be submitted.");
        }

        m_impl->gaussianRenderPass = std::make_unique<MetalGaussianRenderPass>(*m_impl->deviceContext);
        passError.clear();
        if (!m_impl->gaussianRenderPass->initialize(
                *m_impl->shaderLibrary,
                *m_impl->pipelineCache,
                *m_impl->renderStateCache,
                MetalTextureFormat::BGRA8Unorm,
                MetalTextureFormat::Depth32Float,
                &passError)) {
            appendRendererDiagnostic(passError);
            m_impl->gaussianRenderPass.reset();
        }

        m_impl->gaussianSortPass = std::make_unique<MetalGaussianSortPass>();
        passError.clear();
        if (!m_impl->gaussianSortPass->initialize(*m_impl->shaderLibrary, *m_impl->pipelineCache, &passError)) {
            appendRendererDiagnostic(passError);
            m_impl->gaussianSortPass.reset();
        }

        m_impl->meshRenderPass = std::make_unique<MetalMeshRenderPass>(*m_impl->deviceContext);
        passError.clear();
        if (!m_impl->meshRenderPass->initialize(
                *m_impl->shaderLibrary,
                *m_impl->pipelineCache,
                *m_impl->renderStateCache,
                MetalTextureFormat::BGRA8Unorm,
                MetalTextureFormat::Depth32Float,
                &passError)) {
            appendRendererDiagnostic(passError);
            m_impl->meshRenderPass.reset();
        }
    } else {
        appendRendererDiagnostic(shaderDiagnostic);
    }

    m_impl->frameUniforms = core::makeDefaultFrameUniforms(m_impl->width, m_impl->height);
    m_impl->updateDrawableSize(m_impl->width, m_impl->height);
    m_impl->initialized = true;
    if (m_impl->runtimeState != mesh2splat::renderer::RendererRuntimeState::Failed) {
        m_impl->transitionTo(
            m_impl->pendingConversion == nullptr
                ? mesh2splat::renderer::RendererRuntimeState::Ready
                : mesh2splat::renderer::RendererRuntimeState::Converting);
    }
    return true;
}

bool MetalRenderer::loadMeshFile(const std::string& filePath)
{
    if (!filePath.empty()) {
        m_impl->assetSession.importStarted(filePath);
    }
    if (m_impl->deviceContext == nullptr || !m_impl->deviceContext->isValid() || filePath.empty()) {
        const std::string message = filePath.empty()
            ? "Cannot load Metal scene: mesh file path is empty."
            : "Cannot load Metal scene: device context is invalid.";
        m_impl->assetSession.importFailed(message);
        m_impl->markFailed(message);
        return false;
    }

    m_impl->transitionTo(mesh2splat::renderer::RendererRuntimeState::Loading);
    io::GltfSceneLoadResult loadResult;
    if (!io::loadGltfScene(filePath, loadResult)) {
        const std::string message =
            loadResult.error.empty()
                ? "Failed to load mesh: " + filePath
                : "Failed to load mesh: " + loadResult.error;
        m_impl->assetSession.importFailed(message);
        m_impl->markFailed(message);
        return false;
    }

    auto nextSceneResources = std::make_unique<MetalSceneResources>(*m_impl->deviceContext);
    if (!nextSceneResources->uploadMeshes(loadResult.scene.meshes)) {
        const std::string message = "Failed to upload mesh resources: " + filePath;
        m_impl->assetSession.importFailed(message);
        m_impl->markFailed(message);
        return false;
    }

    if (!loadResult.warning.empty()) {
        m_impl->recordDiagnostic("glTF load warning: " + loadResult.warning);
    }

    const core::MeshBounds meshBounds = loadResult.scene.bounds;
    m_impl->assetSession.importSucceeded(filePath);
    auto installSceneWithoutGaussians = [&](std::string diagnostic) {
        m_impl->pendingConversion.reset();
        m_impl->sceneResources = std::move(nextSceneResources);
        m_impl->camera.frameBounds(meshBounds);
        m_impl->loadedMeshPath = filePath;
        m_impl->gaussianBuffer.reset();
        m_impl->gaussianSortBuffer.reset();
        m_impl->convertedGaussianCount = 0;
        m_impl->hasSortedGaussianDepths = false;
        if (!diagnostic.empty()) {
            m_impl->recordDiagnostic(diagnostic);
        }
        m_impl->transitionTo(mesh2splat::renderer::RendererRuntimeState::Ready);
    };

    if (!m_impl->meshToGaussianConversionEnabled) {
        installSceneWithoutGaussians("Metal mesh conversion is disabled; loaded mesh without gaussian conversion.");
        m_impl->assetSession.conversionCancelled();
        return true;
    }

    if (!m_impl->submitSceneConversion(
            *nextSceneResources,
            &nextSceneResources,
            meshBounds,
            filePath)) {
        NSLog(@"Metal mesh conversion could not be submitted: %s", filePath.c_str());
        installSceneWithoutGaussians("Metal mesh conversion could not be submitted.");
        m_impl->assetSession.conversionFailed("Metal mesh conversion could not be submitted.");
    }
    return true;
}

void MetalRenderer::resize(const mesh2splat::renderer::RendererResizeRequest& request)
{
    m_impl->backingScale = request.backingScale > 0.0f ? request.backingScale : 1.0f;
    resize(request.width, request.height);
}

void MetalRenderer::resize(uint32_t width, uint32_t height)
{
    m_impl->updateDrawableSize(width, height);
    if (m_impl->deviceContext != nullptr && m_impl->deviceContext->isValid() && width > 0 && height > 0) {
        m_impl->ensureDrawableDepthTarget(width, height);
    }
}

void MetalRenderer::setViewMode(RenderViewMode mode)
{
    m_impl->viewMode = mode;
}

RenderViewMode MetalRenderer::viewMode() const
{
    return m_impl->viewMode;
}

void MetalRenderer::setGaussianVisualizationMode(GaussianVisualizationMode mode)
{
    m_impl->gaussianVisualizationMode = mode;
}

GaussianVisualizationMode MetalRenderer::gaussianVisualizationMode() const
{
    return m_impl->gaussianVisualizationMode;
}

void MetalRenderer::setGaussianScale(float scale)
{
    m_impl->gaussianScale = std::clamp(scale, 0.1f, 8.0f);
}

float MetalRenderer::gaussianScale() const
{
    return m_impl->gaussianScale;
}

bool MetalRenderer::setConversionSamplesPerTriangle(uint32_t samplesPerTriangle)
{
    const uint32_t normalizedSamples = normalizedConversionSamples(samplesPerTriangle);
    if (m_impl->conversionSamplesPerTriangle == normalizedSamples) {
        return true;
    }

    if (!m_impl->meshToGaussianConversionEnabled) {
        m_impl->conversionSamplesPerTriangle = normalizedSamples;
        m_impl->recordDiagnostic("Metal mesh conversion is disabled; stored conversion quality without rebuilding.");
        return true;
    }

    if (isConvertingGaussians()) {
        m_impl->recordDiagnostic("Cannot change Metal conversion quality while conversion is running.");
        return false;
    }

    const uint32_t previousSamples = m_impl->conversionSamplesPerTriangle;
    m_impl->conversionSamplesPerTriangle = normalizedSamples;
    if (m_impl->sceneResources != nullptr && m_impl->sceneResources->isValid() &&
        !m_impl->submitCurrentSceneConversion(true, previousSamples)) {
        m_impl->conversionSamplesPerTriangle = previousSamples;
        NSLog(@"Metal mesh reconversion could not be submitted.");
        return false;
    }

    return true;
}

uint32_t MetalRenderer::conversionSamplesPerTriangle() const
{
    return m_impl->conversionSamplesPerTriangle;
}

bool MetalRenderer::isConvertingGaussians() const
{
    return m_impl->pendingConversion != nullptr;
}

uint32_t MetalRenderer::convertedGaussianCount() const
{
    return m_impl->convertedGaussianCount;
}

MetalRendererStats MetalRenderer::rendererStats() const
{
    MetalRendererStats stats =
        m_impl->timingState == nullptr ? MetalRendererStats{} : m_impl->timingState->snapshot();
    stats.frameUniformResourceBytes =
        toResourceBytes(m_impl->frameUniformBuffer == nullptr ? 0 : m_impl->frameUniformBuffer->sizeBytes());
    stats.sceneResourceBytes =
        toResourceBytes(m_impl->sceneResources == nullptr ? 0 : m_impl->sceneResources->sizeBytes());
    stats.gaussianResourceBytes =
        toResourceBytes(m_impl->gaussianBuffer == nullptr ? 0 : m_impl->gaussianBuffer->totalSizeBytes());
    stats.gaussianSortResourceBytes =
        toResourceBytes(m_impl->gaussianSortBuffer == nullptr ? 0 : m_impl->gaussianSortBuffer->sizeBytes());
    const uint64_t renderTargetResourceBytes =
        toResourceBytes(m_impl->drawableDepthTarget == nullptr ? 0 : m_impl->drawableDepthTarget->sizeBytes());

    uint64_t pendingResourceBytes = 0;
    std::shared_ptr<PendingGaussianConversion> pendingConversion = m_impl->pendingConversion;
    if (pendingConversion != nullptr) {
        addResourceBytes(
            pendingResourceBytes,
            toResourceBytes(
                pendingConversion->nextSceneResources == nullptr
                    ? 0
                    : pendingConversion->nextSceneResources->sizeBytes()));
        addResourceBytes(
            pendingResourceBytes,
            toResourceBytes(
                pendingConversion->gaussianBuffer == nullptr
                    ? 0
                    : pendingConversion->gaussianBuffer->totalSizeBytes()));
        addResourceBytes(
            pendingResourceBytes,
            toResourceBytes(
                pendingConversion->sortBuffer == nullptr
                    ? 0
                    : pendingConversion->sortBuffer->sizeBytes()));
    }
    stats.pendingConversionResourceBytes = pendingResourceBytes;

    uint64_t totalResourceBytes = 0;
    addResourceBytes(totalResourceBytes, stats.frameUniformResourceBytes);
    addResourceBytes(totalResourceBytes, stats.sceneResourceBytes);
    addResourceBytes(totalResourceBytes, stats.gaussianResourceBytes);
    addResourceBytes(totalResourceBytes, stats.gaussianSortResourceBytes);
    addResourceBytes(totalResourceBytes, renderTargetResourceBytes);
    addResourceBytes(totalResourceBytes, stats.pendingConversionResourceBytes);
    stats.trackedResourceBytes = totalResourceBytes;
    return stats;
}

const std::string& MetalRenderer::lastDiagnostic() const
{
    return m_impl->lastDiagnostic;
}

const std::string& MetalRenderer::loadedMeshPath() const
{
    return m_impl->loadedMeshPath;
}

mesh2splat::renderer::RendererLoadedSceneSnapshot MetalRenderer::loadedSceneSnapshot() const
{
    const mesh2splat::renderer::RendererAssetSessionSnapshot session = m_impl->assetSession.snapshot();
    mesh2splat::renderer::RendererLoadedSceneSnapshot loadedScene;
    loadedScene.loaded = session.hasScene || !m_impl->loadedMeshPath.empty();
    loadedScene.kind = mesh2splat::renderer::RendererSceneKind::Mesh;
    loadedScene.filePath = session.sourcePath.empty() ? m_impl->loadedMeshPath : session.sourcePath;
    loadedScene.displayName = session.displayName.empty()
        ? mesh2splat::renderer::Renderer::rendererDisplayNameFromPath(loadedScene.filePath)
        : session.displayName;
    loadedScene.revision = session.loadSerial;
    return loadedScene;
}

mesh2splat::renderer::RendererSceneLoadResult MetalRenderer::loadScene(
    const mesh2splat::renderer::RendererSceneLoadRequest& request)
{
    mesh2splat::renderer::RendererSceneLoadResult result;
    result.accepted = !request.filePath.empty();
    if (!result.accepted) {
        result.diagnostic = "Scene file path is empty.";
        m_impl->markFailed(result.diagnostic);
        return result;
    }
    if (!request.replaceCurrentScene) {
        result.diagnostic = "Metal renderer only supports replacing the current scene.";
        m_impl->recordDiagnostic(result.diagnostic);
        return result;
    }
    if (!sceneKindCanLoadAsMesh(request.kind, request.filePath)) {
        result.accepted = false;
        result.diagnostic = "Metal renderer scene loading currently supports .glb/.gltf meshes only.";
        m_impl->recordDiagnostic(result.diagnostic);
        return result;
    }

    result.loaded = loadMeshFile(request.filePath);
    result.diagnostic = lastDiagnostic();
    return result;
}

mesh2splat::renderer::RendererConversionResult MetalRenderer::startConversion(
    const mesh2splat::renderer::RendererConversionRequest& request)
{
    mesh2splat::renderer::RendererConversionResult result;
    result.samplesPerTriangle = conversionSamplesPerTriangle();
    result.convertedGaussianCount = convertedGaussianCount();
    if (!m_impl->meshToGaussianConversionEnabled) {
        result.diagnostic = "Metal mesh conversion is disabled.";
        m_impl->recordDiagnostic(result.diagnostic);
        return result;
    }
    if (isConvertingGaussians()) {
        result.diagnostic = "Renderer is already converting gaussians.";
        return result;
    }
    if (m_impl->sceneResources == nullptr || !m_impl->sceneResources->isValid()) {
        result.diagnostic = "Cannot start Metal mesh conversion: no valid scene resources are loaded.";
        m_impl->recordDiagnostic(result.diagnostic);
        return result;
    }

    const uint32_t previousSamples = m_impl->conversionSamplesPerTriangle;
    const uint32_t requestedSamples =
        request.samplesPerTriangle == 0
            ? previousSamples
            : normalizedConversionSamples(request.samplesPerTriangle);
    result.accepted = true;
    if (requestedSamples != previousSamples) {
        m_impl->conversionSamplesPerTriangle = requestedSamples;
    }

    result.started = m_impl->submitCurrentSceneConversion(requestedSamples != previousSamples, previousSamples);
    if (!result.started && requestedSamples != previousSamples) {
        m_impl->conversionSamplesPerTriangle = previousSamples;
    }
    if (!result.started && request.forceRebuild) {
        m_impl->recordDiagnostic("Metal mesh conversion rebuild could not be submitted.");
    }
    result.samplesPerTriangle = conversionSamplesPerTriangle();
    result.convertedGaussianCount = convertedGaussianCount();
    result.diagnostic = lastDiagnostic();
    return result;
}

mesh2splat::renderer::RendererModeResult MetalRenderer::setRenderMode(
    const mesh2splat::renderer::RendererModeRequest& request)
{
    const bool sortingChanged = m_impl->gaussianSortingEnabled != request.gaussianSortingEnabled;
    setViewMode(request.viewMode);
    setGaussianVisualizationMode(request.gaussianVisualizationMode);
    setGaussianScale(request.gaussianScale);
    m_impl->exposure = clampedFinite(request.exposure, 0.0f, 16.0f, 1.0f);
    m_impl->gamma = clampedFinite(request.gamma, 0.1f, 4.0f, 2.2f);
    m_impl->backgroundBrightness = clampedFinite(request.backgroundBrightness, 0.0f, 1.0f, 0.04f);
    m_impl->depthTestEnabled = request.depthTestEnabled;
    m_impl->lightingEnabled = request.lightingEnabled;
    m_impl->lightPosition[0] = clampedFinite(request.lightPosition[0], -100.0f, 100.0f, 3.0f);
    m_impl->lightPosition[1] = clampedFinite(request.lightPosition[1], -100.0f, 100.0f, 4.0f);
    m_impl->lightPosition[2] = clampedFinite(request.lightPosition[2], -100.0f, 100.0f, 2.5f);
    m_impl->lightIntensity = clampedFinite(request.lightIntensity, 0.0f, 1000.0f, 1.0f);
    m_impl->lightColor[0] = clampedFinite(request.lightColor[0], 0.0f, 4.0f, 1.0f);
    m_impl->lightColor[1] = clampedFinite(request.lightColor[1], 0.0f, 4.0f, 0.95f);
    m_impl->lightColor[2] = clampedFinite(request.lightColor[2], 0.0f, 4.0f, 0.85f);
    m_impl->debugFlags = request.debugFlags & core::kKnownRenderDebugFlags;
    m_impl->gaussianSortingEnabled = request.gaussianSortingEnabled;
    m_impl->meshToGaussianConversionEnabled = request.meshToGaussianConversionEnabled;
    if (sortingChanged) {
        m_impl->hasSortedGaussianDepths = false;
    }

    mesh2splat::renderer::RendererModeResult result;
    result.requestId = request.requestId;
    result.applied = true;
    result.viewMode = viewMode();
    result.gaussianVisualizationMode = gaussianVisualizationMode();
    result.gaussianScale = gaussianScale();
    result.exposure = m_impl->exposure;
    result.gamma = m_impl->gamma;
    result.backgroundBrightness = m_impl->backgroundBrightness;
    result.depthTestEnabled = m_impl->depthTestEnabled;
    result.lightingEnabled = m_impl->lightingEnabled;
    result.lightPosition[0] = m_impl->lightPosition[0];
    result.lightPosition[1] = m_impl->lightPosition[1];
    result.lightPosition[2] = m_impl->lightPosition[2];
    result.lightIntensity = m_impl->lightIntensity;
    result.lightColor[0] = m_impl->lightColor[0];
    result.lightColor[1] = m_impl->lightColor[1];
    result.lightColor[2] = m_impl->lightColor[2];
    result.debugFlags = m_impl->debugFlags;
    result.gaussianSortingEnabled = m_impl->gaussianSortingEnabled;
    result.meshToGaussianConversionEnabled = m_impl->meshToGaussianConversionEnabled;
    result.diagnostic = lastDiagnostic();
    return result;
}

mesh2splat::renderer::RendererExportPlyResult MetalRenderer::exportPly(
    const mesh2splat::renderer::RendererExportPlyRequest& request)
{
    mesh2splat::renderer::RendererExportPlyResult result;
    result.accepted = !request.filePath.empty();
    result.requestedCount = convertedGaussianCount();
    if (!result.accepted) {
        result.diagnostic = "PLY export file path is empty.";
        m_impl->recordDiagnostic(result.diagnostic);
        return result;
    }
    if (isConvertingGaussians()) {
        result.diagnostic = "PLY export is waiting for Metal mesh conversion to finish.";
        m_impl->recordDiagnostic(result.diagnostic);
        return result;
    }
    if (m_impl->gaussianBuffer == nullptr || m_impl->gaussianBuffer->count() == 0) {
        result.diagnostic = "PLY export requires converted gaussians.";
        m_impl->recordDiagnostic(result.diagnostic);
        return result;
    }

    m_impl->transitionTo(mesh2splat::renderer::RendererRuntimeState::Exporting);
    m_impl->assetSession.exportStarted(request.filePath);
    std::vector<core::GaussianRecord> gaussians;
    if (!m_impl->gaussianBuffer->readback(gaussians)) {
        result.diagnostic = m_impl->gaussianBuffer->lastErrorMessage().empty()
            ? "PLY export failed: Metal gaussian readback did not complete."
            : "PLY export failed: " + m_impl->gaussianBuffer->lastErrorMessage();
        m_impl->recordDiagnostic(result.diagnostic);
        m_impl->assetSession.exportFailed(result.diagnostic);
        m_impl->transitionTo(mesh2splat::renderer::RendererRuntimeState::Ready);
        return result;
    }

    io::GaussianPlyWriteOptions writeOptions;
    writeOptions.format = static_cast<io::GaussianPlyFormat>(request.format);
    writeOptions.scaleMultiplier = request.scaleMultiplier;
    writeOptions.skipInvalidRecords = request.skipInvalidRecords;

    io::GaussianPlyWriteResult writeResult;
    result.requestedCount = gaussians.size();
    result.exported = io::writeGaussianPly(request.filePath, gaussians, writeOptions, &writeResult);
    result.writtenCount = writeResult.writtenCount;
    if (result.exported) {
        result.diagnostic =
            "Exported " + std::to_string(writeResult.writtenCount) +
            " Metal gaussians to PLY: " + request.filePath;
        if (!writeResult.warning.empty()) {
            result.diagnostic += "\n" + writeResult.warning;
        }
    } else {
        result.diagnostic = writeResult.error.empty()
            ? "PLY export failed while writing output."
            : "PLY export failed: " + writeResult.error;
    }
    m_impl->recordDiagnostic(result.diagnostic);
    if (result.exported) {
        m_impl->assetSession.exportSucceeded(request.filePath);
    } else {
        m_impl->assetSession.exportFailed(result.diagnostic);
    }
    m_impl->transitionTo(mesh2splat::renderer::RendererRuntimeState::Ready);
    return result;
}

mesh2splat::renderer::RendererRenderSettingsSummary MetalRenderer::renderSettingsSummary() const
{
    mesh2splat::renderer::RendererRenderSettingsSummary settings;
    settings.drawableWidth = m_impl->width;
    settings.drawableHeight = m_impl->height;
    settings.backingScale = m_impl->backingScale;
    settings.viewMode = viewMode();
    settings.gaussianVisualizationMode = gaussianVisualizationMode();
    settings.gaussianScale = gaussianScale();
    settings.exposure = m_impl->exposure;
    settings.gamma = m_impl->gamma;
    settings.backgroundBrightness = m_impl->backgroundBrightness;
    settings.depthTestEnabled = m_impl->depthTestEnabled;
    settings.lightingEnabled = m_impl->lightingEnabled;
    settings.lightPosition[0] = m_impl->lightPosition[0];
    settings.lightPosition[1] = m_impl->lightPosition[1];
    settings.lightPosition[2] = m_impl->lightPosition[2];
    settings.lightIntensity = m_impl->lightIntensity;
    settings.lightColor[0] = m_impl->lightColor[0];
    settings.lightColor[1] = m_impl->lightColor[1];
    settings.lightColor[2] = m_impl->lightColor[2];
    settings.debugFlags = m_impl->debugFlags;
    settings.conversionSamplesPerTriangle = conversionSamplesPerTriangle();
    settings.meshRenderingEnabled = settings.viewMode != RenderViewMode::GaussianOnly;
    settings.gaussianRenderingEnabled = settings.viewMode != RenderViewMode::MeshOnly;
    settings.gaussianSortingEnabled = m_impl->gaussianSortingEnabled;
    settings.meshToGaussianConversionEnabled = m_impl->meshToGaussianConversionEnabled;
    return settings;
}

bool MetalRenderer::handleInputEvent(const mesh2splat::renderer::RendererInputEvent& event)
{
    switch (event.type) {
    case mesh2splat::renderer::RendererInputEventType::Resize:
        m_impl->backingScale = event.backingScale > 0.0f ? event.backingScale : 1.0f;
        resize(event.width, event.height);
        return true;
    case mesh2splat::renderer::RendererInputEventType::FrameTick:
        return true;
    case mesh2splat::renderer::RendererInputEventType::Unknown:
    case mesh2splat::renderer::RendererInputEventType::Key:
    case mesh2splat::renderer::RendererInputEventType::MouseButton:
    case mesh2splat::renderer::RendererInputEventType::MouseMove:
    case mesh2splat::renderer::RendererInputEventType::MouseScroll:
    case mesh2splat::renderer::RendererInputEventType::Text:
    case mesh2splat::renderer::RendererInputEventType::Modifiers:
        break;
    }
    return false;
}

mesh2splat::renderer::RendererFrameResult MetalRenderer::tickFrame(
    const mesh2splat::renderer::RendererFrameTick& frame)
{
    const uint64_t submittedBefore = rendererStats().submittedFrameCount;
    draw(frame.renderPassDescriptor, frame.drawable, frame.inputState, frame.deltaTimeSeconds);

    mesh2splat::renderer::RendererFrameResult result;
    result.stats = rendererStats();
    result.submitted = result.stats.submittedFrameCount > submittedBefore;
    result.drawableAvailable = frame.renderPassDescriptor != nullptr && frame.drawable != nullptr;
    result.frameIndex = frame.frameIndex;
    result.frameNumber = frame.frameNumber;
    result.state = runtimeState();
    result.sceneCounts = sceneCounts();
    result.conversion = conversionState();
    result.renderedMesh = result.stats.lastFrameRenderedMesh;
    result.renderedGaussians = result.stats.lastFrameRenderedGaussians;
    result.diagnostic = lastDiagnostic();
    return result;
}

mesh2splat::renderer::RendererDiagnostics MetalRenderer::diagnostics() const
{
    mesh2splat::renderer::RendererDiagnostics diagnostics;
    diagnostics.state = runtimeState();
    diagnostics.severity = severityForState(diagnostics.state, m_impl->lastDiagnostic);
    diagnostics.stats = rendererStats();
    diagnostics.message = m_impl->lastDiagnostic;
    diagnostics.lastError = m_impl->lastErrorMessage;
    diagnostics.loadedScene = loadedSceneSnapshot();
    diagnostics.loadedScenePath = diagnostics.loadedScene.filePath;
    diagnostics.assetSession = m_impl->assetSession.snapshot();
    diagnostics.sceneCounts = sceneCounts();
    diagnostics.renderSettings = renderSettingsSummary();
    diagnostics.conversion = conversionState();
    diagnostics.progress = diagnostics.conversion.progress;
    diagnostics.convertedGaussianCount = convertedGaussianCount();
    diagnostics.conversionSamplesPerTriangle = conversionSamplesPerTriangle();
    diagnostics.viewMode = viewMode();
    diagnostics.gaussianVisualizationMode = gaussianVisualizationMode();
    diagnostics.gaussianScale = gaussianScale();
    diagnostics.converting = isConvertingGaussians();
    diagnostics.hasScene = diagnostics.loadedScene.loaded ||
        (m_impl->sceneResources != nullptr && m_impl->sceneResources->isValid());
    diagnostics.hasGaussians = convertedGaussianCount() > 0;
    diagnostics.hasVisibleMesh = diagnostics.sceneCounts.hasVisibleMesh();
    if (diagnostics.message.empty()) {
        diagnostics.message = diagnostics.assetSession.statusText.empty()
            ? std::string("Metal renderer is ") + rendererStateName(diagnostics.state) + "."
            : diagnostics.assetSession.statusText;
    }
    diagnostics.statusText = diagnostics.message;
    return diagnostics;
}

mesh2splat::renderer::RendererRuntimeState MetalRenderer::runtimeState() const
{
    return m_impl->effectiveRuntimeState();
}

float MetalRenderer::conversionProgress() const
{
    return m_impl->currentConversionProgress();
}

std::string MetalRenderer::lastError() const
{
    return m_impl->lastErrorMessage;
}

void MetalRenderer::draw(
    void* renderPassDescriptor,
    void* drawable,
    const core::InputState& inputState,
    double deltaTimeSeconds)
{
    if (m_impl->deviceContext == nullptr || !m_impl->deviceContext->isValid() ||
        renderPassDescriptor == nullptr || drawable == nullptr) {
        return;
    }

    if (m_impl->frameSemaphore == nil ||
        dispatch_semaphore_wait(m_impl->frameSemaphore, DISPATCH_TIME_FOREVER) != 0) {
        return;
    }

    const Clock::time_point frameCpuStart = Clock::now();
    auto* descriptor = (__bridge MTLRenderPassDescriptor*)renderPassDescriptor;
    id<CAMetalDrawable> metalDrawable = (__bridge id<CAMetalDrawable>)drawable;
    if (descriptor == nil || metalDrawable == nil || metalDrawable.texture == nil) {
        m_impl->recordDiagnostic("Cannot draw Metal frame: render pass descriptor or drawable texture is unavailable.");
        m_impl->recordFrameEncodeFailure(frameCpuStart, false, false, false);
        dispatch_semaphore_signal(m_impl->frameSemaphore);
        return;
    }

    const uint32_t drawableWidth = textureWidth(metalDrawable.texture);
    const uint32_t drawableHeight = textureHeight(metalDrawable.texture);
    if (drawableWidth == 0 || drawableHeight == 0) {
        m_impl->recordDiagnostic("Cannot draw Metal frame: drawable texture size is zero.");
        m_impl->recordFrameEncodeFailure(frameCpuStart, false, false, false);
        dispatch_semaphore_signal(m_impl->frameSemaphore);
        return;
    }

    if (drawableWidth != m_impl->width || drawableHeight != m_impl->height) {
        m_impl->updateDrawableSize(drawableWidth, drawableHeight);
    }

    m_impl->renderingFrame = true;
    m_impl->frameResources->beginFrame("Mesh2Splat Metal Frame");
    m_impl->finalizePendingConversion();
    m_impl->camera.update(inputState, deltaTimeSeconds);
    m_impl->camera.writeFrameUniforms(m_impl->frameUniforms);
    const uint32_t frameResourceIndex = m_impl->frameResources->currentFrameIndex();
    m_impl->frameUniforms.frameIndex = frameResourceIndex;
    m_impl->frameUniforms.renderMode = static_cast<uint32_t>(m_impl->gaussianVisualizationMode);
    m_impl->frameUniforms.flags = m_impl->debugFlags;
    m_impl->frameUniforms.gaussianParams[0] = m_impl->gaussianScale;
    m_impl->frameUniforms.gaussianParams[1] = m_impl->exposure;
    m_impl->frameUniforms.gaussianParams[2] = m_impl->gamma;
    m_impl->frameUniforms.gaussianParams[3] = m_impl->backgroundBrightness;
    m_impl->frameUniforms.lightPositionIntensity[0] = m_impl->lightPosition[0];
    m_impl->frameUniforms.lightPositionIntensity[1] = m_impl->lightPosition[1];
    m_impl->frameUniforms.lightPositionIntensity[2] = m_impl->lightPosition[2];
    m_impl->frameUniforms.lightPositionIntensity[3] = m_impl->lightIntensity;
    m_impl->frameUniforms.lightColorFlags[0] = m_impl->lightColor[0];
    m_impl->frameUniforms.lightColorFlags[1] = m_impl->lightColor[1];
    m_impl->frameUniforms.lightColorFlags[2] = m_impl->lightColor[2];
    m_impl->frameUniforms.lightColorFlags[3] = m_impl->lightingEnabled ? 1.0f : 0.0f;
    if (m_impl->frameUniformBuffer == nullptr ||
        !m_impl->frameUniformBuffer->update(frameResourceIndex, m_impl->frameUniforms)) {
        m_impl->recordDiagnostic(
            m_impl->frameUniformBuffer == nullptr
                ? "Cannot draw Metal frame: frame uniform buffer is unavailable."
                : m_impl->frameUniformBuffer->lastDiagnostic());
        m_impl->recordFrameEncodeFailure(frameCpuStart, false, false, false);
        m_impl->renderingFrame = false;
        dispatch_semaphore_signal(m_impl->frameSemaphore);
        return;
    }

    if (!m_impl->prepareDrawableRenderPassDescriptor(
            descriptor,
            metalDrawable.texture,
            drawableWidth,
            drawableHeight)) {
        m_impl->recordFrameEncodeFailure(frameCpuStart, false, false, false);
        m_impl->renderingFrame = false;
        dispatch_semaphore_signal(m_impl->frameSemaphore);
        return;
    }

    void* nativeCommandQueue = m_impl->deviceContext->nativeCommandQueue();
    MetalCommandScheduler commandScheduler(nativeCommandQueue);
    id<MTLCommandBuffer> commandBuffer =
        (__bridge id<MTLCommandBuffer>)commandScheduler.createCommandBuffer("Mesh2Splat Metal Frame");
    if (commandBuffer == nil) {
        m_impl->recordDiagnostic("Cannot draw Metal frame: failed to create command buffer.");
        m_impl->recordFrameEncodeFailure(frameCpuStart, false, false, false);
        m_impl->renderingFrame = false;
        dispatch_semaphore_signal(m_impl->frameSemaphore);
        return;
    }
    const uint64_t logicalFrameIndex = m_impl->timingState == nullptr
        ? static_cast<uint64_t>(frameResourceIndex)
        : m_impl->timingState->snapshot().submittedFrameCount;
    const MetalFrameCaptureDecision captureBegin =
        m_impl->frameCapture.beginDecision(logicalFrameIndex, "Mesh2Splat Metal Frame");
    bool captureStartedThisFrame = false;
    bool captureDebugGroupPushed = false;
    if (captureBegin.shouldStart) {
        std::string captureDiagnostic;
        captureStartedThisFrame = startMetalCapture(
            (__bridge id<MTLCommandQueue>)nativeCommandQueue,
            captureBegin.marker,
            &captureDiagnostic);
        m_impl->recordDiagnostic(captureDiagnostic);
        if (!captureStartedThisFrame) {
            m_impl->frameCapture.clearRequest();
        } else if (captureBegin.shouldMark) {
            [commandBuffer pushDebugGroup:stringFromStdString(captureBegin.marker.debugGroupLabel())];
            captureDebugGroupPushed = true;
        }
    }
    auto closeCaptureDebugGroup = [&]() {
        if (captureDebugGroupPushed) {
            [commandBuffer popDebugGroup];
            captureDebugGroupPushed = false;
        }
    };

    auto finishFrameCapture = [&](bool completedFrame) {
        if (!captureStartedThisFrame) {
            return;
        }
        closeCaptureDebugGroup();

        const MetalFrameCaptureDecision captureEnd =
            m_impl->frameCapture.endDecision(logicalFrameIndex, "Mesh2Splat Metal Frame");
        stopMetalCapture();
        captureStartedThisFrame = false;
        m_impl->recordDiagnostic(
            std::string(completedFrame ? "Completed Metal capture for " : "Stopped Metal capture after failed frame for ") +
            captureEnd.marker.debugGroupLabel());
    };
    dispatch_semaphore_t frameSemaphore = m_impl->frameSemaphore;
    std::shared_ptr<MetalRendererTimingState> frameTimingState = m_impl->timingState;
    std::shared_ptr<MetalFrameResources> frameResources = m_impl->frameResources;
    std::shared_ptr<MetalFrameUniformBuffer> frameUniformBuffer = m_impl->frameUniformBuffer;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> completedCommandBuffer) {
        if (frameTimingState != nullptr) {
            frameTimingState->recordFrameCompleted(
                completedCommandBuffer.status == MTLCommandBufferStatusCompleted,
                commandBufferGpuMilliseconds(completedCommandBuffer));
        }
        if (frameResources != nullptr) {
            frameResources->markFrameCompleted(frameResourceIndex);
        }
        if (frameUniformBuffer != nullptr) {
            frameUniformBuffer->markFrameCompleted(frameResourceIndex);
        }
        dispatch_semaphore_signal(frameSemaphore);
    }];

    bool sortedGaussiansThisFrame = false;
    const bool showGaussians =
        m_impl->viewMode == RenderViewMode::Combined || m_impl->viewMode == RenderViewMode::GaussianOnly;
    if (showGaussians && m_impl->gaussianSortPass != nullptr && m_impl->gaussianBuffer != nullptr &&
        m_impl->gaussianSortBuffer != nullptr && m_impl->frameUniformBuffer != nullptr) {
        const bool gaussianCountChanged =
            m_impl->gaussianSortBuffer->count() != m_impl->gaussianBuffer->count();
        const bool needsSortedIndices = m_impl->gaussianSortingEnabled &&
            (!m_impl->hasSortedGaussianDepths ||
                gaussianCountChanged ||
                !matrixApproximatelyEquals(m_impl->lastSortedViewMatrix, m_impl->frameUniforms.viewMatrix));
        const bool needsIdentityIndices = !m_impl->gaussianSortingEnabled &&
            (!m_impl->hasSortedGaussianDepths || gaussianCountChanged);
        if (needsSortedIndices) {
            const bool encodedSort = m_impl->gaussianSortPass->encodeDepthKeys(
                (__bridge void*)commandBuffer,
                *m_impl->gaussianBuffer,
                *m_impl->gaussianSortBuffer,
                m_impl->frameUniformBuffer->buffer(frameResourceIndex));
            m_impl->hasSortedGaussianDepths = encodedSort;
            if (encodedSort) {
                sortedGaussiansThisFrame = true;
                m_impl->lastSortedViewMatrix = m_impl->frameUniforms.viewMatrix;
            } else {
                m_impl->recordDiagnostic(m_impl->gaussianSortPass->lastDiagnostic());
            }
        } else if (needsIdentityIndices) {
            const bool encodedIdentity = m_impl->gaussianSortPass->encodeIdentityIndices(
                (__bridge void*)commandBuffer,
                *m_impl->gaussianBuffer,
                *m_impl->gaussianSortBuffer);
            m_impl->hasSortedGaussianDepths = encodedIdentity;
            if (encodedIdentity) {
                m_impl->lastSortedViewMatrix = m_impl->frameUniforms.viewMatrix;
            } else {
                m_impl->recordDiagnostic(m_impl->gaussianSortPass->lastDiagnostic());
            }
        }
    }

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    if (encoder == nil) {
        m_impl->recordDiagnostic("Cannot draw Metal frame: failed to create render command encoder.");
        finishFrameCapture(false);
        m_impl->recordFrameEncodeFailure(frameCpuStart, sortedGaussiansThisFrame, false, false);
        m_impl->renderingFrame = false;
        dispatch_semaphore_signal(m_impl->frameSemaphore);
        return;
    }
    encoder.label = @"Mesh2Splat Drawable Render";
    const bool showMesh = m_impl->viewMode == RenderViewMode::Combined || m_impl->viewMode == RenderViewMode::MeshOnly;
    const bool canRenderMeshThisFrame =
        showMesh && m_impl->meshRenderPass != nullptr && m_impl->sceneResources != nullptr &&
        m_impl->frameUniformBuffer != nullptr;
    bool renderedMeshThisFrame = false;
    if (canRenderMeshThisFrame) {
        const bool showMeshWireframe =
            core::hasRenderDebugFlag(m_impl->debugFlags, core::RenderDebugFlag::ShowMeshWireframe);
        m_impl->meshRenderPass->encode(
            (__bridge void*)encoder,
            *m_impl->sceneResources,
            m_impl->frameUniformBuffer->buffer(frameResourceIndex),
            m_impl->depthTestEnabled,
            showMeshWireframe);
        m_impl->recordDiagnostic(m_impl->meshRenderPass->lastDiagnostic());
        renderedMeshThisFrame =
            m_impl->meshRenderPass->lastEncodeDiagnostics().encodedDrawRangeCount > 0;
    }
    const bool canRenderGaussiansThisFrame =
        showGaussians && m_impl->hasSortedGaussianDepths &&
        m_impl->gaussianRenderPass != nullptr && m_impl->gaussianBuffer != nullptr &&
        m_impl->gaussianSortBuffer != nullptr && m_impl->frameUniformBuffer != nullptr;
    bool renderedGaussiansThisFrame = false;
    if (canRenderGaussiansThisFrame) {
        const bool overdrawVisualization =
            m_impl->gaussianVisualizationMode == GaussianVisualizationMode::Overdraw;
        m_impl->gaussianRenderPass->encode(
            (__bridge void*)encoder,
            *m_impl->gaussianBuffer,
            *m_impl->gaussianSortBuffer,
            m_impl->frameUniformBuffer->buffer(frameResourceIndex),
            m_impl->depthTestEnabled,
            overdrawVisualization);
        m_impl->recordDiagnostic(m_impl->gaussianRenderPass->lastDiagnostic());
        renderedGaussiansThisFrame =
            m_impl->gaussianRenderPass->lastEncodeDiagnostics().instanceCount > 0;
    }
    [encoder endEncoding];

    if (!MetalCommandScheduler::presentDrawable((__bridge void*)commandBuffer, (__bridge void*)metalDrawable)) {
        m_impl->recordDiagnostic("Cannot draw Metal frame: failed to schedule drawable presentation.");
        finishFrameCapture(false);
        m_impl->recordFrameEncodeFailure(
            frameCpuStart,
            sortedGaussiansThisFrame,
            renderedMeshThisFrame,
            renderedGaussiansThisFrame);
        m_impl->renderingFrame = false;
        dispatch_semaphore_signal(m_impl->frameSemaphore);
        return;
    }

    closeCaptureDebugGroup();
    if (commandScheduler.commit((__bridge void*)commandBuffer)) {
        finishFrameCapture(true);
        if (frameTimingState != nullptr) {
            frameTimingState->recordFrameSubmitted(
                elapsedMilliseconds(frameCpuStart, Clock::now()),
                m_impl->currentGaussianCount(),
                sortedGaussiansThisFrame,
                renderedMeshThisFrame,
                renderedGaussiansThisFrame);
        }
        m_impl->markFrameSubmitted(frameResourceIndex);
        m_impl->renderingFrame = false;
    } else {
        m_impl->recordDiagnostic("Cannot draw Metal frame: failed to commit command buffer.");
        finishFrameCapture(false);
        m_impl->recordFrameEncodeFailure(
            frameCpuStart,
            sortedGaussiansThisFrame,
            renderedMeshThisFrame,
            renderedGaussiansThisFrame);
        m_impl->renderingFrame = false;
        dispatch_semaphore_signal(m_impl->frameSemaphore);
    }
}

} // namespace mesh2splat::metal

namespace mesh2splat::renderer {

std::unique_ptr<Renderer> createMetalRenderer(void* metalDevice)
{
    return std::make_unique<metal::MetalRenderer>(metalDevice);
}

} // namespace mesh2splat::renderer
