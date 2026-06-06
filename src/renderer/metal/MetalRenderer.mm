#include "MetalRenderer.hpp"

#include "core/FrameData.hpp"
#include "core/GaussianData.hpp"
#include "core/GltfMeshLoader.hpp"
#include "core/NativeCamera.hpp"
#include "core/PrimitiveMeshFactory.hpp"
#include "MetalCommandScheduler.hpp"
#include "MetalConversionPass.hpp"
#include "MetalDeviceContext.hpp"
#include "MetalFrameUniformBuffer.hpp"
#include "MetalFrameResources.hpp"
#include "MetalGaussianBuffer.hpp"
#include "MetalGaussianRenderPass.hpp"
#include "MetalGaussianSortBuffer.hpp"
#include "MetalGaussianSortPass.hpp"
#include "MetalMeshRenderPass.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalRenderStateCache.hpp"
#include "MetalSceneResources.hpp"
#include "MetalShaderLibrary.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <dispatch/dispatch.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::metal {
namespace {

using Clock = std::chrono::steady_clock;

constexpr uint32_t kDefaultMetalConversionSamplesPerTriangle = 4;

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

uint32_t normalizedConversionSamples(uint32_t samplesPerTriangle)
{
    if (samplesPerTriangle <= 1) {
        return 1;
    }
    if (samplesPerTriangle <= 4) {
        return 4;
    }
    return 9;
}

core::MeshBounds aggregateMeshBounds(const std::vector<core::MeshData>& meshes)
{
    core::MeshBounds bounds;
    bool hasBounds = false;

    for (const core::MeshData& mesh : meshes) {
        if (mesh.empty()) {
            continue;
        }

        if (!hasBounds) {
            bounds = mesh.bounds;
            hasBounds = true;
            continue;
        }

        for (int axis = 0; axis < 3; ++axis) {
            bounds.min[axis] = std::min(bounds.min[axis], mesh.bounds.min[axis]);
            bounds.max[axis] = std::max(bounds.max[axis], mesh.bounds.max[axis]);
        }
    }

    return bounds;
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

double exponentialAverage(double currentAverage, double sample)
{
    constexpr double kAlpha = 0.12;
    return currentAverage <= 0.0 ? sample : currentAverage + (sample - currentAverage) * kAlpha;
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
};

struct PendingGaussianConversion {
    std::unique_ptr<MetalSceneResources> nextSceneResources;
    std::unique_ptr<MetalGaussianBuffer> gaussianBuffer;
    std::unique_ptr<MetalGaussianSortBuffer> sortBuffer;
    core::MeshBounds nextMeshBounds;
    std::string nextLoadedMeshPath;
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
        std::unique_ptr<MetalSceneResources>&& nextSceneResources,
        const core::MeshBounds& nextMeshBounds,
        std::string nextLoadedMeshPath,
        bool revertsSamplesOnFailure = false,
        uint32_t previousSamplesPerTriangle = kDefaultMetalConversionSamplesPerTriangle);
    bool submitCurrentSceneConversion(bool revertsSamplesOnFailure = false, uint32_t previousSamplesPerTriangle = 0);
    void finalizePendingConversion();

    std::unique_ptr<MetalDeviceContext> deviceContext;
    MetalFrameResources frameResources;
    dispatch_semaphore_t frameSemaphore = nil;
    std::unique_ptr<MetalFrameUniformBuffer> frameUniformBuffer;
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
    core::FrameUniforms frameUniforms;
    core::Matrix4 lastSortedViewMatrix;
    core::NativeCamera camera;
    std::string loadedMeshPath;
    std::string lastDiagnostic;
    RenderViewMode viewMode = RenderViewMode::Combined;
    GaussianVisualizationMode gaussianVisualizationMode = GaussianVisualizationMode::Final;
    bool hasSortedGaussianDepths = false;
    float gaussianScale = 1.0f;
    uint32_t conversionSamplesPerTriangle = kDefaultMetalConversionSamplesPerTriangle;
    uint32_t convertedGaussianCount = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    std::shared_ptr<MetalRendererTimingState> timingState = std::make_shared<MetalRendererTimingState>();
};

bool MetalRenderer::Impl::submitSceneConversion(
    const MetalSceneResources& conversionSceneResources,
    std::unique_ptr<MetalSceneResources>&& nextSceneResources,
    const core::MeshBounds& nextMeshBounds,
    std::string nextLoadedMeshPath,
    bool revertsSamplesOnFailure,
    uint32_t previousSamplesPerTriangle)
{
    if (deviceContext == nullptr || !deviceContext->isValid() ||
        conversionPass == nullptr || !conversionPass->isReady() ||
        !conversionSceneResources.isValid() ||
        !core::gaussianCountFitsBuffer(conversionSceneResources.totalVertexCount())) {
        return false;
    }

    const Clock::time_point conversionCpuStart = Clock::now();
    const std::size_t gaussianCapacity =
        conversionSceneResources.conversionCapacity(conversionSamplesPerTriangle);
    if (gaussianCapacity == 0) {
        return false;
    }

    if (!core::gaussianCountFitsBuffer(gaussianCapacity)) {
        return false;
    }

    auto nextConversion = std::make_shared<PendingGaussianConversion>();
    nextConversion->nextMeshBounds = nextMeshBounds;
    nextConversion->nextLoadedMeshPath = std::move(nextLoadedMeshPath);
    nextConversion->updatesScene = nextSceneResources != nullptr;
    nextConversion->revertsSamplesOnFailure = revertsSamplesOnFailure;
    nextConversion->previousSamplesPerTriangle = previousSamplesPerTriangle;
    nextConversion->gaussianBuffer = std::make_unique<MetalGaussianBuffer>(*deviceContext);
    if (!nextConversion->gaussianBuffer->create(gaussianCapacity, "Mesh2Splat Converted Gaussians")) {
        return false;
    }

    nextConversion->sortBuffer = std::make_unique<MetalGaussianSortBuffer>(*deviceContext);
    if (!nextConversion->sortBuffer->create(gaussianCapacity, "Mesh2Splat Gaussian Sort")) {
        return false;
    }

    MetalCommandScheduler commandScheduler(deviceContext->nativeCommandQueue());
    id<MTLCommandBuffer> commandBuffer =
        (__bridge id<MTLCommandBuffer>)commandScheduler.createCommandBuffer("Mesh2Splat Mesh Conversion");
    if (commandBuffer == nil) {
        return false;
    }

    if (!conversionPass->encode(
            (__bridge void*)commandBuffer,
            conversionSceneResources,
            *nextConversion->gaussianBuffer,
            conversionSamplesPerTriangle)) {
        return false;
    }

    nextConversion->nextSceneResources = std::move(nextSceneResources);
    std::shared_ptr<MetalRendererTimingState> conversionTimingState = timingState;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> completedCommandBuffer) {
        bool didSucceed = completedCommandBuffer.status == MTLCommandBufferStatusCompleted &&
            nextConversion->gaussianBuffer != nullptr &&
            nextConversion->gaussianBuffer->readGpuCounter();
        const uint32_t nextConvertedCount = didSucceed ? nextConversion->gaussianBuffer->count() : 0;
        didSucceed = didSucceed && nextConvertedCount > 0 &&
            nextConversion->sortBuffer != nullptr &&
            nextConvertedCount <= nextConversion->sortBuffer->capacity();

        nextConversion->convertedCount.store(nextConvertedCount, std::memory_order_relaxed);
        nextConversion->succeeded.store(didSucceed, std::memory_order_relaxed);
        if (conversionTimingState != nullptr) {
            conversionTimingState->recordConversionCompleted(
                didSucceed,
                commandBufferGpuMilliseconds(completedCommandBuffer));
        }
        nextConversion->completed.store(true, std::memory_order_release);
    }];

    if (timingState != nullptr) {
        timingState->recordConversionSubmitted(elapsedMilliseconds(conversionCpuStart, Clock::now()));
    }
    pendingConversion = nextConversion;
    return commandScheduler.commit((__bridge void*)commandBuffer);
}

bool MetalRenderer::Impl::submitCurrentSceneConversion(bool revertsSamplesOnFailure, uint32_t previousSamplesPerTriangle)
{
    if (sceneResources == nullptr || !sceneResources->isValid()) {
        return false;
    }

    return submitSceneConversion(
        *sceneResources,
        std::unique_ptr<MetalSceneResources>{},
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
        NSLog(@"Metal mesh conversion command did not produce gaussians.");
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
    hasSortedGaussianDepths = false;
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
        return false;
    }

    m_impl->lastDiagnostic.clear();
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
        return false;
    }

    m_impl->frameSemaphore = dispatch_semaphore_create(m_impl->frameResources.frameCount());
    if (m_impl->frameSemaphore == nil) {
        appendRendererDiagnostic("Failed to create Metal frame semaphore.");
        return false;
    }

    m_impl->frameUniformBuffer = std::make_unique<MetalFrameUniformBuffer>(*m_impl->deviceContext);
    if (!m_impl->frameUniformBuffer->initialize("Mesh2Splat Frame Uniforms")) {
        appendRendererDiagnostic("Failed to initialize Metal frame uniform buffers.");
        return false;
    }

    m_impl->renderStateCache = std::make_unique<MetalRenderStateCache>(*m_impl->deviceContext);
    m_impl->pipelineCache = std::make_unique<MetalPipelineCache>(*m_impl->deviceContext);
    m_impl->shaderLibrary = std::make_unique<MetalShaderLibrary>(*m_impl->deviceContext);
    m_impl->sceneResources = std::make_unique<MetalSceneResources>(*m_impl->deviceContext);

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
    return true;
}

bool MetalRenderer::loadMeshFile(const std::string& filePath)
{
    if (m_impl->deviceContext == nullptr || !m_impl->deviceContext->isValid() || filePath.empty()) {
        return false;
    }

    core::GltfMeshLoadResult loadResult;
    if (!core::loadGltfMeshData(filePath, loadResult)) {
        NSLog(@"Failed to load mesh: %s", loadResult.error.c_str());
        return false;
    }

    auto nextSceneResources = std::make_unique<MetalSceneResources>(*m_impl->deviceContext);
    if (!nextSceneResources->uploadMeshes(loadResult.meshes)) {
        NSLog(@"Failed to upload mesh resources: %s", filePath.c_str());
        return false;
    }

    if (!loadResult.warning.empty()) {
        NSLog(@"glTF load warning: %s", loadResult.warning.c_str());
    }

    const core::MeshBounds meshBounds = aggregateMeshBounds(loadResult.meshes);
    if (!m_impl->submitSceneConversion(
            *nextSceneResources,
            std::move(nextSceneResources),
            meshBounds,
            filePath)) {
        NSLog(@"Metal mesh conversion could not be submitted: %s", filePath.c_str());
        m_impl->pendingConversion.reset();
        m_impl->sceneResources = std::move(nextSceneResources);
        m_impl->camera.frameBounds(meshBounds);
        m_impl->loadedMeshPath = filePath;
        m_impl->gaussianBuffer.reset();
        m_impl->gaussianSortBuffer.reset();
        m_impl->convertedGaussianCount = 0;
        m_impl->hasSortedGaussianDepths = false;
    }
    return true;
}

void MetalRenderer::resize(uint32_t width, uint32_t height)
{
    m_impl->width = width;
    m_impl->height = height;
    m_impl->camera.resize(width, height);
    m_impl->frameUniforms.viewport[0] = static_cast<float>(width);
    m_impl->frameUniforms.viewport[1] = static_cast<float>(height);
    m_impl->frameUniforms.viewport[2] = width == 0 ? 1.0f : 1.0f / static_cast<float>(width);
    m_impl->frameUniforms.viewport[3] = height == 0 ? 1.0f : 1.0f / static_cast<float>(height);
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
    return m_impl->timingState == nullptr ? MetalRendererStats{} : m_impl->timingState->snapshot();
}

const std::string& MetalRenderer::lastDiagnostic() const
{
    return m_impl->lastDiagnostic;
}

const std::string& MetalRenderer::loadedMeshPath() const
{
    return m_impl->loadedMeshPath;
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
    m_impl->frameResources.beginFrame();
    m_impl->finalizePendingConversion();
    m_impl->camera.update(inputState, deltaTimeSeconds);
    m_impl->camera.writeFrameUniforms(m_impl->frameUniforms);
    m_impl->frameUniforms.frameIndex = m_impl->frameResources.currentFrameIndex();
    m_impl->frameUniforms.renderMode = static_cast<uint32_t>(m_impl->gaussianVisualizationMode);
    m_impl->frameUniforms.gaussianParams[0] = m_impl->gaussianScale;
    if (m_impl->frameUniformBuffer != nullptr) {
        m_impl->frameUniformBuffer->update(
            m_impl->frameResources.currentFrameIndex(),
            m_impl->frameUniforms);
    }

    auto* descriptor = (__bridge MTLRenderPassDescriptor*)renderPassDescriptor;
    id<CAMetalDrawable> metalDrawable = (__bridge id<CAMetalDrawable>)drawable;
    MetalCommandScheduler commandScheduler(m_impl->deviceContext->nativeCommandQueue());
    id<MTLCommandBuffer> commandBuffer =
        (__bridge id<MTLCommandBuffer>)commandScheduler.createCommandBuffer("Mesh2Splat Metal Frame");
    if (commandBuffer == nil) {
        dispatch_semaphore_signal(m_impl->frameSemaphore);
        return;
    }
    dispatch_semaphore_t frameSemaphore = m_impl->frameSemaphore;
    std::shared_ptr<MetalRendererTimingState> frameTimingState = m_impl->timingState;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> completedCommandBuffer) {
        if (frameTimingState != nullptr) {
            frameTimingState->recordFrameCompleted(
                completedCommandBuffer.status == MTLCommandBufferStatusCompleted,
                commandBufferGpuMilliseconds(completedCommandBuffer));
        }
        dispatch_semaphore_signal(frameSemaphore);
    }];

    bool sortedGaussiansThisFrame = false;
    const bool showGaussians =
        m_impl->viewMode == RenderViewMode::Combined || m_impl->viewMode == RenderViewMode::GaussianOnly;
    if (showGaussians && m_impl->gaussianSortPass != nullptr && m_impl->gaussianBuffer != nullptr &&
        m_impl->gaussianSortBuffer != nullptr && m_impl->frameUniformBuffer != nullptr) {
        const bool needsGaussianSort = !m_impl->hasSortedGaussianDepths ||
            m_impl->gaussianSortBuffer->count() != m_impl->gaussianBuffer->count() ||
            !matrixApproximatelyEquals(m_impl->lastSortedViewMatrix, m_impl->frameUniforms.viewMatrix);
        if (needsGaussianSort) {
            m_impl->hasSortedGaussianDepths = m_impl->gaussianSortPass->encodeDepthKeys(
                (__bridge void*)commandBuffer,
                *m_impl->gaussianBuffer,
                *m_impl->gaussianSortBuffer,
                m_impl->frameUniformBuffer->buffer(m_impl->frameResources.currentFrameIndex()));
            if (m_impl->hasSortedGaussianDepths) {
                sortedGaussiansThisFrame = true;
                m_impl->lastSortedViewMatrix = m_impl->frameUniforms.viewMatrix;
            }
        }
    }

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    if (encoder == nil) {
        if (frameTimingState != nullptr) {
            const uint32_t gaussianCount =
                m_impl->gaussianBuffer == nullptr ? 0 : m_impl->gaussianBuffer->count();
            frameTimingState->recordFrameSubmitted(
                elapsedMilliseconds(frameCpuStart, Clock::now()),
                gaussianCount,
                sortedGaussiansThisFrame,
                false,
                false);
        }
        commandScheduler.commit((__bridge void*)commandBuffer);
        return;
    }
    encoder.label = @"Mesh2Splat Drawable Render";
    const bool showMesh = m_impl->viewMode == RenderViewMode::Combined || m_impl->viewMode == RenderViewMode::MeshOnly;
    const bool renderMeshThisFrame =
        showMesh && m_impl->meshRenderPass != nullptr && m_impl->sceneResources != nullptr &&
        m_impl->frameUniformBuffer != nullptr;
    if (renderMeshThisFrame) {
        m_impl->meshRenderPass->encode(
            (__bridge void*)encoder,
            *m_impl->sceneResources,
            m_impl->frameUniformBuffer->buffer(m_impl->frameResources.currentFrameIndex()));
    }
    const bool renderGaussiansThisFrame =
        showGaussians && m_impl->hasSortedGaussianDepths &&
        m_impl->gaussianRenderPass != nullptr && m_impl->gaussianBuffer != nullptr &&
        m_impl->gaussianSortBuffer != nullptr && m_impl->frameUniformBuffer != nullptr;
    if (renderGaussiansThisFrame) {
        m_impl->gaussianRenderPass->encode(
            (__bridge void*)encoder,
            *m_impl->gaussianBuffer,
            *m_impl->gaussianSortBuffer,
            m_impl->frameUniformBuffer->buffer(m_impl->frameResources.currentFrameIndex()));
    }
    [encoder endEncoding];

    if (frameTimingState != nullptr) {
        const uint32_t gaussianCount =
            m_impl->gaussianBuffer == nullptr ? 0 : m_impl->gaussianBuffer->count();
        frameTimingState->recordFrameSubmitted(
            elapsedMilliseconds(frameCpuStart, Clock::now()),
            gaussianCount,
            sortedGaussiansThisFrame,
            renderMeshThisFrame,
            renderGaussiansThisFrame);
    }
    [commandBuffer presentDrawable:metalDrawable];
    commandScheduler.commit((__bridge void*)commandBuffer);
}

} // namespace mesh2splat::metal
