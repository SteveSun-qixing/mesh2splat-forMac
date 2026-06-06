///////////////////////////////////////////////////////////////////////////////
//         Mesh2Splat: fast mesh to 3D gaussian splat conversion             //
//        Copyright (c) 2025 Electronic Arts Inc. All rights reserved.       //
///////////////////////////////////////////////////////////////////////////////

#pragma once

#include "core/GaussianData.hpp"
#include "core/SceneData.hpp"
#include "io/GltfLoader.hpp"
#include "io/PlyWriter.hpp"

#if __has_include(<GL/glew.h>) && __has_include(<GLFW/glfw3.h>)
#include "utils/Camera.hpp"
#else
class Camera;
struct GLFWwindow;
#endif

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::renderer {

using RendererGaussianPlyFormat = io::GaussianPlyFormat;

struct RendererIoLoadResult {
    bool loaded = false;
    core::SceneData scene;
    std::string warning;
    std::string error;
    std::string diagnostic;

    bool succeeded() const
    {
        return loaded && error.empty() && !scene.empty();
    }

    explicit operator bool() const
    {
        return succeeded();
    }
};

struct RendererIoSaveOptions {
    RendererGaussianPlyFormat format = RendererGaussianPlyFormat::Standard3DGS;
    float scaleMultiplier = 1.0f;
    bool skipInvalidRecords = true;
};

struct RendererIoSaveResult {
    bool saved = false;
    uint64_t requestedCount = 0;
    uint64_t writtenCount = 0;
    std::string error;
    std::string diagnostic;

    bool succeeded() const
    {
        return saved && error.empty();
    }

    explicit operator bool() const
    {
        return succeeded();
    }
};

class RendererIoBridge {
public:
    static RendererIoLoadResult loadScene(const std::string& filePath)
    {
        RendererIoLoadResult bridgeResult;

        io::GltfSceneLoadResult loadResult;
        bridgeResult.loaded = io::loadGltfScene(filePath, loadResult);
        bridgeResult.scene = std::move(loadResult.scene);
        bridgeResult.warning = std::move(loadResult.warning);
        bridgeResult.error = std::move(loadResult.error);
        bridgeResult.diagnostic = joinDiagnostics(bridgeResult.warning, bridgeResult.error);
        return bridgeResult;
    }

    static bool loadScene(
        const std::string& filePath,
        core::SceneData& scene,
        std::string* diagnostic = nullptr)
    {
        RendererIoLoadResult result = loadScene(filePath);
        if (diagnostic != nullptr) {
            *diagnostic = result.diagnostic;
        }
        if (!result.succeeded()) {
            return false;
        }

        scene = std::move(result.scene);
        return true;
    }

    static RendererIoSaveResult saveGaussianPly(
        const std::string& filePath,
        const std::vector<core::GaussianRecord>& gaussians,
        const RendererIoSaveOptions& options = {})
    {
        io::GaussianPlyWriteOptions writeOptions;
        writeOptions.format = options.format;
        writeOptions.scaleMultiplier = options.scaleMultiplier;
        writeOptions.skipInvalidRecords = options.skipInvalidRecords;

        io::GaussianPlyWriteResult writeResult;
        const bool saved = io::writeGaussianPly(filePath, gaussians, writeOptions, &writeResult);

        RendererIoSaveResult bridgeResult;
        bridgeResult.saved = saved;
        bridgeResult.requestedCount = writeResult.requestedCount;
        bridgeResult.writtenCount = writeResult.writtenCount;
        bridgeResult.error = std::move(writeResult.error);
        bridgeResult.diagnostic = bridgeResult.error;
        return bridgeResult;
    }

    static bool saveGaussianPly(
        const std::string& filePath,
        const std::vector<core::GaussianRecord>& gaussians,
        std::string* diagnostic)
    {
        return saveGaussianPly(filePath, gaussians, RendererIoSaveOptions{}, diagnostic);
    }

    static bool saveGaussianPly(
        const std::string& filePath,
        const std::vector<core::GaussianRecord>& gaussians,
        const RendererIoSaveOptions& options,
        std::string* diagnostic)
    {
        RendererIoSaveResult result = saveGaussianPly(filePath, gaussians, options);
        if (diagnostic != nullptr) {
            *diagnostic = result.diagnostic;
        }
        return result.succeeded();
    }

private:
    static std::string joinDiagnostics(const std::string& warning, const std::string& error)
    {
        if (warning.empty()) {
            return error;
        }
        if (error.empty()) {
            return warning;
        }
        return warning + "\n" + error;
    }
};

} // namespace mesh2splat::renderer

class IoHandler {
public:
    IoHandler(GLFWwindow* window, Camera& camera);
    void setupCallbacks();
    void processInput(float deltaTime);

private:
    static void mouseButtonCallback(GLFWwindow* window, int button, int action, int mods);
    static void cursorPositionCallback(GLFWwindow* window, double xpos, double ypos);
    static void scrollCallback(GLFWwindow* window, double xoffset, double yoffset);
    static void keyCallback(GLFWwindow* window, int key, int scancode, int action, int mods);

    Camera* camera; 
    GLFWwindow* window;

    // Internal state
    static bool mouseDragging;
    static bool firstMouse;
    static bool keys[1024];
};
