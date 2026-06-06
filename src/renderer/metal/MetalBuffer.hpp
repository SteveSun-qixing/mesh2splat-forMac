#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalDeviceContext;
class MetalResourceUploadBatch;

enum class MetalBufferMemoryPolicy : uint8_t {
    Unknown,
    Shared,
    SharedWriteCombined,
    Private
};

struct MetalBufferMemoryDiagnostics {
    MetalBufferMemoryPolicy policy = MetalBufferMemoryPolicy::Unknown;
    std::size_t size = 0;
    bool cpuAccessible = false;
    bool unifiedMemoryDevice = false;
    std::string label;
    std::string storageMode;
    std::string cpuCacheMode;
};

class MetalBuffer {
public:
    explicit MetalBuffer(MetalDeviceContext& deviceContext);
    ~MetalBuffer();

    MetalBuffer(const MetalBuffer&) = delete;
    MetalBuffer& operator=(const MetalBuffer&) = delete;

    MetalBuffer(MetalBuffer&&) noexcept;
    MetalBuffer& operator=(MetalBuffer&&) noexcept;

    bool createShared(std::size_t size, const void* initialData = nullptr, const char* label = nullptr);
    bool createSharedWriteCombined(std::size_t size, const void* initialData = nullptr, const char* label = nullptr);
    bool createPrivate(std::size_t size, const char* label = nullptr);
    bool createPrivateWithData(std::size_t size, const void* initialData, const char* label = nullptr);
    bool createPrivateWithData(
        std::size_t size,
        const void* initialData,
        MetalResourceUploadBatch& uploadBatch,
        const char* label = nullptr);
    bool update(const void* data, std::size_t size, std::size_t offset = 0);
    bool read(void* destination, std::size_t size, std::size_t offset = 0) const;
    bool encodeFill(void* commandBuffer, uint8_t value, std::size_t offset = 0, std::size_t size = 0) const;
    bool encodeCopyTo(
        void* commandBuffer,
        const MetalBuffer& destination,
        std::size_t size,
        std::size_t sourceOffset = 0,
        std::size_t destinationOffset = 0) const;

    bool isValid() const;
    bool isCpuAccessible() const;
    std::size_t size() const;
    void* nativeBuffer() const;
    MetalBufferMemoryPolicy memoryPolicy() const;
    MetalBufferMemoryDiagnostics memoryDiagnostics() const;
    std::string memoryDescription() const;

    static const char* memoryPolicyName(MetalBufferMemoryPolicy policy);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
