#pragma once

#include "core/InputState.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalRenderer {
public:
    explicit MetalRenderer(void* metalDevice);
    ~MetalRenderer();

    MetalRenderer(const MetalRenderer&) = delete;
    MetalRenderer& operator=(const MetalRenderer&) = delete;

    bool initialize();
    bool loadMeshFile(const std::string& filePath);
    void resize(uint32_t width, uint32_t height);
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
