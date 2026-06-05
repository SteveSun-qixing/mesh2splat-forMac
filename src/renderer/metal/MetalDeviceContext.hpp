#pragma once

#include <memory>

namespace mesh2splat::metal {

class MetalDeviceContext {
public:
    explicit MetalDeviceContext(void* metalDevice);
    ~MetalDeviceContext();

    MetalDeviceContext(const MetalDeviceContext&) = delete;
    MetalDeviceContext& operator=(const MetalDeviceContext&) = delete;

    bool initialize();
    bool isValid() const;

    void* nativeDevice() const;
    void* nativeCommandQueue() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
