#include "MetalRenderer.hpp"

#include "core/FrameData.hpp"
#include "core/GaussianData.hpp"
#include "core/GltfMeshLoader.hpp"
#include "core/NativeCamera.hpp"
#include "core/PrimitiveMeshFactory.hpp"
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
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::metal {
namespace {

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

bool loadRendererShaderLibrary(MetalShaderLibrary& shaderLibrary)
{
    const std::string metallibPath = bundledMetallibPath();
    if (!metallibPath.empty() && shaderLibrary.loadFromFile(metallibPath)) {
        return true;
    }

    if (shaderLibrary.loadDefault("Mesh2Splat Default Metal Library")) {
        return true;
    }

    const std::string source = bundledShaderSource();
    return !source.empty() && shaderLibrary.compileSource(source, "Mesh2Splat Runtime Metal Library");
}

std::size_t nextPowerOfTwo(std::size_t value)
{
    if (value <= 1) {
        return 1;
    }

    --value;
    for (std::size_t shift = 1; shift < sizeof(std::size_t) * 8; shift <<= 1) {
        value |= value >> shift;
    }
    return value + 1;
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

bool matrixEquals(const core::Matrix4& lhs, const core::Matrix4& rhs)
{
    for (std::size_t i = 0; i < 16; ++i) {
        if (lhs.values[i] != rhs.values[i]) {
            return false;
        }
    }

    return true;
}

} // namespace

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
    RenderViewMode viewMode = RenderViewMode::Combined;
    GaussianVisualizationMode gaussianVisualizationMode = GaussianVisualizationMode::Final;
    bool hasSortedGaussianDepths = false;
    float gaussianScale = 1.0f;
    uint32_t conversionSamplesPerTriangle = kDefaultMetalConversionSamplesPerTriangle;
    uint32_t convertedGaussianCount = 0;
    uint32_t width = 0;
    uint32_t height = 0;
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

    const std::size_t triangleCount = conversionSceneResources.totalVertexCount() / 3;
    if (triangleCount == 0 ||
        triangleCount > std::numeric_limits<std::size_t>::max() / conversionSamplesPerTriangle) {
        return false;
    }

    const std::size_t gaussianCapacity = triangleCount * conversionSamplesPerTriangle;
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

    const std::size_t sortCapacity = nextPowerOfTwo(gaussianCapacity);
    if (sortCapacity < gaussianCapacity) {
        return false;
    }

    nextConversion->sortBuffer = std::make_unique<MetalGaussianSortBuffer>(*deviceContext);
    if (!nextConversion->sortBuffer->create(sortCapacity, "Mesh2Splat Gaussian Sort")) {
        return false;
    }

    id<MTLCommandQueue> commandQueue =
        (__bridge id<MTLCommandQueue>)deviceContext->nativeCommandQueue();
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    if (commandBuffer == nil) {
        return false;
    }

    commandBuffer.label = @"Mesh2Splat Mesh Conversion";
    if (!conversionPass->encode(
            (__bridge void*)commandBuffer,
            conversionSceneResources,
            *nextConversion->gaussianBuffer,
            conversionSamplesPerTriangle)) {
        return false;
    }

    nextConversion->nextSceneResources = std::move(nextSceneResources);
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
        nextConversion->completed.store(true, std::memory_order_release);
    }];

    pendingConversion = nextConversion;
    [commandBuffer commit];
    return true;
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
        return false;
    }

    if (!m_impl->deviceContext->initialize()) {
        return false;
    }

    m_impl->frameSemaphore = dispatch_semaphore_create(m_impl->frameResources.frameCount());
    if (m_impl->frameSemaphore == nil) {
        return false;
    }

    m_impl->frameUniformBuffer = std::make_unique<MetalFrameUniformBuffer>(*m_impl->deviceContext);
    if (!m_impl->frameUniformBuffer->initialize("Mesh2Splat Frame Uniforms")) {
        return false;
    }

    m_impl->renderStateCache = std::make_unique<MetalRenderStateCache>(*m_impl->deviceContext);
    m_impl->pipelineCache = std::make_unique<MetalPipelineCache>(*m_impl->deviceContext);
    m_impl->shaderLibrary = std::make_unique<MetalShaderLibrary>(*m_impl->deviceContext);
    m_impl->sceneResources = std::make_unique<MetalSceneResources>(*m_impl->deviceContext);

    std::vector<core::MeshData> previewMeshes;
    previewMeshes.push_back(core::createPreviewTriangleMesh());
    m_impl->sceneResources->uploadMeshes(previewMeshes);

    if (loadRendererShaderLibrary(*m_impl->shaderLibrary)) {
        m_impl->conversionPass = std::make_unique<MetalConversionPass>();
        if (!m_impl->conversionPass->initialize(
                *m_impl->shaderLibrary,
                *m_impl->pipelineCache,
                *m_impl->renderStateCache)) {
            m_impl->conversionPass.reset();
        } else if (!m_impl->submitCurrentSceneConversion()) {
            NSLog(@"Initial Metal mesh conversion could not be submitted.");
        }

        m_impl->gaussianRenderPass = std::make_unique<MetalGaussianRenderPass>(*m_impl->deviceContext);
        if (!m_impl->gaussianRenderPass->initialize(
                *m_impl->shaderLibrary,
                *m_impl->pipelineCache,
                *m_impl->renderStateCache,
                MetalTextureFormat::BGRA8Unorm,
                MetalTextureFormat::Depth32Float)) {
            m_impl->gaussianRenderPass.reset();
        }

        m_impl->gaussianSortPass = std::make_unique<MetalGaussianSortPass>();
        if (!m_impl->gaussianSortPass->initialize(*m_impl->shaderLibrary, *m_impl->pipelineCache)) {
            m_impl->gaussianSortPass.reset();
        }

        m_impl->meshRenderPass = std::make_unique<MetalMeshRenderPass>(*m_impl->deviceContext);
        if (!m_impl->meshRenderPass->initialize(
                *m_impl->shaderLibrary,
                *m_impl->pipelineCache,
                *m_impl->renderStateCache,
                MetalTextureFormat::BGRA8Unorm,
                MetalTextureFormat::Depth32Float)) {
            m_impl->meshRenderPass.reset();
        }
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
    id<MTLCommandQueue> commandQueue =
        (__bridge id<MTLCommandQueue>)m_impl->deviceContext->nativeCommandQueue();
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    if (commandBuffer == nil) {
        dispatch_semaphore_signal(m_impl->frameSemaphore);
        return;
    }
    commandBuffer.label = @"Mesh2Splat Metal Frame";
    dispatch_semaphore_t frameSemaphore = m_impl->frameSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> completedCommandBuffer) {
        (void)completedCommandBuffer;
        dispatch_semaphore_signal(frameSemaphore);
    }];

    const bool showGaussians =
        m_impl->viewMode == RenderViewMode::Combined || m_impl->viewMode == RenderViewMode::GaussianOnly;
    if (showGaussians && m_impl->gaussianSortPass != nullptr && m_impl->gaussianBuffer != nullptr &&
        m_impl->gaussianSortBuffer != nullptr && m_impl->frameUniformBuffer != nullptr) {
        const bool needsGaussianSort = !m_impl->hasSortedGaussianDepths ||
            m_impl->gaussianSortBuffer->count() != m_impl->gaussianBuffer->count() ||
            !matrixEquals(m_impl->lastSortedViewMatrix, m_impl->frameUniforms.viewMatrix);
        if (needsGaussianSort) {
            m_impl->hasSortedGaussianDepths = m_impl->gaussianSortPass->encodeDepthKeys(
                (__bridge void*)commandBuffer,
                *m_impl->gaussianBuffer,
                *m_impl->gaussianSortBuffer,
                m_impl->frameUniformBuffer->buffer(m_impl->frameResources.currentFrameIndex()));
            if (m_impl->hasSortedGaussianDepths) {
                m_impl->lastSortedViewMatrix = m_impl->frameUniforms.viewMatrix;
            }
        }
    }

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    if (encoder == nil) {
        [commandBuffer commit];
        return;
    }
    encoder.label = @"Mesh2Splat Drawable Render";
    const bool showMesh = m_impl->viewMode == RenderViewMode::Combined || m_impl->viewMode == RenderViewMode::MeshOnly;
    if (showMesh && m_impl->meshRenderPass != nullptr && m_impl->sceneResources != nullptr &&
        m_impl->frameUniformBuffer != nullptr) {
        m_impl->meshRenderPass->encode(
            (__bridge void*)encoder,
            *m_impl->sceneResources,
            m_impl->frameUniformBuffer->buffer(m_impl->frameResources.currentFrameIndex()));
    }
    if (showGaussians && m_impl->hasSortedGaussianDepths &&
        m_impl->gaussianRenderPass != nullptr && m_impl->gaussianBuffer != nullptr &&
        m_impl->gaussianSortBuffer != nullptr && m_impl->frameUniformBuffer != nullptr) {
        m_impl->gaussianRenderPass->encode(
            (__bridge void*)encoder,
            *m_impl->gaussianBuffer,
            *m_impl->gaussianSortBuffer,
            m_impl->frameUniformBuffer->buffer(m_impl->frameResources.currentFrameIndex()));
    }
    [encoder endEncoding];

    [commandBuffer presentDrawable:metalDrawable];
    [commandBuffer commit];
}

} // namespace mesh2splat::metal
