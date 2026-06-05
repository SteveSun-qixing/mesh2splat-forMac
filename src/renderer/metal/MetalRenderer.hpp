#pragma once

#include <cstdint>
#include <memory>

namespace mesh2splat::metal {

class MetalRenderer {
public:
    explicit MetalRenderer(void* metalDevice);
    ~MetalRenderer();

    MetalRenderer(const MetalRenderer&) = delete;
    MetalRenderer& operator=(const MetalRenderer&) = delete;

    bool initialize();
    void resize(uint32_t width, uint32_t height);
    void draw(void* renderPassDescriptor, void* drawable);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
