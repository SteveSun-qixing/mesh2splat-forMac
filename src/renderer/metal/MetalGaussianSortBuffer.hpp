#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>

namespace mesh2splat::metal {

class MetalDeviceContext;

class MetalGaussianSortBuffer {
public:
    explicit MetalGaussianSortBuffer(MetalDeviceContext& deviceContext);
    ~MetalGaussianSortBuffer();

    MetalGaussianSortBuffer(const MetalGaussianSortBuffer&) = delete;
    MetalGaussianSortBuffer& operator=(const MetalGaussianSortBuffer&) = delete;

    MetalGaussianSortBuffer(MetalGaussianSortBuffer&&) noexcept;
    MetalGaussianSortBuffer& operator=(MetalGaussianSortBuffer&&) noexcept;

    bool create(std::size_t capacity, const char* label = nullptr);
    bool setCount(uint32_t count);
    void reset();

    bool isValid() const;
    std::size_t capacity() const;
    uint32_t count() const;
    void* nativeKeyBuffer() const;
    void* nativeIndexBuffer() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
