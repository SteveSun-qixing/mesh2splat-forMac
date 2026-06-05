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
#include "MetalMeshRenderPass.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalRenderStateCache.hpp"
#include "MetalSceneResources.hpp"
#include "MetalShaderLibrary.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::metal {
namespace {

constexpr std::size_t kMetalConversionSamplesPerTriangle = 4;

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

} // namespace

struct MetalRenderer::Impl {
    bool convertSceneToGaussians(const MetalSceneResources& nextSceneResources);

    std::unique_ptr<MetalDeviceContext> deviceContext;
    MetalFrameResources frameResources;
    std::unique_ptr<MetalFrameUniformBuffer> frameUniformBuffer;
    std::unique_ptr<MetalShaderLibrary> shaderLibrary;
    std::unique_ptr<MetalPipelineCache> pipelineCache;
    std::unique_ptr<MetalRenderStateCache> renderStateCache;
    std::unique_ptr<MetalSceneResources> sceneResources;
    std::unique_ptr<MetalGaussianBuffer> gaussianBuffer;
    std::unique_ptr<MetalConversionPass> conversionPass;
    std::unique_ptr<MetalGaussianRenderPass> gaussianRenderPass;
    std::unique_ptr<MetalMeshRenderPass> meshRenderPass;
    core::FrameUniforms frameUniforms;
    core::NativeCamera camera;
    std::string loadedMeshPath;
    uint32_t convertedGaussianCount = 0;
    uint32_t width = 0;
    uint32_t height = 0;
};

bool MetalRenderer::Impl::convertSceneToGaussians(const MetalSceneResources& nextSceneResources)
{
    if (deviceContext == nullptr || !deviceContext->isValid() ||
        conversionPass == nullptr || !conversionPass->isReady() ||
        !nextSceneResources.isValid() || !core::gaussianCountFitsBuffer(nextSceneResources.totalVertexCount())) {
        return false;
    }

    const std::size_t triangleCount = nextSceneResources.totalVertexCount() / 3;
    if (triangleCount == 0 || triangleCount > std::numeric_limits<std::size_t>::max() / kMetalConversionSamplesPerTriangle) {
        return false;
    }

    const std::size_t gaussianCapacity = triangleCount * kMetalConversionSamplesPerTriangle;
    if (!core::gaussianCountFitsBuffer(gaussianCapacity)) {
        return false;
    }

    auto nextGaussianBuffer = std::make_unique<MetalGaussianBuffer>(*deviceContext);
    if (!nextGaussianBuffer->create(gaussianCapacity, "Mesh2Splat Converted Gaussians")) {
        return false;
    }

    id<MTLCommandQueue> commandQueue =
        (__bridge id<MTLCommandQueue>)deviceContext->nativeCommandQueue();
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    if (commandBuffer == nil) {
        return false;
    }

    commandBuffer.label = @"Mesh2Splat Mesh Conversion";
    if (!conversionPass->encode((__bridge void*)commandBuffer, nextSceneResources, *nextGaussianBuffer)) {
        return false;
    }

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    if (commandBuffer.status != MTLCommandBufferStatusCompleted) {
        return false;
    }

    if (!nextGaussianBuffer->readGpuCounter()) {
        return false;
    }

    convertedGaussianCount = nextGaussianBuffer->count();
    gaussianBuffer = std::move(nextGaussianBuffer);
    return convertedGaussianCount > 0;
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
        } else if (!m_impl->convertSceneToGaussians(*m_impl->sceneResources)) {
            NSLog(@"Initial Metal mesh conversion did not produce gaussians.");
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

    if (!m_impl->convertSceneToGaussians(*nextSceneResources)) {
        NSLog(@"Metal mesh conversion did not produce gaussians: %s", filePath.c_str());
    }

    m_impl->sceneResources = std::move(nextSceneResources);
    m_impl->camera.frameBounds(aggregateMeshBounds(loadResult.meshes));
    m_impl->loadedMeshPath = filePath;
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

    m_impl->frameResources.beginFrame();
    m_impl->camera.update(inputState, deltaTimeSeconds);
    m_impl->camera.writeFrameUniforms(m_impl->frameUniforms);
    m_impl->frameUniforms.frameIndex = m_impl->frameResources.currentFrameIndex();
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
        return;
    }
    commandBuffer.label = @"Mesh2Splat Metal Frame";

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    encoder.label = @"Mesh2Splat Drawable Render";
    if (m_impl->meshRenderPass != nullptr && m_impl->sceneResources != nullptr &&
        m_impl->frameUniformBuffer != nullptr) {
        m_impl->meshRenderPass->encode(
            (__bridge void*)encoder,
            *m_impl->sceneResources,
            m_impl->frameUniformBuffer->buffer(m_impl->frameResources.currentFrameIndex()));
    }
    if (m_impl->gaussianRenderPass != nullptr && m_impl->gaussianBuffer != nullptr &&
        m_impl->frameUniformBuffer != nullptr) {
        m_impl->gaussianRenderPass->encode(
            (__bridge void*)encoder,
            *m_impl->gaussianBuffer,
            m_impl->frameUniformBuffer->buffer(m_impl->frameResources.currentFrameIndex()));
    }
    [encoder endEncoding];

    [commandBuffer presentDrawable:metalDrawable];
    [commandBuffer commit];
}

} // namespace mesh2splat::metal
