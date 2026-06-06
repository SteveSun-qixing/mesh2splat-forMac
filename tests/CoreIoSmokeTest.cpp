#include "core/CameraController.hpp"
#include "core/FrameData.hpp"
#include "core/GaussianData.hpp"
#include "core/GpuTypes.hpp"
#include "core/PrimitiveMeshFactory.hpp"
#include "core/SceneData.hpp"
#include "io/GltfLoader.hpp"
#include "io/PlyWriter.hpp"

#include <cmath>
#include <cstddef>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {

int fail(const std::string& message)
{
    std::cerr << "CoreIoSmokeTest failed: " << message << '\n';
    return 1;
}

bool isFiniteMatrix(const mesh2splat::core::Matrix4& matrix)
{
    for (float value : matrix.values) {
        if (!std::isfinite(value)) {
            return false;
        }
    }
    return true;
}

std::string readHeader(const std::filesystem::path& path)
{
    std::ifstream file(path, std::ios::binary);
    std::string header;
    std::string line;
    while (std::getline(file, line)) {
        header += line;
        header += '\n';
        if (line == "end_header") {
            break;
        }
    }
    return header;
}

} // namespace

int main()
{
    using namespace mesh2splat;

    core::MeshData mesh = core::createPreviewTriangleMesh();
    if (mesh.vertexCount() != 3 || mesh.drawRanges.size() != 1 || mesh.materials.size() != 1) {
        return fail("preview mesh shape is not stable");
    }

    core::SceneData scene;
    scene.name = "Core IO smoke scene";
    scene.meshes.push_back(mesh);
    scene.bounds = core::aggregateSceneBounds(scene);
    if (scene.meshCount() != 1 || scene.totalVertexCount() != 3 || scene.totalDrawRangeCount() != 1) {
        return fail("scene aggregation counters are not stable");
    }
    if (scene.bounds.min[0] > -0.64f || scene.bounds.max[1] < 0.64f) {
        return fail("scene bounds aggregation is not stable");
    }

    core::CameraController camera;
    camera.resize(1280, 720);
    camera.frameBounds(scene.bounds);
    core::InputState input;
    input.setKey(13, true);
    input.updateMousePosition(32.0, 16.0);
    input.setMouseButton(1, true);
    input.updateMousePosition(40.0, 20.0);
    input.addScrollDelta(0.0, 1.0);
    camera.update(input, 1.0 / 60.0);

    core::FrameUniforms uniforms = core::makeDefaultFrameUniforms(1280, 720);
    camera.writeFrameUniforms(uniforms);
    if (!isFiniteMatrix(uniforms.viewMatrix) ||
        !isFiniteMatrix(uniforms.projectionMatrix) ||
        !isFiniteMatrix(uniforms.modelViewProjectionMatrix)) {
        return fail("camera produced non-finite frame uniforms");
    }

    if (sizeof(core::GaussianRecord) != sizeof(float) * 4 * 6 ||
        core::gaussianBufferByteSize(2) != sizeof(core::GaussianRecord) * 2) {
        return fail("gaussian ABI size helpers are not stable");
    }

    core::GaussianRecord gaussian;
    gaussian.position[0] = 1.0f;
    gaussian.position[1] = 2.0f;
    gaussian.position[2] = 3.0f;
    gaussian.color[0] = 0.25f;
    gaussian.color[1] = 0.5f;
    gaussian.color[2] = 0.75f;
    gaussian.color[3] = 0.8f;
    gaussian.scale[0] = 0.05f;
    gaussian.scale[1] = 0.06f;
    gaussian.scale[2] = 0.04f;
    gaussian.normal[0] = 0.0f;
    gaussian.normal[1] = 1.0f;
    gaussian.normal[2] = 0.0f;
    gaussian.pbr[0] = 0.2f;
    gaussian.pbr[1] = 0.7f;

    const std::filesystem::path outputPath =
        std::filesystem::temp_directory_path() / "mesh2splat_core_io_smoke.ply";
    io::GaussianPlyWriteOptions plyOptions;
    plyOptions.format = io::GaussianPlyFormat::Pbr3DGS;
    plyOptions.scaleMultiplier = 1.0f;
    io::GaussianPlyWriteResult plyResult;
    if (!io::writeGaussianPly(outputPath.string(), std::vector<core::GaussianRecord>{gaussian}, plyOptions, &plyResult)) {
        return fail("PLY writer failed: " + plyResult.error);
    }
    if (plyResult.requestedCount != 1 || plyResult.writtenCount != 1) {
        return fail("PLY writer result counters are not stable");
    }

    const std::string header = readHeader(outputPath);
    std::filesystem::remove(outputPath);
    if (header.find("element vertex 1") == std::string::npos ||
        header.find("property float metallicFactor") == std::string::npos ||
        header.find("property float roughnessFactor") == std::string::npos) {
        return fail("PLY writer emitted an unexpected PBR header");
    }

    io::GltfSceneLoadResult gltfResult;
    if (io::loadGltfScene("", gltfResult) || gltfResult.error.empty()) {
        return fail("GLTF loader empty-path error handling is not stable");
    }

    return 0;
}
