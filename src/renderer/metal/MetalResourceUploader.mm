#include "MetalResourceUploader.hpp"

#include "MetalCommandScheduler.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <cstring>
#include <limits>
#include <string>
#include <utility>

namespace mesh2splat::metal {
namespace {

NSString* labelString(const char* label)
{
    return label == nullptr || label[0] == '\0' ? nil : [NSString stringWithUTF8String:label];
}

NSString* labelString(const std::string& label)
{
    return labelString(label.c_str());
}

std::string nsStringValue(NSString* value)
{
    if (value == nil) {
        return {};
    }

    const char* utf8Value = value.UTF8String;
    return utf8Value == nullptr ? std::string{} : std::string(utf8Value);
}

std::string labelOrDefault(const char* label, const char* fallback)
{
    return label == nullptr || label[0] == '\0' ? std::string(fallback) : std::string(label);
}

NSString* uploadStagingLabel(const std::string& label, const char* resourceKind, uint32_t stagingIndex)
{
    std::string stagingLabel = label.empty() ? "Mesh2Splat Resource Upload" : label;
    stagingLabel += " ";
    stagingLabel += resourceKind;
    stagingLabel += " Upload Staging ";
    stagingLabel += std::to_string(stagingIndex);
    return labelString(stagingLabel);
}

const char* uploadBatchStatusName(MetalResourceUploadBatch::Status status)
{
    switch (status) {
    case MetalResourceUploadBatch::Status::NotReady:
        return "not ready";
    case MetalResourceUploadBatch::Status::Ready:
        return "ready";
    case MetalResourceUploadBatch::Status::Failed:
        return "failed";
    case MetalResourceUploadBatch::Status::Committed:
        return "committed";
    case MetalResourceUploadBatch::Status::Completed:
        return "completed";
    case MetalResourceUploadBatch::Status::Cancelled:
        return "cancelled";
    }

    return "unknown";
}

std::string labelOrNative(const char* label, NSString* nativeLabel, const char* fallback)
{
    std::string resolvedLabel = labelOrDefault(label, "");
    if (!resolvedLabel.empty()) {
        return resolvedLabel;
    }

    resolvedLabel = nsStringValue(nativeLabel);
    if (!resolvedLabel.empty()) {
        return resolvedLabel;
    }

    return fallback;
}

std::size_t textureDimensionAtMip(NSUInteger baseDimension, uint32_t mipLevel)
{
    std::size_t dimension = static_cast<std::size_t>(baseDimension);
    for (uint32_t mip = 0; mip < mipLevel && dimension > 1; ++mip) {
        dimension >>= 1;
    }
    return dimension == 0 ? 1 : dimension;
}

bool checkedMultiply(std::size_t lhs, std::size_t rhs, std::size_t& result)
{
    if (lhs != 0 && rhs > std::numeric_limits<std::size_t>::max() / lhs) {
        return false;
    }

    result = lhs * rhs;
    return true;
}

bool checkedAdd(std::size_t lhs, std::size_t rhs, std::size_t& result)
{
    if (rhs > std::numeric_limits<std::size_t>::max() - lhs) {
        return false;
    }

    result = lhs + rhs;
    return true;
}

bool isAligned(std::size_t value, std::size_t alignment)
{
    return alignment <= 1 || value % alignment == 0;
}

const char* textureTypeName(MTLTextureType textureType)
{
    switch (textureType) {
    case MTLTextureType1D:
        return "1D";
    case MTLTextureType1DArray:
        return "1D array";
    case MTLTextureType2D:
        return "2D";
    case MTLTextureType2DArray:
        return "2D array";
    case MTLTextureType2DMultisample:
        return "2D multisample";
    case MTLTextureTypeCube:
        return "cube";
    case MTLTextureTypeCubeArray:
        return "cube array";
    case MTLTextureType3D:
        return "3D";
    case MTLTextureType2DMultisampleArray:
        return "2D multisample array";
    default:
        return "unknown";
    }
}

constexpr MTLResourceOptions kUploadStagingBufferOptions =
    MTLResourceStorageModeShared | MTLResourceCPUCacheModeWriteCombined;

constexpr std::size_t kTextureUploadRowAlignment = 256;
constexpr const char* kDefaultCommandLabel = "Mesh2Splat Resource Upload";
constexpr const char* kDefaultBlitLabel = "Mesh2Splat Resource Upload Blit";

} // namespace

struct MetalResourceUploadBatch::Impl {
    id<MTLDevice> device = nil;
    id<MTLCommandBuffer> commandBuffer = nil;
    id<MTLBlitCommandEncoder> blitEncoder = nil;
    NSMutableArray<id<MTLBuffer>>* stagingBuffers = nil;
    MetalResourceUploadBatch::Status status = MetalResourceUploadBatch::Status::NotReady;
    MetalResourceUploadBatch::Stats stats;
    std::string commandLabel;
    std::string blitLabel;
    std::string lastErrorMessage;

    MetalResourceUploadBatch::Result result(const MetalCommandBufferDiagnostics& diagnostics) const
    {
        MetalResourceUploadBatch::Result uploadResult;
        uploadResult.status = status;
        uploadResult.stats = stats;
        uploadResult.completed = status == MetalResourceUploadBatch::Status::Completed && diagnostics.completed;
        uploadResult.commandBufferStatus = diagnostics.status;
        uploadResult.gpuMilliseconds = diagnostics.gpuMilliseconds;
        uploadResult.commandLabel = commandLabel;
        uploadResult.blitLabel = blitLabel;
        uploadResult.commandBufferLabel = diagnostics.label;
        uploadResult.statusDescription = diagnostics.valid
            ? diagnostics.statusDescription
            : uploadBatchStatusName(status);
        uploadResult.errorMessage = lastErrorMessage;
        return uploadResult;
    }

    MetalResourceUploadBatch::Result result() const
    {
        return result(MetalCommandScheduler::commandBufferDiagnostics((__bridge void*)commandBuffer));
    }

    std::string diagnosticsFailureMessage(const char* action, const MetalCommandBufferDiagnostics& diagnostics) const
    {
        std::string message = "Metal resource upload batch '" + commandLabel + "' failed in ";
        message += action;
        message += " with command buffer status '";
        message += diagnostics.statusDescription;
        message += "'";
        if (!diagnostics.label.empty() && diagnostics.label != commandLabel) {
            message += " for command buffer '";
            message += diagnostics.label;
            message += "'";
        }
        if (!diagnostics.errorDescription.empty()) {
            message += ": ";
            message += diagnostics.errorDescription;
        }
        message += ". Encoded ";
        message += std::to_string(stats.bufferUploads);
        message += " buffer upload(s), ";
        message += std::to_string(stats.textureUploads);
        message += " texture upload(s), ";
        message += std::to_string(stats.stagingBytes);
        message += " staging byte(s).";
        if (diagnostics.gpuMilliseconds > 0.0) {
            message += " GPU time ";
            message += std::to_string(diagnostics.gpuMilliseconds);
            message += " ms.";
        }
        return message;
    }

    bool finishCommit(const char* action, const MetalCommandBufferDiagnostics& diagnostics)
    {
        if (stagingBuffers != nil) {
            [stagingBuffers removeAllObjects];
        }

        if (diagnostics.completed) {
            status = MetalResourceUploadBatch::Status::Completed;
            clearError();
            return true;
        }

        return fail(diagnosticsFailureMessage(action, diagnostics));
    }

    bool fail(std::string message)
    {
        if (status == MetalResourceUploadBatch::Status::Failed && !lastErrorMessage.empty()) {
            return false;
        }

        lastErrorMessage = std::move(message);
        if (status != MetalResourceUploadBatch::Status::Completed &&
            status != MetalResourceUploadBatch::Status::Cancelled) {
            if (status == MetalResourceUploadBatch::Status::Ready && blitEncoder != nil) {
                [blitEncoder endEncoding];
                blitEncoder = nil;
            }
            if (stagingBuffers != nil) {
                [stagingBuffers removeAllObjects];
            }
            status = MetalResourceUploadBatch::Status::Failed;
        }
        return false;
    }

    void clearError()
    {
        lastErrorMessage.clear();
    }

    std::string invalidStateMessage(const char* action) const
    {
        std::string message = "Cannot ";
        message += action;
        message += ": Metal resource upload batch is ";
        message += uploadBatchStatusName(status);
        if (!lastErrorMessage.empty()) {
            message += " (";
            message += lastErrorMessage;
            message += ")";
        }
        message += ".";
        return message;
    }

    bool canRecordUpload(const std::string& label, const char* resourceKind, std::size_t bytes)
    {
        const bool textureUpload = std::strcmp(resourceKind, "Texture") == 0;
        const uint32_t currentCount = textureUpload ? stats.textureUploads : stats.bufferUploads;
        if (currentCount == std::numeric_limits<uint32_t>::max()) {
            return fail(
                "Cannot upload " + std::string(resourceKind) + " '" + label +
                "': upload count exceeded diagnostic counter capacity.");
        }

        if (bytes > std::numeric_limits<std::size_t>::max() - stats.stagingBytes) {
            return fail(
                "Cannot upload " + std::string(resourceKind) + " '" + label +
                "': staging byte count overflowed diagnostic counter capacity.");
        }

        return true;
    }

    uint32_t nextStagingIndex() const
    {
        const std::size_t totalUploads =
            static_cast<std::size_t>(stats.bufferUploads) + static_cast<std::size_t>(stats.textureUploads);
        return totalUploads >= std::numeric_limits<uint32_t>::max()
            ? std::numeric_limits<uint32_t>::max()
            : static_cast<uint32_t>(totalUploads + 1);
    }

    void recordUpload(const char* resourceKind, std::size_t bytes)
    {
        if (std::strcmp(resourceKind, "Texture") == 0) {
            ++stats.textureUploads;
        } else {
            ++stats.bufferUploads;
        }
        stats.stagingBytes += bytes;
        clearError();
    }
};

MetalResourceUploadBatch::MetalResourceUploadBatch(
    void* metalDevice,
    void* commandQueue,
    const char* commandLabel,
    const char* blitLabel)
    : m_impl(std::make_shared<Impl>())
{
    m_impl->commandLabel = labelOrDefault(commandLabel, kDefaultCommandLabel);
    m_impl->blitLabel = labelOrDefault(blitLabel, kDefaultBlitLabel);

    id<MTLDevice> device = (__bridge id<MTLDevice>)metalDevice;
    id<MTLCommandQueue> nativeCommandQueue = (__bridge id<MTLCommandQueue>)commandQueue;
    if (device == nil) {
        m_impl->fail("Cannot create Metal resource upload batch: Metal device is unavailable.");
        return;
    }

    if (nativeCommandQueue == nil) {
        m_impl->fail("Cannot create Metal resource upload batch: Metal command queue is unavailable.");
        return;
    }

    id<MTLCommandBuffer> commandBuffer = [nativeCommandQueue commandBuffer];
    if (commandBuffer == nil) {
        m_impl->fail("Cannot create Metal resource upload batch: failed to allocate command buffer.");
        return;
    }

    NSString* nativeCommandLabel = labelString(m_impl->commandLabel);
    if (nativeCommandLabel != nil) {
        commandBuffer.label = nativeCommandLabel;
    }

    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    if (blitEncoder == nil) {
        m_impl->fail("Cannot create Metal resource upload batch: failed to create blit encoder.");
        return;
    }

    NSString* nativeBlitLabel = labelString(m_impl->blitLabel);
    if (nativeBlitLabel != nil) {
        blitEncoder.label = nativeBlitLabel;
    }

    m_impl->device = device;
    m_impl->commandBuffer = commandBuffer;
    m_impl->blitEncoder = blitEncoder;
    m_impl->stagingBuffers = [NSMutableArray array];
    m_impl->status = MetalResourceUploadBatch::Status::Ready;
    m_impl->clearError();
}

MetalResourceUploadBatch::~MetalResourceUploadBatch()
{
    if (m_impl->blitEncoder != nil &&
        (m_impl->status == Status::Ready || m_impl->status == Status::Failed)) {
        [m_impl->blitEncoder endEncoding];
        m_impl->blitEncoder = nil;
        m_impl->status = Status::Cancelled;
    }
}

bool MetalResourceUploadBatch::isValid() const
{
    return m_impl->status == Status::Ready &&
        m_impl->device != nil &&
        m_impl->commandBuffer != nil &&
        m_impl->blitEncoder != nil &&
        m_impl->stagingBuffers != nil;
}

MetalResourceUploadBatch::Status MetalResourceUploadBatch::status() const
{
    return m_impl->status;
}

const MetalResourceUploadBatch::Stats& MetalResourceUploadBatch::stats() const
{
    return m_impl->stats;
}

const std::string& MetalResourceUploadBatch::lastErrorMessage() const
{
    return m_impl->lastErrorMessage;
}

MetalResourceUploadBatch::Result MetalResourceUploadBatch::result() const
{
    return m_impl->result();
}

bool MetalResourceUploadBatch::uploadBufferToPrivate(
    const void* data,
    std::size_t size,
    void* destinationBuffer,
    const char* label)
{
    if (!isValid()) {
        return m_impl->fail(m_impl->invalidStateMessage("upload buffer to private storage"));
    }

    id<MTLBuffer> targetBuffer = (__bridge id<MTLBuffer>)destinationBuffer;
    if (targetBuffer == nil) {
        return m_impl->fail(
            "Cannot upload buffer '" + labelOrDefault(label, "unnamed buffer") +
            "': destination Metal buffer is unavailable.");
    }

    const std::string bufferLabel = labelOrNative(label, targetBuffer.label, "unnamed buffer");
    if (data == nullptr) {
        return m_impl->fail(
            "Cannot upload buffer '" + bufferLabel +
            "': source data is null.");
    }

    if (size == 0) {
        return m_impl->fail(
            "Cannot upload buffer '" + bufferLabel +
            "': upload size is zero.");
    }

    if (size > static_cast<std::size_t>(targetBuffer.length)) {
        return m_impl->fail(
            "Cannot upload buffer '" + bufferLabel +
            "': upload size " + std::to_string(size) +
            " exceeds destination size " + std::to_string(static_cast<std::size_t>(targetBuffer.length)) + ".");
    }

    if (!m_impl->canRecordUpload(bufferLabel, "Buffer", size)) {
        return false;
    }

    id<MTLBuffer> stagingBuffer = [m_impl->device newBufferWithLength:size options:kUploadStagingBufferOptions];
    if (stagingBuffer == nil) {
        return m_impl->fail(
            "Cannot upload buffer '" + bufferLabel +
            "': failed to allocate " + std::to_string(size) + " byte staging buffer.");
    }

    if (stagingBuffer.contents == nullptr) {
        return m_impl->fail(
            "Cannot upload buffer '" + bufferLabel +
            "': staging buffer is not CPU accessible.");
    }

    NSString* stagingLabel = uploadStagingLabel(bufferLabel, "Buffer", m_impl->nextStagingIndex());
    if (stagingLabel != nil) {
        stagingBuffer.label = stagingLabel;
    }
    std::memcpy(stagingBuffer.contents, data, size);
    [m_impl->stagingBuffers addObject:stagingBuffer];

    [m_impl->blitEncoder copyFromBuffer:stagingBuffer
                           sourceOffset:0
                               toBuffer:targetBuffer
                      destinationOffset:0
                                   size:size];
    m_impl->recordUpload("Buffer", size);
    return true;
}

bool MetalResourceUploadBatch::uploadTexture2DToPrivate(
    const void* data,
    std::size_t sourceBytesPerRow,
    std::size_t copyBytesPerRow,
    std::size_t destinationBytesPerRow,
    std::size_t uploadSize,
    uint32_t width,
    uint32_t height,
    uint32_t mipLevel,
    void* destinationTexture,
    const char* label)
{
    if (!isValid()) {
        return m_impl->fail(m_impl->invalidStateMessage("upload texture to private storage"));
    }

    id<MTLTexture> targetTexture = (__bridge id<MTLTexture>)destinationTexture;
    if (targetTexture == nil) {
        return m_impl->fail(
            "Cannot upload texture '" + labelOrDefault(label, "unnamed texture") +
            "': destination Metal texture is unavailable.");
    }

    const std::string textureLabel = labelOrNative(label, targetTexture.label, "unnamed texture");
    if (data == nullptr) {
        return m_impl->fail("Cannot upload texture '" + textureLabel + "': source data is null.");
    }

    if (sourceBytesPerRow == 0 || copyBytesPerRow == 0 || destinationBytesPerRow == 0 || uploadSize == 0 ||
        width == 0 || height == 0) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel +
            "': dimensions, row strides, and upload size must be non-zero.");
    }

    if (targetTexture.textureType != MTLTextureType2D) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': destination texture type is " +
            textureTypeName(targetTexture.textureType) + "; only 2D textures are supported.");
    }

    if (targetTexture.storageMode == MTLStorageModeMemoryless) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel +
            "': destination texture storage mode is memoryless and cannot receive staged uploads.");
    }

    if (targetTexture.sampleCount > 1) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': multisample textures cannot receive buffer uploads.");
    }

    if (copyBytesPerRow > sourceBytesPerRow) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': copy row size " +
            std::to_string(copyBytesPerRow) + " exceeds source row stride " +
            std::to_string(sourceBytesPerRow) + ".");
    }

    if (copyBytesPerRow > destinationBytesPerRow) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': copy row size " +
            std::to_string(copyBytesPerRow) + " exceeds staging row stride " +
            std::to_string(destinationBytesPerRow) + ".");
    }

    if (!isAligned(destinationBytesPerRow, kTextureUploadRowAlignment)) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': staging row stride " +
            std::to_string(destinationBytesPerRow) + " is not aligned to " +
            std::to_string(kTextureUploadRowAlignment) + " bytes.");
    }

    if (mipLevel >= static_cast<uint32_t>(targetTexture.mipmapLevelCount)) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': mip level " +
            std::to_string(mipLevel) + " is outside destination mip count " +
            std::to_string(static_cast<std::size_t>(targetTexture.mipmapLevelCount)) + ".");
    }

    const std::size_t mipWidth = textureDimensionAtMip(targetTexture.width, mipLevel);
    const std::size_t mipHeight = textureDimensionAtMip(targetTexture.height, mipLevel);
    if (static_cast<std::size_t>(width) > mipWidth || static_cast<std::size_t>(height) > mipHeight) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': upload extent " +
            std::to_string(width) + "x" + std::to_string(height) +
            " exceeds destination mip extent " + std::to_string(mipWidth) + "x" +
            std::to_string(mipHeight) + ".");
    }

    std::size_t sourceLastRowOffset = 0;
    std::size_t sourceRequiredBytes = 0;
    if (!checkedMultiply(sourceBytesPerRow, static_cast<std::size_t>(height - 1), sourceLastRowOffset) ||
        !checkedAdd(sourceLastRowOffset, copyBytesPerRow, sourceRequiredBytes)) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': source row layout overflowed size_t.");
    }

    std::size_t bytesPerImage = 0;
    if (!checkedMultiply(destinationBytesPerRow, static_cast<std::size_t>(height), bytesPerImage)) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': staging bytesPerImage overflowed size_t.");
    }

    std::size_t stagingLastRowOffset = 0;
    std::size_t requiredCopyBytes = 0;
    if (!checkedMultiply(destinationBytesPerRow, static_cast<std::size_t>(height - 1), stagingLastRowOffset) ||
        !checkedAdd(stagingLastRowOffset, copyBytesPerRow, requiredCopyBytes)) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': staging row layout overflowed size_t.");
    }

    if (uploadSize < bytesPerImage) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': upload size " +
            std::to_string(uploadSize) + " is smaller than required staging size " +
            std::to_string(bytesPerImage) + ".");
    }

    if (!m_impl->canRecordUpload(textureLabel, "Texture", requiredCopyBytes)) {
        return false;
    }

    id<MTLBuffer> stagingBuffer =
        [m_impl->device newBufferWithLength:uploadSize options:kUploadStagingBufferOptions];
    if (stagingBuffer == nil) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': failed to allocate " +
            std::to_string(uploadSize) + " byte staging buffer.");
    }

    if (stagingBuffer.contents == nullptr) {
        return m_impl->fail(
            "Cannot upload texture '" + textureLabel + "': staging buffer is not CPU accessible.");
    }

    NSString* stagingLabel = uploadStagingLabel(textureLabel, "Texture", m_impl->nextStagingIndex());
    if (stagingLabel != nil) {
        stagingBuffer.label = stagingLabel;
    }

    auto* destination = static_cast<std::byte*>(stagingBuffer.contents);
    const auto* source = static_cast<const std::byte*>(data);
    for (uint32_t row = 0; row < height; ++row) {
        std::memcpy(
            destination + static_cast<std::size_t>(row) * destinationBytesPerRow,
            source + static_cast<std::size_t>(row) * sourceBytesPerRow,
            copyBytesPerRow);
    }
    [m_impl->stagingBuffers addObject:stagingBuffer];

    [m_impl->blitEncoder copyFromBuffer:stagingBuffer
                           sourceOffset:0
                      sourceBytesPerRow:destinationBytesPerRow
                    sourceBytesPerImage:bytesPerImage
                             sourceSize:MTLSizeMake(width, height, 1)
                              toTexture:targetTexture
                       destinationSlice:0
                       destinationLevel:mipLevel
                      destinationOrigin:MTLOriginMake(0, 0, 0)];
    (void)sourceRequiredBytes;
    m_impl->recordUpload("Texture", requiredCopyBytes);
    return true;
}

bool MetalResourceUploadBatch::commitAndWait()
{
    return commitAndWait(nullptr);
}

bool MetalResourceUploadBatch::commitAndWait(std::string* errorMessage)
{
    if (!isValid()) {
        m_impl->fail(m_impl->invalidStateMessage("commit upload batch"));
        if (errorMessage != nullptr) {
            *errorMessage = m_impl->lastErrorMessage;
        }
        return false;
    }

    [m_impl->blitEncoder endEncoding];
    m_impl->blitEncoder = nil;
    m_impl->status = Status::Committed;
    [m_impl->commandBuffer commit];
    [m_impl->commandBuffer waitUntilCompleted];

    const MetalCommandBufferDiagnostics diagnostics =
        MetalCommandScheduler::commandBufferDiagnostics((__bridge void*)m_impl->commandBuffer);
    if (m_impl->finishCommit("commitAndWait", diagnostics)) {
        if (errorMessage != nullptr) {
            errorMessage->clear();
        }
        return true;
    }

    if (errorMessage != nullptr) {
        *errorMessage = m_impl->lastErrorMessage;
    }
    return false;
}

bool MetalResourceUploadBatch::commitAsync(CompletionHandler completion, void* userData)
{
    if (!isValid()) {
        return m_impl->fail(m_impl->invalidStateMessage("commit upload batch asynchronously"));
    }

    [m_impl->blitEncoder endEncoding];
    m_impl->blitEncoder = nil;
    m_impl->status = Status::Committed;

    std::shared_ptr<Impl> impl = m_impl;
    [m_impl->commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> commandBuffer) {
        const MetalCommandBufferDiagnostics diagnostics =
            MetalCommandScheduler::commandBufferDiagnostics((__bridge void*)commandBuffer);
        impl->finishCommit("commitAsync", diagnostics);
        if (completion != nullptr) {
            completion(impl->result(diagnostics), userData);
        }
    }];
    [m_impl->commandBuffer commit];
    return true;
}

MetalResourceUploader::MetalResourceUploader(void* metalDevice, void* commandQueue)
    : m_device(metalDevice)
    , m_commandQueue(commandQueue)
{
}

bool MetalResourceUploader::uploadBufferToPrivate(
    const void* data,
    std::size_t size,
    void* destinationBuffer,
    const char* label) const
{
    return uploadBufferToPrivate(data, size, destinationBuffer, label, nullptr);
}

bool MetalResourceUploader::uploadBufferToPrivate(
    const void* data,
    std::size_t size,
    void* destinationBuffer,
    const char* label,
    std::string* errorMessage) const
{
    MetalResourceUploadBatch uploadBatch(
        m_device,
        m_commandQueue,
        "Mesh2Splat Private Buffer Upload",
        "Mesh2Splat Private Buffer Upload Blit");
    if (!uploadBatch.uploadBufferToPrivate(data, size, destinationBuffer, label)) {
        if (errorMessage != nullptr) {
            *errorMessage = uploadBatch.lastErrorMessage();
        }
        return false;
    }

    return uploadBatch.commitAndWait(errorMessage);
}

bool MetalResourceUploader::uploadTexture2DToPrivate(
    const void* data,
    std::size_t sourceBytesPerRow,
    std::size_t copyBytesPerRow,
    std::size_t destinationBytesPerRow,
    std::size_t uploadSize,
    uint32_t width,
    uint32_t height,
    uint32_t mipLevel,
    void* destinationTexture,
    const char* label) const
{
    return uploadTexture2DToPrivate(
        data,
        sourceBytesPerRow,
        copyBytesPerRow,
        destinationBytesPerRow,
        uploadSize,
        width,
        height,
        mipLevel,
        destinationTexture,
        label,
        nullptr);
}

bool MetalResourceUploader::uploadTexture2DToPrivate(
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
    std::string* errorMessage) const
{
    MetalResourceUploadBatch uploadBatch(
        m_device,
        m_commandQueue,
        "Mesh2Splat Private Texture Upload",
        "Mesh2Splat Private Texture Upload Blit");
    if (!uploadBatch.uploadTexture2DToPrivate(
            data,
            sourceBytesPerRow,
            copyBytesPerRow,
            destinationBytesPerRow,
            uploadSize,
            width,
            height,
            mipLevel,
            destinationTexture,
            label)) {
        if (errorMessage != nullptr) {
            *errorMessage = uploadBatch.lastErrorMessage();
        }
        return false;
    }

    return uploadBatch.commitAndWait(errorMessage);
}

} // namespace mesh2splat::metal
