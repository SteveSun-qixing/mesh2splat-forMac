#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalResourceUploadBatch {
public:
    enum class Status {
        NotReady,
        Ready,
        Failed,
        Committed,
        Completed,
        Cancelled
    };

    struct Stats {
        uint32_t bufferUploads = 0;
        uint32_t textureUploads = 0;
        std::size_t stagingBytes = 0;
    };

    struct Result {
        Status status = Status::NotReady;
        Stats stats;
        bool completed = false;
        int commandBufferStatus = -1;
        double gpuMilliseconds = 0.0;
        std::string commandLabel;
        std::string blitLabel;
        std::string commandBufferLabel;
        std::string statusDescription;
        std::string errorMessage;
    };

    using CompletionHandler = void (*)(const Result& result, void* userData);

    MetalResourceUploadBatch(
        void* metalDevice,
        void* commandQueue,
        const char* commandLabel = nullptr,
        const char* blitLabel = nullptr);
    ~MetalResourceUploadBatch();

    MetalResourceUploadBatch(const MetalResourceUploadBatch&) = delete;
    MetalResourceUploadBatch& operator=(const MetalResourceUploadBatch&) = delete;

    bool isValid() const;
    Status status() const;
    const Stats& stats() const;
    const std::string& lastErrorMessage() const;
    Result result() const;

    bool uploadBufferToPrivate(
        const void* data,
        std::size_t size,
        void* destinationBuffer,
        const char* label = nullptr);

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
        const char* label = nullptr);

    bool commitAndWait();
    bool commitAndWait(std::string* errorMessage);
    bool commitAsync(CompletionHandler completion = nullptr, void* userData = nullptr);

private:
    struct Impl;
    std::shared_ptr<Impl> m_impl;
};

class MetalResourceUploader {
public:
    MetalResourceUploader(void* metalDevice, void* commandQueue);

    bool uploadBufferToPrivate(
        const void* data,
        std::size_t size,
        void* destinationBuffer,
        const char* label = nullptr) const;

    bool uploadBufferToPrivate(
        const void* data,
        std::size_t size,
        void* destinationBuffer,
        const char* label,
        std::string* errorMessage) const;

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
        const char* label,
        std::string* errorMessage) const;

private:
    void* m_device = nullptr;
    void* m_commandQueue = nullptr;
};

} // namespace mesh2splat::metal
