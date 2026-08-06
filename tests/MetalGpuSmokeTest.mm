// Mesh2Splat Metal GPU smoke test (headless, no NSApplication).
//
// Exercises two production GPU pipelines through the real renderer classes:
//   1. MetalGaussianSortPass  - depth key generation + GPU radix sort
//   2. MetalConversionPass    - mesh-to-gaussian conversion kernel
//
// All Metal interop happens through the C++-friendly wrappers of
// Mesh2SplatMetalLib. The test links Foundation/AppKit/libobjc directly so
// the Objective-C runtime is fully available to the library objects.

#include <objc/runtime.h>

#import <Metal/Metal.h>

#include "core/FrameData.hpp"
#include "core/GaussianData.hpp"
#include "core/PrimitiveMeshFactory.hpp"
#include "core/SceneData.hpp"
#include "renderer/metal/MetalBuffer.hpp"
#include "renderer/metal/MetalCommandScheduler.hpp"
#include "renderer/metal/MetalConversionPass.hpp"
#include "renderer/metal/MetalDeviceContext.hpp"
#include "renderer/metal/MetalGaussianBuffer.hpp"
#include "renderer/metal/MetalGaussianSortBuffer.hpp"
#include "renderer/metal/MetalGaussianSortPass.hpp"
#include "renderer/metal/MetalPipelineCache.hpp"
#include "renderer/metal/MetalRenderStateCache.hpp"
#include "renderer/metal/MetalSceneResources.hpp"
#include "renderer/metal/MetalShaderLibrary.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

// ---------------------------------------------------------------------------
// Test harness plumbing
// ---------------------------------------------------------------------------

int g_failures = 0;

void reportPass(const std::string& name)
{
    std::cout << "[PASS] " << name << '\n';
}

void reportFail(const std::string& name, const std::string& reason)
{
    ++g_failures;
    std::cerr << "[FAIL] " << name << ": " << reason << '\n';
}

bool readFile(const std::string& path, std::string& contents, std::string* errorMessage = nullptr)
{
    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        if (errorMessage != nullptr) {
            *errorMessage = "cannot open '" + path + "'";
        }
        return false;
    }
    contents.assign(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
    return !contents.empty();
}

std::string findShaderDirectory(int argc, char* argv[])
{
    if (argc > 1 && *argv[1] != '\0') {
        return argv[1];
    }
    if (const char* env = std::getenv("MESH2SPLAT_SHADER_DIR"); env != nullptr && *env != '\0') {
        return env;
    }
    const char* candidates[] = {
        "shaders/metal",
        "../shaders/metal",
        "mesh2splat-forMac/shaders/metal",
    };
    for (const char* candidate : candidates) {
        std::string probe = std::string(candidate) + "/Sort.metal";
        if (std::ifstream(probe).good()) {
            return candidate;
        }
    }
    return {};
}

bool compileShaderSource(
    const std::string& shaderDir,
    const char* shaderFileName,
    mesh2splat::metal::MetalShaderLibrary& library,
    std::string& errorMessage)
{
    std::string gpuTypesSource;
    std::string passSource;
    if (!readFile(shaderDir + "/GpuTypes.metal", gpuTypesSource, &errorMessage)) {
        return false;
    }
    if (!readFile(shaderDir + "/" + shaderFileName, passSource, &errorMessage)) {
        return false;
    }

    // GpuTypes.metal carries the shared ABI definitions; the pass shader files
    // are self-contained, so concatenating them (as the app's runtime fallback
    // does) yields a single compilable translation unit.
    std::string concatenated = gpuTypesSource + "\n" + passSource;
    std::string compileError;
    if (!library.compileSource(concatenated, shaderFileName, &compileError)) {
        errorMessage = "shader compile '" + std::string(shaderFileName) + "' failed: " + compileError;
        return false;
    }
    return true;
}

// Blit the GPU-private sorted index buffer into a CPU-accessible MetalBuffer.
inline bool blitIndexBufferToReadback(
    id<MTLCommandBuffer> commandBuffer,
    void* sourceBuffer,
    void* destinationBuffer,
    std::size_t byteCount)
{
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    if (blitEncoder == nil) {
        return false;
    }
    [blitEncoder copyFromBuffer:(__bridge id<MTLBuffer>)sourceBuffer
                   sourceOffset:0
                       toBuffer:(__bridge id<MTLBuffer>)destinationBuffer
              destinationOffset:0
                           size:byteCount];
    [blitEncoder endEncoding];
    return true;
}

// ---------------------------------------------------------------------------
// CPU reference for the GPU sort pipeline (mirrors Sort.metal exactly)
// ---------------------------------------------------------------------------

// sortableFloatKey / descendingDepthKey from Sort.metal lines 66-94.
uint32_t sortableFloatKey(float value)
{
    uint32_t bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));
    const uint32_t sign = bits >> 31;
    return sign == 0 ? (bits ^ 0x80000000u) : ~bits;
}

uint32_t descendingDepthKey(float positiveDepth)
{
    return 0xffffffffu - sortableFloatKey(positiveDepth);
}

// Column-major 4x4 (columns[i] = values[i * 4 + 0 .. 3]), matching both
// core::Matrix4 and the MSL `float4 columns[4]` ABI.
struct ViewMatrix {
    float values[16] = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f,
    };

    // Replicates `transformPoint(frame.viewMatrix, position)` with the same
    // float4 left-to-right association the shader uses. The matrix used by the
    // test has exact 0/±1 entries, so this is bit-identical to the GPU result.
    float viewDepth(float x, float y, float z) const
    {
        const float px = (x * values[0] + y * values[4]);
        const float py = (x * values[1] + y * values[5]);
        const float pz = (x * values[2] + y * values[6]);
        const float pw = (x * values[3] + y * values[7]);
        (void)px;
        (void)py;
        (void)pw;
        // viewPosition.z = ((pz) + z * values[10]) + values[14]
        const float viewZ = (pz + z * values[10]) + values[14];
        return -(viewZ);
    }
};

// Standard right-handed look-at view: camera at eye looking at center.
// Storage convention mirrors core::CameraController::lookAt.
ViewMatrix makeLookAtView(float eyeX, float eyeY, float eyeZ)
{
    const float forwardX = -eyeX;
    const float forwardY = -eyeY;
    const float forwardZ = -eyeZ;
    const float forwardLength =
        std::sqrt(forwardX * forwardX + forwardY * forwardY + forwardZ * forwardZ);
    const float fx = forwardX / forwardLength;
    const float fy = forwardY / forwardLength;
    const float fz = forwardZ / forwardLength;

    const float upX = 0.0f;
    const float upY = 1.0f;
    const float upZ = 0.0f;

    const float cx = fy * upZ - fz * upY;
    const float cy = fz * upX - fx * upZ;
    const float cz = fx * upY - fy * upX;
    const float rightLength = std::sqrt(cx * cx + cy * cy + cz * cz);
    const float rx = cx / rightLength;
    const float ry = cy / rightLength;
    const float rz = cz / rightLength;

    const float ux = ry * fz - rz * fy;
    const float uy = rz * fx - rx * fz;
    const float uz = rx * fy - ry * fx;

    ViewMatrix view;
    view.values[0] = rx;
    view.values[1] = ux;
    view.values[2] = -fx;
    view.values[4] = ry;
    view.values[5] = uy;
    view.values[6] = -fy;
    view.values[8] = rz;
    view.values[9] = uz;
    view.values[10] = -fz;
    view.values[12] = -(rx * eyeX + ry * eyeY + rz * eyeZ);
    view.values[13] = -(ux * eyeX + uy * eyeY + uz * eyeZ);
    view.values[14] = fx * eyeX + fy * eyeY + fz * eyeZ;
    return view;
}

std::vector<mesh2splat::core::GaussianRecord> makeSortGaussians(std::size_t count)
{
    std::vector<mesh2splat::core::GaussianRecord> gaussians;
    gaussians.reserve(count);
    uint32_t state = 0x12345678u;
    for (std::size_t index = 0; index < count; ++index) {
        state = state * 1664525u + 1013904223u;
        const float x = -3.0f + 6.0f * static_cast<float>((state >> 8) & 0xffffu) / 65535.0f;
        state = state * 1664525u + 1013904223u;
        const float y = -3.0f + 6.0f * static_cast<float>((state >> 8) & 0xffffu) / 65535.0f;
        const float z =
            -(0.5f + 2.0f * static_cast<float>(index) / static_cast<float>(count - 1));

        mesh2splat::core::GaussianRecord gaussian;
        gaussian.position[0] = x;
        gaussian.position[1] = y;
        gaussian.position[2] = z;
        gaussian.color[0] = 1.0f;
        gaussian.color[1] = 0.9f;
        gaussian.color[2] = 0.8f;
        gaussian.color[3] = 0.5f;
        gaussian.scale[0] = 0.02f;
        gaussian.scale[1] = 0.02f;
        gaussian.scale[2] = 0.01f;
        gaussian.normal[0] = 0.0f;
        gaussian.normal[1] = 0.0f;
        gaussian.normal[2] = 1.0f;
        gaussian.rotation[0] = 1.0f;
        gaussian.rotation[1] = 0.0f;
        gaussian.rotation[2] = 0.0f;
        gaussian.rotation[3] = 0.0f;
        gaussian.pbr[0] = 0.1f;
        gaussian.pbr[1] = 0.5f;
        gaussian.pbr[2] = 0.0f;
        gaussian.pbr[3] = 1.0f;
        gaussians.push_back(gaussian);
    }
    return gaussians;
}

// ---------------------------------------------------------------------------
// Test 1: GPU radix sort against the CPU reference
// ---------------------------------------------------------------------------

bool testGpuRadixSort(
    mesh2splat::metal::MetalDeviceContext& deviceContext,
    const std::string& shaderDir)
{
    const std::string kTestName = "gpu_radix_sort_depth_order";
    constexpr std::size_t kGaussianCount = 300;

    std::string errorMessage;

    mesh2splat::metal::MetalShaderLibrary shaderLibrary(deviceContext);
    if (!compileShaderSource(shaderDir, "Sort.metal", shaderLibrary, errorMessage)) {
        reportFail(kTestName, errorMessage);
        return false;
    }

    mesh2splat::metal::MetalPipelineCache pipelineCache(deviceContext);
    mesh2splat::metal::MetalGaussianSortPass sortPass;
    if (!sortPass.initialize(shaderLibrary, pipelineCache, &errorMessage)) {
        reportFail(kTestName, "sort pass initialization failed: " + errorMessage);
        return false;
    }

    const std::vector<mesh2splat::core::GaussianRecord> gaussians = makeSortGaussians(kGaussianCount);

    mesh2splat::metal::MetalGaussianBuffer gaussianBuffer(deviceContext);
    if (!gaussianBuffer.upload(gaussians, "GpuSmokeTest Gaussians")) {
        reportFail(kTestName, "gaussian upload failed: " + gaussianBuffer.lastErrorMessage());
        return false;
    }

    mesh2splat::metal::MetalGaussianSortBuffer sortBuffer(deviceContext);
    if (!sortBuffer.create(kGaussianCount, "GpuSmokeTest Sort Buffer")) {
        reportFail(kTestName, "sort buffer creation failed");
        return false;
    }

    // Camera at (0, 0, 8) looking at the origin; gaussians live at
    // z in [-2.5, -0.5], i.e. view depth in [8.5, 10.5] (positive, finite).
    mesh2splat::core::FrameUniforms uniforms = mesh2splat::core::makeDefaultFrameUniforms(1920, 1080);
    const ViewMatrix view = makeLookAtView(0.0f, 0.0f, 8.0f);
    std::memcpy(uniforms.viewMatrix.values, view.values, sizeof(view.values));

    mesh2splat::metal::MetalBuffer frameUniformBuffer(deviceContext);
    if (!frameUniformBuffer.createShared(sizeof(uniforms), &uniforms, "GpuSmokeTest Frame Uniforms")) {
        reportFail(kTestName, "frame uniform buffer creation failed");
        return false;
    }

    mesh2splat::metal::MetalCommandScheduler scheduler(deviceContext.nativeCommandQueue());
    void* commandBuffer = scheduler.createCommandBuffer("GpuSmokeTest Sort");
    if (commandBuffer == nullptr) {
        reportFail(kTestName, "command buffer creation failed");
        return false;
    }

    if (!sortPass.encodeDepthKeys(
            commandBuffer,
            gaussianBuffer,
            sortBuffer,
            frameUniformBuffer.nativeBuffer())) {
        reportFail(kTestName, "encodeDepthKeys failed: " + sortPass.lastDiagnostic());
        return false;
    }

    // CPU reference: expected index order (stable ascending sort of the
    // descending-depth keys, which the LSD radix sort must reproduce).
    std::vector<float> cpuDepth(kGaussianCount, 0.0f);
    std::vector<uint32_t> cpuKey(kGaussianCount, 0u);
    std::vector<std::pair<uint32_t, uint32_t>> keyedIndices;
    keyedIndices.reserve(kGaussianCount);
    for (std::size_t index = 0; index < kGaussianCount; ++index) {
        const float depth = view.viewDepth(
            gaussians[index].position[0],
            gaussians[index].position[1],
            gaussians[index].position[2]);
        cpuDepth[index] = depth;
        cpuKey[index] = descendingDepthKey(depth);
        keyedIndices.emplace_back(cpuKey[index], static_cast<uint32_t>(index));
    }
    std::stable_sort(
        keyedIndices.begin(),
        keyedIndices.end(),
        [](const std::pair<uint32_t, uint32_t>& lhs, const std::pair<uint32_t, uint32_t>& rhs) {
            return lhs.first < rhs.first;
        });

    // Read back the GPU-private sorted buffers: final keys and indices live in
    // the main key/index buffers (the even number of radix passes swaps back).
    mesh2splat::metal::MetalBuffer readbackBuffer(deviceContext);
    if (!readbackBuffer.createShared(
            kGaussianCount * sizeof(uint32_t),
            nullptr,
            "GpuSmokeTest Sort Readback")) {
        reportFail(kTestName, "readback buffer creation failed");
        return false;
    }

    if (!blitIndexBufferToReadback(
            (__bridge id<MTLCommandBuffer>)commandBuffer,
            sortBuffer.nativeIndexBuffer(),
            readbackBuffer.nativeBuffer(),
            kGaussianCount * sizeof(uint32_t))) {
        reportFail(kTestName, "readback blit encoder creation failed");
        return false;
    }

    if (!scheduler.commitAndWait(commandBuffer)) {
        const mesh2splat::metal::MetalCommandBufferDiagnostics diagnostics =
            mesh2splat::metal::MetalCommandScheduler::commandBufferDiagnostics(commandBuffer);
        reportFail(kTestName, "sort command buffer failed: " + diagnostics.statusDescription);
        return false;
    }

    std::vector<uint32_t> gpuIndices(kGaussianCount, 0u);
    if (!readbackBuffer.read(gpuIndices.data(), kGaussianCount * sizeof(uint32_t))) {
        reportFail(kTestName, "sort index readback failed");
        return false;
    }

    // 1) Output index list must match the CPU reference exactly.
    for (std::size_t position = 0; position < kGaussianCount; ++position) {
        if (gpuIndices[position] != keyedIndices[position].second) {
            reportFail(
                kTestName,
                "GPU index order diverges from CPU reference at position " +
                    std::to_string(position) + ": GPU=" + std::to_string(gpuIndices[position]) +
                    ", expected=" + std::to_string(keyedIndices[position].second));
            return false;
        }
    }

    // 2) Keys must be non-decreasing (ascending radix order) and the
    //    corresponding view depths strictly descending (farthest first),
    //    which is the convention Sort.metal 'descendingDepthKey' encodes.
    bool strictlyDescendingDepth = true;
    float previousDepth = cpuDepth[gpuIndices[0]];
    for (std::size_t position = 1; position < kGaussianCount; ++position) {
        const float depth = cpuDepth[gpuIndices[position]];
        if (!(depth < previousDepth)) {
            strictlyDescendingDepth = false;
            break;
        }
        previousDepth = depth;
    }
    if (!strictlyDescendingDepth) {
        reportFail(kTestName, "GPU index order does not produce strictly descending view depth");
        return false;
    }

    reportPass(kTestName);
    return true;
}

// ---------------------------------------------------------------------------
// Test 2: mesh conversion kernel output validation
// ---------------------------------------------------------------------------

bool testGpuMeshConversion(
    mesh2splat::metal::MetalDeviceContext& deviceContext,
    const std::string& shaderDir)
{
    const std::string kTestName = "gpu_mesh_conversion_valid_output";
    constexpr uint32_t kSamplesPerTriangle = 4;
    constexpr float kBoundsTolerance = 1.0e-3f;

    std::string errorMessage;

    mesh2splat::metal::MetalShaderLibrary shaderLibrary(deviceContext);
    if (!compileShaderSource(shaderDir, "Conversion.metal", shaderLibrary, errorMessage)) {
        reportFail(kTestName, errorMessage);
        return false;
    }

    mesh2splat::metal::MetalPipelineCache pipelineCache(deviceContext);
    mesh2splat::metal::MetalRenderStateCache renderStateCache(deviceContext);
    mesh2splat::metal::MetalConversionPass conversionPass;
    if (!conversionPass.initialize(shaderLibrary, pipelineCache, renderStateCache, &errorMessage)) {
        reportFail(kTestName, "conversion pass initialization failed: " + errorMessage);
        return false;
    }

    mesh2splat::core::SceneData scene;
    scene.name = "GPU smoke test scene";
    scene.meshes.push_back(mesh2splat::core::createPreviewTriangleMesh());
    scene.bounds = mesh2splat::core::aggregateSceneBounds(scene);

    mesh2splat::metal::MetalSceneResources sceneResources(deviceContext);
    if (!sceneResources.uploadScene(scene)) {
        reportFail(kTestName, "scene upload failed");
        return false;
    }

    const std::size_t plannedCapacity = sceneResources.conversionCapacity(kSamplesPerTriangle);
    if (plannedCapacity == 0) {
        reportFail(kTestName, "conversion capacity is zero for the preview triangle");
        return false;
    }

    mesh2splat::metal::MetalGaussianBuffer gaussianBuffer(deviceContext);
    if (!gaussianBuffer.create(plannedCapacity, "GpuSmokeTest Conversion Output")) {
        reportFail(kTestName, "conversion gaussian buffer creation failed: " +
            gaussianBuffer.lastErrorMessage());
        return false;
    }

    mesh2splat::metal::MetalCommandScheduler scheduler(deviceContext.nativeCommandQueue());
    void* commandBuffer = scheduler.createCommandBuffer("GpuSmokeTest Conversion");
    if (commandBuffer == nullptr) {
        reportFail(kTestName, "command buffer creation failed");
        return false;
    }

    if (!conversionPass.encode(commandBuffer, sceneResources, gaussianBuffer,
                               kSamplesPerTriangle, &errorMessage)) {
        reportFail(kTestName, "conversion encode failed: " + errorMessage);
        return false;
    }
    if (!scheduler.commitAndWait(commandBuffer)) {
        const mesh2splat::metal::MetalCommandBufferDiagnostics diagnostics =
            mesh2splat::metal::MetalCommandScheduler::commandBufferDiagnostics(commandBuffer);
        reportFail(kTestName, "conversion command buffer failed: " + diagnostics.statusDescription);
        return false;
    }

    if (!gaussianBuffer.readGpuCounter()) {
        reportFail(kTestName, "gpu counter readback failed: " + gaussianBuffer.lastErrorMessage());
        return false;
    }

    const uint32_t gpuCount = gaussianBuffer.count();
    if (gpuCount == 0 || gpuCount > gaussianBuffer.capacity()) {
        reportFail(
            kTestName,
            "gpu gaussian count out of range: count=" + std::to_string(gpuCount) +
                ", capacity=" + std::to_string(gaussianBuffer.capacity()));
        return false;
    }

    std::vector<mesh2splat::core::GaussianRecord> records;
    if (!gaussianBuffer.readback(records)) {
        reportFail(kTestName, "gaussian readback failed: " + gaussianBuffer.lastErrorMessage());
        return false;
    }
    if (records.size() != gpuCount) {
        reportFail(
            kTestName,
            "readback record count " + std::to_string(records.size()) +
                " does not match gpu counter " + std::to_string(gpuCount));
        return false;
    }

    const mesh2splat::core::MeshBounds& bounds = scene.bounds;
    for (std::size_t index = 0; index < records.size(); ++index) {
        const mesh2splat::core::GaussianRecord& record = records[index];
        for (int axis = 0; axis < 3; ++axis) {
            const float value = record.position[axis];
            if (!std::isfinite(value)) {
                reportFail(
                    kTestName,
                    "record " + std::to_string(index) + " position[" + std::to_string(axis) +
                        "] is not finite");
                return false;
            }
            if (value < bounds.min[axis] - kBoundsTolerance ||
                value > bounds.max[axis] + kBoundsTolerance) {
                reportFail(
                    kTestName,
                    "record " + std::to_string(index) + " position[" + std::to_string(axis) +
                        "]=" + std::to_string(value) +
                        " is outside mesh bounds [" + std::to_string(bounds.min[axis]) + ", " +
                        std::to_string(bounds.max[axis]) + "]");
                return false;
            }
        }
        for (int axis = 0; axis < 3; ++axis) {
            const float scale = record.scale[axis];
            if (!std::isfinite(scale) || !(scale > 0.0f)) {
                reportFail(
                    kTestName,
                    "record " + std::to_string(index) + " scale[" + std::to_string(axis) +
                        "] is not positive finite: " + std::to_string(scale));
                return false;
            }
        }
    }

    reportPass(kTestName);
    return true;
}

int main(int argc, char* argv[])
{
    const std::string shaderDir = findShaderDirectory(argc, argv);
    if (shaderDir.empty()) {
        std::cerr << "[FAIL] gpu_radix_sort_depth_order: shaders/metal directory not found "
                     "(pass it as argv[1] or set MESH2SPLAT_SHADER_DIR)\n";
        return 1;
    }

    id device = MTLCreateSystemDefaultDevice();
    if (device == nil) {
        std::cerr << "[FAIL] gpu_radix_sort_depth_order: MTLCreateSystemDefaultDevice returned nil\n";
        return 1;
    }

    mesh2splat::metal::MetalDeviceContext deviceContext((__bridge void*)device);
    if (!deviceContext.initialize() || !deviceContext.isValid()) {
        std::cerr << "[FAIL] gpu_radix_sort_depth_order: Metal device context initialization failed\n";
        return 1;
    }

    testGpuRadixSort(deviceContext, shaderDir);
    testGpuMeshConversion(deviceContext, shaderDir);

    if (g_failures != 0) {
        std::cerr << "MetalGpuSmokeTest: " << g_failures << " case(s) failed\n";
        return 1;
    }
    return 0;
}
