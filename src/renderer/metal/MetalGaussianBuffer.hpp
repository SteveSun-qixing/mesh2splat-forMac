#pragma once

#include "core/GaussianData.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace mesh2splat::metal {

class MetalDeviceContext;

struct MetalGaussianBufferResourceStats {
    std::size_t capacity = 0;
    uint32_t count = 0;
    std::size_t recordStrideBytes = 0;
    std::size_t dataBytes = 0;
    std::size_t counterBytes = 0;
    std::size_t counterReadbackBytes = 0;
    std::size_t totalBytes = 0;
};

struct MetalGaussianBounds {
    std::array<float, 3> min = {0.0f, 0.0f, 0.0f};
    std::array<float, 3> max = {0.0f, 0.0f, 0.0f};
    std::array<float, 3> center = {0.0f, 0.0f, 0.0f};
    float radius = 0.0f;
    bool valid = false;
};

struct MetalGaussianVisibilityStats {
    std::size_t inputCount = 0;
    std::size_t validRecordCount = 0;
    std::size_t invalidRecordCount = 0;
    std::size_t alphaZeroCount = 0;
    std::size_t degenerateScaleCount = 0;
    std::size_t visibleCount = 0;

    std::size_t rejectedCount() const
    {
        return invalidRecordCount + alphaZeroCount + degenerateScaleCount;
    }
};

struct MetalGaussianBufferDiagnostics {
    bool valid = false;
    std::size_t capacity = 0;
    uint32_t count = 0;
    std::size_t sizeBytes = 0;
    std::size_t totalSizeBytes = 0;
    MetalGaussianBounds bounds = {};
    MetalGaussianVisibilityStats visibility = {};
    std::string lastErrorMessage;
};

class MetalGaussianBuffer {
public:
    explicit MetalGaussianBuffer(MetalDeviceContext& deviceContext);
    ~MetalGaussianBuffer();

    MetalGaussianBuffer(const MetalGaussianBuffer&) = delete;
    MetalGaussianBuffer& operator=(const MetalGaussianBuffer&) = delete;

    MetalGaussianBuffer(MetalGaussianBuffer&&) noexcept;
    MetalGaussianBuffer& operator=(MetalGaussianBuffer&&) noexcept;

    bool create(std::size_t capacity, const char* label = nullptr);
    bool resize(std::size_t capacity, const char* label = nullptr);
    bool ensureCapacity(std::size_t capacity, const char* label = nullptr);
    bool upload(const std::vector<core::GaussianRecord>& gaussians, const char* label = nullptr);
    bool setCount(uint32_t count);
    bool encodeResetGpuCounter(void* commandBuffer);
    bool encodeReadbackGpuCounter(void* commandBuffer);
    bool readGpuCounter();
    void reset();

    bool isValid() const;
    bool hasCapacityFor(std::size_t count) const;
    std::size_t capacity() const;
    uint32_t count() const;
    const std::string& lastErrorMessage() const;
    std::size_t sizeBytes() const;
    std::size_t totalSizeBytes() const;
    MetalGaussianBufferResourceStats resourceStats() const;
    MetalGaussianBounds bounds() const;
    const MetalGaussianVisibilityStats& visibilityStats() const;
    MetalGaussianBufferDiagnostics diagnostics() const;
    std::string diagnosticSummary() const;
    void* nativeBuffer() const;
    void* nativeCounterBuffer() const;
    void* nativeCounterReadbackBuffer() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
