#pragma once

#include "core/InputState.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::metal {

enum class RenderViewMode : uint32_t {
    Combined = 0,
    MeshOnly = 1,
    GaussianOnly = 2,
};

class MetalRenderer {
public:
    explicit MetalRenderer(void* metalDevice);
    ~MetalRenderer();

    MetalRenderer(const MetalRenderer&) = delete;
    MetalRenderer& operator=(const MetalRenderer&) = delete;

    bool initialize();
    bool loadMeshFile(const std::string& filePath);
    void resize(uint32_t width, uint32_t height);
    void setViewMode(RenderViewMode mode);
    RenderViewMode viewMode() const;
    uint32_t convertedGaussianCount() const;
    const std::string& loadedMeshPath() const;
    void draw(
        void* renderPassDescriptor,
        void* drawable,
        const core::InputState& inputState,
        double deltaTimeSeconds);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
