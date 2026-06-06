#pragma once

#include <cstddef>
#include <cstdint>

namespace mesh2splat::metal {

class MetalResourceUploader {
public:
    MetalResourceUploader(void* metalDevice, void* commandQueue);

    bool uploadBufferToPrivate(
        const void* data,
        std::size_t size,
        void* destinationBuffer,
        const char* label = nullptr) const;

    bool uploadTexture2DToPrivate(
        const void* data,
        std::size_t sourceBytesPerRow,
        std::size_t copyBytesPerRow,
        std::size_t destinationBytesPerRow,
        std::size_t uploadSize,
        uint32_t width,
        uint32_t height,
        uint32_t mipLevel,
        void* destinationTexture,
        const char* label = nullptr) const;

private:
    void* m_device = nullptr;
    void* m_commandQueue = nullptr;
};

} // namespace mesh2splat::metal
