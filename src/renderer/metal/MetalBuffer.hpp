#pragma once

#include <cstddef>
#include <memory>

namespace mesh2splat::metal {

class MetalDeviceContext;

class MetalBuffer {
public:
    explicit MetalBuffer(MetalDeviceContext& deviceContext);
    ~MetalBuffer();

    MetalBuffer(const MetalBuffer&) = delete;
    MetalBuffer& operator=(const MetalBuffer&) = delete;

    MetalBuffer(MetalBuffer&&) noexcept;
    MetalBuffer& operator=(MetalBuffer&&) noexcept;

    bool createShared(std::size_t size, const void* initialData = nullptr, const char* label = nullptr);
    bool createPrivate(std::size_t size, const char* label = nullptr);
    bool update(const void* data, std::size_t size, std::size_t offset = 0);
    bool read(void* destination, std::size_t size, std::size_t offset = 0) const;

    bool isValid() const;
    bool isCpuAccessible() const;
    std::size_t size() const;
    void* nativeBuffer() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
