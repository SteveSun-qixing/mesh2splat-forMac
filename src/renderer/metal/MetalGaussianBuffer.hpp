#pragma once

#include "core/GaussianData.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

namespace mesh2splat::metal {

class MetalDeviceContext;

class MetalGaussianBuffer {
public:
    explicit MetalGaussianBuffer(MetalDeviceContext& deviceContext);
    ~MetalGaussianBuffer();

    MetalGaussianBuffer(const MetalGaussianBuffer&) = delete;
    MetalGaussianBuffer& operator=(const MetalGaussianBuffer&) = delete;

    MetalGaussianBuffer(MetalGaussianBuffer&&) noexcept;
    MetalGaussianBuffer& operator=(MetalGaussianBuffer&&) noexcept;

    bool create(std::size_t capacity, const char* label = nullptr);
    bool upload(const std::vector<core::GaussianRecord>& gaussians, const char* label = nullptr);
    bool setCount(uint32_t count);
    bool encodeResetGpuCounter(void* commandBuffer);
    bool encodeReadbackGpuCounter(void* commandBuffer);
    bool readGpuCounter();
    void reset();

    bool isValid() const;
    std::size_t capacity() const;
    uint32_t count() const;
    std::size_t sizeBytes() const;
    std::size_t totalSizeBytes() const;
    void* nativeBuffer() const;
    void* nativeCounterBuffer() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
