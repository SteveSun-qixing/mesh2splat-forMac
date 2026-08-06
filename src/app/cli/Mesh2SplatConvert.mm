#include "core/AssetFileTypes.hpp"
#include "core/GaussianData.hpp"
#include "io/GltfLoader.hpp"
#include "io/PlyReader.hpp"
#include "renderer/RendererInterface.hpp"

#import <Metal/Metal.h>

#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

// ---------------------------------------------------------------------------
// Mesh2SplatConvert: headless mesh -> gaussian -> PLY converter.
//
// The converter drives the production Metal renderer through its public API:
// loadScene -> startConversion -> pumpPendingConversion -> exportPly. No
// window, view, or drawable is required; the renderer's asynchronous state
// machine is advanced with pumpPendingConversion().
// ---------------------------------------------------------------------------

namespace {

using mesh2splat::core::isFiniteGaussianRecord;
using mesh2splat::core::hasUsableGaussianScale;
using mesh2splat::renderer::Renderer;
using mesh2splat::renderer::RendererSceneKind;
using mesh2splat::renderer::RendererSceneLoadRequest;
using mesh2splat::renderer::RendererConversionRequest;
using mesh2splat::renderer::RendererExportPlyRequest;
using mesh2splat::renderer::RendererExportPlyResult;
using mesh2splat::renderer::RendererRuntimeState;

constexpr uint32_t kDefaultCliSamplesPerTriangle = 8;
constexpr float kDefaultScaleMultiplier = 1.0f;
constexpr uint64_t kConversionTimeoutMilliseconds = 120000;
constexpr uint64_t kPreviewPumpTimeoutMilliseconds = 15000;
constexpr uint32_t kPumpSleepMilliseconds = 20;

using Clock = std::chrono::steady_clock;

struct Options {
    std::string inputPath;
    std::string outputPath;
    uint32_t samplesPerTriangle = kDefaultCliSamplesPerTriangle;
    uint32_t plyFormat = 1;
    float scaleMultiplier = kDefaultScaleMultiplier;
    bool stats = false;
    bool verify = false;
    bool inputIsPly = false;
};

int fail(const std::string& message)
{
    std::cerr << "Mesh2SplatConvert failed: " << message << '\n';
    return 1;
}

int usage(const std::string& message = {})
{
    if (!message.empty()) {
        std::cerr << "Mesh2SplatConvert: " << message << "\n\n";
    }
    std::cerr <<
        "Usage: Mesh2SplatConvert <input.(glb|gltf|ply)> <output.ply> [options]\n"
        "\n"
        "Options:\n"
        "  --samples N         gaussian samples per mesh triangle (default 8)\n"
        "  --format NAME       export format: pbr3dgs (default) or 3dgs\n"
        "  --scale MULT        gaussian scale multiplier applied on export (default 1.0)\n"
        "  --verify            read the exported PLY back and validate gaussian records\n"
        "  --stats             print renderer resource and timing statistics\n"
        "\n"
        "A .ply input is re-imported and re-exported without mesh conversion.\n";
    return 2;
}

bool parseUInt32(const char* text, uint32_t& output)
{
    if (text == nullptr || text[0] == '\0') {
        return false;
    }
    char* end = nullptr;
    errno = 0;
    const unsigned long value = std::strtoul(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || value > 0xFFFFFFFFul) {
        return false;
    }
    output = static_cast<uint32_t>(value);
    return true;
}

bool parseFloat(const char* text, float& output)
{
    if (text == nullptr || text[0] == '\0') {
        return false;
    }
    char* end = nullptr;
    errno = 0;
    const float value = std::strtof(text, &end);
    if (errno != 0 || end == text || *end != '\0' || !std::isfinite(value)) {
        return false;
    }
    output = value;
    return true;
}

int parseArguments(int argc, char** argv, Options& options)
{
    if (argc < 3) {
        return usage();
    }

    options.inputPath = argv[1];
    options.outputPath = argv[2];

    const std::string inputExtension(options.inputPath.empty()
        ? std::string{}
        : std::string(mesh2splat::core::assetFileExtensionFromPath(options.inputPath)));
    if (inputExtension != "glb" && inputExtension != "gltf" && inputExtension != "ply") {
        return usage("input file must be .glb, .gltf, or .ply: " + options.inputPath);
    }
    if (options.outputPath.empty() ||
        mesh2splat::core::assetFileKindFromPath(options.outputPath) !=
            mesh2splat::core::AssetFileKind::Ply) {
        return usage("output file must have a .ply extension: " + options.outputPath);
    }
    if (!std::filesystem::exists(options.inputPath)) {
        return usage("input file does not exist: " + options.inputPath);
    }
    options.inputIsPly = inputExtension == "ply";

    for (int index = 3; index < argc; ++index) {
        const std::string argument = argv[index];
        if (argument == "--samples") {
            if (index + 1 >= argc || !parseUInt32(argv[index + 1], options.samplesPerTriangle)) {
                return usage("--samples requires a positive integer value");
            }
            if (options.samplesPerTriangle == 0) {
                return usage("--samples must be at least 1");
            }
            ++index;
        } else if (argument == "--format") {
            if (index + 1 >= argc) {
                return usage("--format requires a name: pbr3dgs or 3dgs");
            }
            const std::string formatName = argv[index + 1];
            if (formatName == "pbr3dgs" || formatName == "pbr") {
                options.plyFormat = 1;
            } else if (formatName == "3dgs" || formatName == "standard") {
                options.plyFormat = 0;
            } else {
                return usage("unknown --format value: " + formatName);
            }
            ++index;
        } else if (argument == "--scale") {
            if (index + 1 >= argc || !parseFloat(argv[index + 1], options.scaleMultiplier)) {
                return usage("--scale requires a finite number");
            }
            if (options.scaleMultiplier <= 0.0f) {
                return usage("--scale must be positive");
            }
            ++index;
        } else if (argument == "--stats") {
            options.stats = true;
        } else if (argument == "--verify") {
            options.verify = true;
        } else {
            return usage("unknown argument: " + argument);
        }
    }

    return 0;
}

std::string rendererStateName(mesh2splat::renderer::RendererRuntimeState state)
{
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

std::string formatSeconds(double seconds)
{
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%.1f s", seconds);
    return buffer;
}

std::string formatBytes(uint64_t bytes)
{
    char buffer[64];
    if (bytes >= 1024ull * 1024ull * 1024ull) {
        std::snprintf(buffer, sizeof(buffer), "%.2f GB", static_cast<double>(bytes) / (1024.0 * 1024.0 * 1024.0));
    } else if (bytes >= 1024ull * 1024ull) {
        std::snprintf(buffer, sizeof(buffer), "%.2f MB", static_cast<double>(bytes) / (1024.0 * 1024.0));
    } else if (bytes >= 1024ull) {
        std::snprintf(buffer, sizeof(buffer), "%.2f KB", static_cast<double>(bytes) / 1024.0);
    } else {
        std::snprintf(buffer, sizeof(buffer), "%llu B", static_cast<unsigned long long>(bytes));
    }
    return buffer;
}

bool pumpUntilIdle(Renderer& renderer, uint64_t timeoutMilliseconds)
{
    const Clock::time_point start = Clock::now();
    while (renderer.isConvertingGaussians()) {
        const double elapsedMilliseconds =
            std::chrono::duration<double, std::milli>(Clock::now() - start).count();
        if (elapsedMilliseconds >= static_cast<double>(timeoutMilliseconds)) {
            return false;
        }
        if (renderer.runtimeState() == RendererRuntimeState::Failed) {
            return false;
        }
        if (!renderer.pumpPendingConversion()) {
            return false;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(kPumpSleepMilliseconds));
    }
    return true;
}

void printRendererFailure(const Renderer& renderer)
{
    const std::string error = renderer.lastError();
    const std::string diagnostic = renderer.lastDiagnostic();
    if (!error.empty() && error != diagnostic) {
        std::cerr << "  lastError: " << error << '\n';
    }
    if (!diagnostic.empty()) {
        std::cerr << "  lastDiagnostic: " << diagnostic << '\n';
    }
    if (error.empty() && diagnostic.empty()) {
        std::cerr << "  runtimeState: "
                  << rendererStateName(renderer.runtimeState()) << '\n';
    }
}

void printSceneStats(const Options& options)
{
    if (options.inputIsPly) {
        std::vector<mesh2splat::core::GaussianRecord> gaussians;
        mesh2splat::io::GaussianPlyReadResult result;
        if (!mesh2splat::io::readGaussianPly(
                options.inputPath,
                gaussians,
                mesh2splat::io::GaussianPlyReadOptions{},
                &result)) {
            std::cout << "[scene] input PLY read failed: " << result.error << '\n';
            return;
        }
        std::cout << "[scene] " << options.inputPath
                  << " ply gaussians=" << gaussians.size()
                  << " skipped=" << result.skippedInvalidCount
                  << " encoding="
                  << (result.encoding == mesh2splat::io::GaussianPlyEncoding::Ascii
                          ? "ascii"
                          : result.encoding == mesh2splat::io::GaussianPlyEncoding::BinaryLittleEndian
                              ? "binary-little-endian"
                              : "unknown")
                  << '\n';
        return;
    }

    mesh2splat::io::GltfSceneLoadResult loadResult;
    if (!mesh2splat::io::loadGltfScene(options.inputPath, loadResult)) {
        std::cout << "[scene] glTF parse failed: " << loadResult.error << '\n';
        return;
    }
    const mesh2splat::core::SceneData& scene = loadResult.scene;
    const mesh2splat::io::GltfSceneLoadStats& stats = loadResult.stats;
    std::cout << "[scene] " << options.inputPath
              << " meshes=" << scene.meshCount()
              << " vertices=" << scene.totalVertexCount()
              << " triangles=" << scene.totalDrawRangeCount()
              << " materials=" << scene.materials.size()
              << " textures=" << scene.textures.size()
              << " primitives=" << stats.loadedPrimitiveCount
              << " sourceNodes=" << stats.sourceNodeCount
              << " sourceMeshes=" << stats.sourceMeshCount
              << " sourceMaterials=" << stats.sourceMaterialCount
              << " sourceTextures=" << stats.sourceTextureCount;
    if (!loadResult.warning.empty()) {
        std::cout << " warning=\"" << loadResult.warning << "\"";
    }
    std::cout << '\n';
}

int verifyExportedPly(const Options& options, uint64_t expectedCount)
{
    std::vector<mesh2splat::core::GaussianRecord> gaussians;
    mesh2splat::io::GaussianPlyReadResult result;
    if (!mesh2splat::io::readGaussianPly(
            options.outputPath,
            gaussians,
            mesh2splat::io::GaussianPlyReadOptions{},
            &result)) {
        return fail("verify: exported PLY could not be read back: " + result.error);
    }
    if (result.readCount != expectedCount) {
        return fail("verify: exported PLY read count mismatch: " +
            std::to_string(result.readCount) + " != expected " + std::to_string(expectedCount));
    }

    uint64_t nonFiniteCount = 0;
    uint64_t invalidScaleCount = 0;
    for (const mesh2splat::core::GaussianRecord& gaussian : gaussians) {
        if (!isFiniteGaussianRecord(gaussian)) {
            ++nonFiniteCount;
        }
        if (!hasUsableGaussianScale(gaussian)) {
            ++invalidScaleCount;
        }
    }

    std::cout << "[verify] read back " << gaussians.size()
              << " gaussians (skipped=" << result.skippedInvalidCount << ")"
              << " nonFinite=" << nonFiniteCount
              << " invalidScale=" << invalidScaleCount;
    if (nonFiniteCount == 0 && invalidScaleCount == 0) {
        std::cout << " -> all position/color/scale records are finite and valid";
    }
    std::cout << '\n';

    if (nonFiniteCount != 0 || invalidScaleCount != 0) {
        return fail("verify: exported PLY contains invalid gaussian records");
    }
    return 0;
}

} // namespace

int main(int argc, char** argv)
{
    Options options;
    int argumentStatus = parseArguments(argc, argv, options);
    if (argumentStatus != 0) {
        return argumentStatus;
    }

    std::cout << "[init] Mesh2SplatConvert (Mesh2Splat Metal, headless CLI)\n";

    id<MTLDevice> metalDevice = MTLCreateSystemDefaultDevice();
    if (metalDevice == nil) {
        return fail("no Metal device available in this session (MTLCreateSystemDefaultDevice returned nil)");
    }
    std::cout << "[init] Metal device: "
              << (metalDevice.name != nil ? metalDevice.name.UTF8String : "unknown") << '\n';

    std::unique_ptr<Renderer> renderer =
        mesh2splat::renderer::createMetalRenderer((__bridge void*)metalDevice);
    if (renderer == nullptr) {
        return fail("createMetalRenderer returned nullptr");
    }

    if (!renderer->initialize()) {
        std::cerr << "[init] renderer initialize() returned false\n";
        printRendererFailure(*renderer);
        return 1;
    }
    std::cout << "[init] renderer initialized (samples default="
              << renderer->conversionSamplesPerTriangle() << ")\n";

    // initialize() auto-submits a conversion for the built-in preview mesh;
    // let it settle so later calls are not rejected while a conversion is
    // still pending.
    if (!pumpUntilIdle(*renderer, kPreviewPumpTimeoutMilliseconds)) {
        std::cerr << "[init] preview conversion did not settle\n";
        printRendererFailure(*renderer);
        return 1;
    }

    printSceneStats(options);

    if (!options.inputIsPly) {
        // Configure the conversion quality before the scene load: loading a
        // mesh auto-submits a conversion with the renderer's current samples,
        // so the sample count must be set (on the tiny preview scene) first.
        RendererConversionRequest sampleRequest;
        sampleRequest.samplesPerTriangle = options.samplesPerTriangle;
        sampleRequest.forceRebuild = true;
        const mesh2splat::renderer::RendererConversionResult sampleResult =
            renderer->startConversion(sampleRequest);
        if (!sampleResult.started && !sampleResult.accepted) {
            std::cerr << "[convert] startConversion (quality setup) was rejected\n";
            if (!sampleResult.diagnostic.empty()) {
                std::cerr << "  diagnostic: " << sampleResult.diagnostic << '\n';
            }
            printRendererFailure(*renderer);
            return 1;
        }
        if (!pumpUntilIdle(*renderer, kPreviewPumpTimeoutMilliseconds)) {
            std::cerr << "[convert] quality setup conversion did not settle\n";
            printRendererFailure(*renderer);
            return 1;
        }
    }

    RendererSceneLoadRequest loadRequest;
    loadRequest.filePath = options.inputPath;
    loadRequest.kind = RendererSceneKind::Auto;
    loadRequest.replaceCurrentScene = true;
    const Clock::time_point loadStart = Clock::now();
    const mesh2splat::renderer::RendererSceneLoadResult loadResult =
        renderer->loadScene(loadRequest);
    const double loadSeconds =
        std::chrono::duration<double>(Clock::now() - loadStart).count();
    if (!loadResult.loaded) {
        std::cerr << "[load] loadScene returned loaded=false after "
                  << formatSeconds(loadSeconds) << "\n";
        printRendererFailure(*renderer);
        return 1;
    }
    std::cout << "[load] scene loaded in " << formatSeconds(loadSeconds)
              << " kind=" << (loadResult.kind == RendererSceneKind::Mesh ? "mesh" : "gaussian-ply")
              << " displayName=" << loadResult.displayName << '\n';

    if (options.inputIsPly) {
        const uint32_t importedCount = renderer->convertedGaussianCount();
        std::cout << "[convert] skipped (ply input); imported gaussians="
                  << importedCount << '\n';
        if (importedCount == 0) {
            return fail("PLY import produced zero gaussians");
        }
    } else {
        // The scene load already submitted a conversion with the requested
        // samples; wait for it to finish.
        const Clock::time_point conversionStart = Clock::now();
        const bool settled = pumpUntilIdle(*renderer, kConversionTimeoutMilliseconds);
        const double conversionSeconds =
            std::chrono::duration<double>(Clock::now() - conversionStart).count();
        if (!settled) {
            std::cerr << "[convert] conversion did not complete within "
                      << (kConversionTimeoutMilliseconds / 1000) << " s\n";
            printRendererFailure(*renderer);
            return 1;
        }
        const uint32_t gaussianCount = renderer->convertedGaussianCount();
        std::cout << "[convert] gaussians=" << gaussianCount
                  << " samples=" << options.samplesPerTriangle
                  << " (renderer effective=" << renderer->conversionSamplesPerTriangle() << ")"
                  << " time=" << formatSeconds(conversionSeconds);
        if (renderer->runtimeState() == RendererRuntimeState::Failed) {
            std::cout << " state=failed";
        }
        std::cout << '\n';
        if (gaussianCount == 0) {
            std::cerr << "[convert] conversion produced zero gaussians\n";
            printRendererFailure(*renderer);
            return 1;
        }
    }

    RendererExportPlyRequest exportRequest;
    exportRequest.filePath = options.outputPath;
    exportRequest.format = options.plyFormat;
    exportRequest.scaleMultiplier = options.scaleMultiplier;
    exportRequest.skipInvalidRecords = true;
    const Clock::time_point exportStart = Clock::now();
    const RendererExportPlyResult exportResult = renderer->exportPly(exportRequest);
    const double exportSeconds =
        std::chrono::duration<double>(Clock::now() - exportStart).count();
    if (!exportResult.exported) {
        std::cerr << "[export] exportPly failed after " << formatSeconds(exportSeconds) << "\n";
        std::cerr << "  diagnostic: " << exportResult.diagnostic << '\n';
        printRendererFailure(*renderer);
        return 1;
    }

    uint64_t outputFileBytes = 0;
    std::error_code fileError;
    const auto fileSize = std::filesystem::file_size(options.outputPath, fileError);
    if (!fileError) {
        outputFileBytes = static_cast<uint64_t>(fileSize);
    }
    std::cout << "[export] format=" << (options.plyFormat == 1 ? "pbr3dgs" : "3dgs")
              << " scale=" << options.scaleMultiplier
              << " requested=" << exportResult.requestedCount
              << " written=" << exportResult.writtenCount
              << " file=" << options.outputPath
              << " size=" << formatBytes(outputFileBytes)
              << " time=" << formatSeconds(exportSeconds) << '\n';
    if (!exportResult.diagnostic.empty()) {
        std::cout << "[export] renderer diagnostic: " << exportResult.diagnostic << '\n';
    }

    if (options.verify) {
        const int verifyStatus = verifyExportedPly(options, exportResult.writtenCount);
        if (verifyStatus != 0) {
            return verifyStatus;
        }
    }

    if (options.stats) {
        const mesh2splat::renderer::RendererStats stats = renderer->rendererStats();
        std::cout << "[stats] frames submitted=" << stats.submittedFrameCount
                  << " completed=" << stats.completedFrameCount
                  << " failed=" << stats.failedFrameCount << '\n';
        std::cout << "[stats] conversions submitted=" << stats.submittedConversionCount
                  << " completed=" << stats.completedConversionCount
                  << " failed=" << stats.failedConversionCount
                  << " lastGpuMs=" << stats.lastConversionGpuMs
                  << " avgGpuMs=" << stats.averageConversionGpuMs
                  << " lastCpuSubmitMs=" << stats.lastConversionCpuSubmitMs
                  << " avgCpuSubmitMs=" << stats.averageConversionCpuSubmitMs << '\n';
        std::cout << "[stats] resources frameUniform=" << formatBytes(stats.frameUniformResourceBytes)
                  << " scene=" << formatBytes(stats.sceneResourceBytes)
                  << " gaussians=" << formatBytes(stats.gaussianResourceBytes)
                  << " sort=" << formatBytes(stats.gaussianSortResourceBytes)
                  << " shadow=" << formatBytes(stats.shadowResourceBytes)
                  << " pending=" << formatBytes(stats.pendingConversionResourceBytes)
                  << " trackedTotal=" << formatBytes(stats.trackedResourceBytes) << '\n';
    }

    std::cout << "[done] Mesh2SplatConvert succeeded\n";
    return 0;
}
