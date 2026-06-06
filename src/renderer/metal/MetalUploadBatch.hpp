#pragma once

#include <cstddef>
#include <cstdint>
#include <limits>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace mesh2splat::metal {

using MetalUploadBatchSerial = uint64_t;

enum class MetalUploadPriority : uint8_t {
    Background,
    Normal,
    High,
    Critical,
};

enum class MetalUploadFailurePolicy : uint8_t {
    StopBatch,
    SkipItem,
    ContinueBatch,
};

enum class MetalUploadItemKind : uint8_t {
    Buffer,
    Texture,
};

inline const char* metalUploadPriorityName(MetalUploadPriority priority)
{
    switch (priority) {
    case MetalUploadPriority::Background:
        return "background";
    case MetalUploadPriority::Normal:
        return "normal";
    case MetalUploadPriority::High:
        return "high";
    case MetalUploadPriority::Critical:
        return "critical";
    }

    return "unknown";
}

inline const char* metalUploadFailurePolicyName(MetalUploadFailurePolicy policy)
{
    switch (policy) {
    case MetalUploadFailurePolicy::StopBatch:
        return "stop-batch";
    case MetalUploadFailurePolicy::SkipItem:
        return "skip-item";
    case MetalUploadFailurePolicy::ContinueBatch:
        return "continue-batch";
    }

    return "unknown";
}

inline const char* metalUploadItemKindName(MetalUploadItemKind kind)
{
    switch (kind) {
    case MetalUploadItemKind::Buffer:
        return "buffer";
    case MetalUploadItemKind::Texture:
        return "texture";
    }

    return "upload";
}

namespace detail {

inline std::size_t metalUploadAddSaturating(std::size_t lhs, std::size_t rhs)
{
    const std::size_t maxValue = (std::numeric_limits<std::size_t>::max)();
    return lhs > maxValue - rhs ? maxValue : lhs + rhs;
}

inline std::size_t metalUploadMultiplySaturating(std::size_t lhs, std::size_t rhs)
{
    if (lhs == 0 || rhs == 0) {
        return 0;
    }

    const std::size_t maxValue = (std::numeric_limits<std::size_t>::max)();
    return lhs > maxValue / rhs ? maxValue : lhs * rhs;
}

inline bool metalUploadIsLabelSeparator(char value)
{
    const auto byte = static_cast<unsigned char>(value);
    return byte <= 0x20u || byte == 0x7fu;
}

inline std::string metalUploadCleanLabel(std::string_view value, std::string_view fallback = {})
{
    auto clean = [](std::string_view source) {
        std::string result;
        result.reserve(source.size());

        bool pendingSpace = false;
        for (char character : source) {
            if (metalUploadIsLabelSeparator(character)) {
                pendingSpace = !result.empty();
                continue;
            }

            if (pendingSpace) {
                result.push_back(' ');
                pendingSpace = false;
            }
            result.push_back(character);
        }

        return result;
    };

    std::string result = clean(value);
    if (result.empty() && !fallback.empty()) {
        result = clean(fallback);
    }
    return result;
}

inline void metalUploadAppendOptionalIndex(std::string& label, std::size_t itemIndex)
{
    if (itemIndex == (std::numeric_limits<std::size_t>::max)()) {
        return;
    }

    label += " [index=" + std::to_string(itemIndex) + "]";
}

} // namespace detail

struct MetalUploadBufferItem {
    const void* sourceData = nullptr;
    void* destinationBuffer = nullptr;
    std::size_t sourceOffset = 0;
    std::size_t destinationOffset = 0;
    std::size_t byteSize = 0;
    std::string label;

    bool isValid() const
    {
        return sourceData != nullptr && destinationBuffer != nullptr && byteSize != 0;
    }

    std::size_t stagingByteEstimate() const
    {
        return byteSize;
    }

    std::string diagnosticLabel(std::size_t itemIndex = (std::numeric_limits<std::size_t>::max)()) const
    {
        std::string result = detail::metalUploadCleanLabel(label, "Metal buffer upload");
        detail::metalUploadAppendOptionalIndex(result, itemIndex);
        result += " [kind=" + std::string(metalUploadItemKindName(MetalUploadItemKind::Buffer)) + "]";
        result += " [srcOffset=" + std::to_string(sourceOffset) + "]";
        result += " [dstOffset=" + std::to_string(destinationOffset) + "]";
        result += " [bytes=" + std::to_string(byteSize) + "]";
        result += " [valid=" + std::string(isValid() ? "true" : "false") + "]";
        return result;
    }
};

struct MetalUploadTextureRegion {
    uint32_t x = 0;
    uint32_t y = 0;
    uint32_t z = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t depth = 1;
    uint32_t mipLevel = 0;
    uint32_t arraySlice = 0;

    bool isEmpty() const
    {
        return width == 0 || height == 0 || depth == 0;
    }

    std::size_t texelCountEstimate() const
    {
        if (isEmpty()) {
            return 0;
        }

        const std::size_t rowTexels = width;
        const std::size_t imageTexels = detail::metalUploadMultiplySaturating(rowTexels, height);
        return detail::metalUploadMultiplySaturating(imageTexels, depth);
    }
};

struct MetalUploadTextureItem {
    const void* sourceData = nullptr;
    void* destinationTexture = nullptr;
    std::size_t sourceOffset = 0;
    std::size_t sourceBytesPerRow = 0;
    std::size_t sourceBytesPerImage = 0;
    std::size_t copyBytesPerRow = 0;
    std::size_t copyBytesPerImage = 0;
    std::size_t destinationBytesPerRow = 0;
    std::size_t stagingBytes = 0;
    MetalUploadTextureRegion region;
    std::string label;

    bool isValid() const
    {
        return sourceData != nullptr &&
            destinationTexture != nullptr &&
            !region.isEmpty() &&
            sourceBytesPerRow != 0 &&
            copyBytesPerRow != 0 &&
            destinationBytesPerRow != 0 &&
            stagingByteEstimate() != 0;
    }

    std::size_t stagingByteEstimate() const
    {
        if (stagingBytes != 0) {
            return stagingBytes;
        }

        if (region.isEmpty()) {
            return 0;
        }

        const std::size_t rowBytes = copyBytesPerRow != 0 ? copyBytesPerRow : sourceBytesPerRow;
        if (rowBytes == 0) {
            return 0;
        }

        const std::size_t imageBytes = copyBytesPerImage != 0 ?
            copyBytesPerImage :
            detail::metalUploadMultiplySaturating(rowBytes, region.height);
        return detail::metalUploadMultiplySaturating(imageBytes, region.depth);
    }

    std::string diagnosticLabel(std::size_t itemIndex = (std::numeric_limits<std::size_t>::max)()) const
    {
        std::string result = detail::metalUploadCleanLabel(label, "Metal texture upload");
        detail::metalUploadAppendOptionalIndex(result, itemIndex);
        result += " [kind=" + std::string(metalUploadItemKindName(MetalUploadItemKind::Texture)) + "]";
        result += " [mip=" + std::to_string(region.mipLevel) + "]";
        result += " [slice=" + std::to_string(region.arraySlice) + "]";
        result += " [origin=" + std::to_string(region.x) + "," + std::to_string(region.y) + "," +
            std::to_string(region.z) + "]";
        result += " [extent=" + std::to_string(region.width) + "x" + std::to_string(region.height) + "x" +
            std::to_string(region.depth) + "]";
        result += " [srcOffset=" + std::to_string(sourceOffset) + "]";
        result += " [srcRowBytes=" + std::to_string(sourceBytesPerRow) + "]";
        result += " [copyRowBytes=" + std::to_string(copyBytesPerRow) + "]";
        result += " [stagingBytes=" + std::to_string(stagingByteEstimate()) + "]";
        result += " [valid=" + std::string(isValid() ? "true" : "false") + "]";
        return result;
    }
};

struct MetalUploadBatchDesc {
    MetalUploadBatchSerial serial = 0;
    MetalUploadPriority priority = MetalUploadPriority::Normal;
    MetalUploadFailurePolicy failurePolicy = MetalUploadFailurePolicy::StopBatch;
    std::string label;
    std::string dependencyLabel;

    bool hasSerial() const
    {
        return serial != 0;
    }

    bool hasDependency() const
    {
        return !dependencyLabel.empty();
    }

    std::string diagnosticLabel() const
    {
        std::string result = detail::metalUploadCleanLabel(label, "Metal upload batch");
        if (hasSerial()) {
            result += " [serial=" + std::to_string(serial) + "]";
        }
        result += " [priority=" + std::string(metalUploadPriorityName(priority)) + "]";
        result += " [failurePolicy=" + std::string(metalUploadFailurePolicyName(failurePolicy)) + "]";

        const std::string cleanDependency = detail::metalUploadCleanLabel(dependencyLabel);
        if (!cleanDependency.empty()) {
            result += " [depends=" + cleanDependency + "]";
        }

        return result;
    }
};

struct MetalUploadBatchStats {
    std::size_t bufferUploads = 0;
    std::size_t textureUploads = 0;
    std::size_t validBufferUploads = 0;
    std::size_t validTextureUploads = 0;
    std::size_t invalidUploads = 0;
    std::size_t stagingBytes = 0;

    bool empty() const
    {
        return bufferUploads == 0 && textureUploads == 0;
    }

    std::size_t uploadCount() const
    {
        return detail::metalUploadAddSaturating(bufferUploads, textureUploads);
    }

    std::size_t validUploadCount() const
    {
        return detail::metalUploadAddSaturating(validBufferUploads, validTextureUploads);
    }
};

class MetalUploadBatch {
public:
    using Serial = MetalUploadBatchSerial;

    MetalUploadBatch() = default;

    explicit MetalUploadBatch(MetalUploadBatchDesc desc)
        : m_desc(std::move(desc))
    {
    }

    explicit MetalUploadBatch(Serial serial)
    {
        m_desc.serial = serial;
    }

    const MetalUploadBatchDesc& descriptor() const
    {
        return m_desc;
    }

    MetalUploadBatchDesc& mutableDescriptor()
    {
        return m_desc;
    }

    Serial serial() const
    {
        return m_desc.serial;
    }

    void setSerial(Serial serial)
    {
        m_desc.serial = serial;
    }

    MetalUploadPriority priority() const
    {
        return m_desc.priority;
    }

    void setPriority(MetalUploadPriority priority)
    {
        m_desc.priority = priority;
    }

    MetalUploadFailurePolicy failurePolicy() const
    {
        return m_desc.failurePolicy;
    }

    void setFailurePolicy(MetalUploadFailurePolicy failurePolicy)
    {
        m_desc.failurePolicy = failurePolicy;
    }

    const std::string& label() const
    {
        return m_desc.label;
    }

    void setLabel(const char* label)
    {
        m_desc.label = label ? label : "";
    }

    void setLabel(std::string label)
    {
        m_desc.label = std::move(label);
    }

    const std::string& dependencyLabel() const
    {
        return m_desc.dependencyLabel;
    }

    void setDependencyLabel(const char* dependencyLabel)
    {
        m_desc.dependencyLabel = dependencyLabel ? dependencyLabel : "";
    }

    void setDependencyLabel(std::string dependencyLabel)
    {
        m_desc.dependencyLabel = std::move(dependencyLabel);
    }

    bool hasDependency() const
    {
        return m_desc.hasDependency();
    }

    bool isValid() const
    {
        if (empty()) {
            return false;
        }

        for (const MetalUploadBufferItem& item : m_bufferUploads) {
            if (!item.isValid()) {
                return false;
            }
        }

        for (const MetalUploadTextureItem& item : m_textureUploads) {
            if (!item.isValid()) {
                return false;
            }
        }

        return true;
    }

    void reserve(std::size_t bufferUploadCount, std::size_t textureUploadCount)
    {
        m_bufferUploads.reserve(bufferUploadCount);
        m_textureUploads.reserve(textureUploadCount);
    }

    void addBufferUpload(MetalUploadBufferItem item)
    {
        m_bufferUploads.push_back(std::move(item));
    }

    void addTextureUpload(MetalUploadTextureItem item)
    {
        m_textureUploads.push_back(std::move(item));
    }

    const std::vector<MetalUploadBufferItem>& bufferUploads() const
    {
        return m_bufferUploads;
    }

    std::vector<MetalUploadBufferItem>& mutableBufferUploads()
    {
        return m_bufferUploads;
    }

    const std::vector<MetalUploadTextureItem>& textureUploads() const
    {
        return m_textureUploads;
    }

    std::vector<MetalUploadTextureItem>& mutableTextureUploads()
    {
        return m_textureUploads;
    }

    bool empty() const
    {
        return m_bufferUploads.empty() && m_textureUploads.empty();
    }

    std::size_t uploadCount() const
    {
        return detail::metalUploadAddSaturating(m_bufferUploads.size(), m_textureUploads.size());
    }

    std::size_t stagingByteEstimate() const
    {
        std::size_t bytes = 0;
        for (const MetalUploadBufferItem& item : m_bufferUploads) {
            bytes = detail::metalUploadAddSaturating(bytes, item.stagingByteEstimate());
        }

        for (const MetalUploadTextureItem& item : m_textureUploads) {
            bytes = detail::metalUploadAddSaturating(bytes, item.stagingByteEstimate());
        }

        return bytes;
    }

    std::size_t validUploadCount() const
    {
        std::size_t count = 0;
        for (const MetalUploadBufferItem& item : m_bufferUploads) {
            if (item.isValid()) {
                count = detail::metalUploadAddSaturating(count, 1);
            }
        }

        for (const MetalUploadTextureItem& item : m_textureUploads) {
            if (item.isValid()) {
                count = detail::metalUploadAddSaturating(count, 1);
            }
        }

        return count;
    }

    std::size_t invalidUploadCount() const
    {
        const std::size_t total = uploadCount();
        const std::size_t valid = validUploadCount();
        return total > valid ? total - valid : 0;
    }

    MetalUploadBatchStats stats() const
    {
        MetalUploadBatchStats result;
        result.bufferUploads = m_bufferUploads.size();
        result.textureUploads = m_textureUploads.size();

        for (const MetalUploadBufferItem& item : m_bufferUploads) {
            if (item.isValid()) {
                result.validBufferUploads = detail::metalUploadAddSaturating(result.validBufferUploads, 1);
            } else {
                result.invalidUploads = detail::metalUploadAddSaturating(result.invalidUploads, 1);
            }
        }

        for (const MetalUploadTextureItem& item : m_textureUploads) {
            if (item.isValid()) {
                result.validTextureUploads = detail::metalUploadAddSaturating(result.validTextureUploads, 1);
            } else {
                result.invalidUploads = detail::metalUploadAddSaturating(result.invalidUploads, 1);
            }
        }

        result.stagingBytes = stagingByteEstimate();
        return result;
    }

    std::string diagnosticLabel() const
    {
        MetalUploadBatchStats currentStats = stats();
        std::string result = m_desc.diagnosticLabel();
        result += " [uploads=" + std::to_string(currentStats.uploadCount()) + "]";
        result += " [buffers=" + std::to_string(currentStats.bufferUploads) + "]";
        result += " [textures=" + std::to_string(currentStats.textureUploads) + "]";
        result += " [valid=" + std::to_string(currentStats.validUploadCount()) + "]";
        result += " [invalid=" + std::to_string(currentStats.invalidUploads) + "]";
        result += " [stagingBytes=" + std::to_string(currentStats.stagingBytes) + "]";
        return result;
    }

    std::string describe() const
    {
        const MetalUploadBatchStats currentStats = stats();
        std::ostringstream stream;
        stream << "MetalUploadBatch serial=" << serial()
               << " label=" << detail::metalUploadCleanLabel(label(), "Metal upload batch")
               << " priority=" << metalUploadPriorityName(priority())
               << " failurePolicy=" << metalUploadFailurePolicyName(failurePolicy())
               << " buffers=" << currentStats.bufferUploads
               << " textures=" << currentStats.textureUploads
               << " valid=" << currentStats.validUploadCount()
               << " invalid=" << currentStats.invalidUploads
               << " stagingBytes=" << currentStats.stagingBytes;

        if (hasDependency()) {
            stream << " dependency=" << detail::metalUploadCleanLabel(dependencyLabel());
        }

        return stream.str();
    }

    std::vector<std::string> itemDiagnosticLabels() const
    {
        std::vector<std::string> result;
        result.reserve(uploadCount());

        std::size_t itemIndex = 0;
        for (const MetalUploadBufferItem& item : m_bufferUploads) {
            result.push_back(item.diagnosticLabel(itemIndex));
            itemIndex = detail::metalUploadAddSaturating(itemIndex, 1);
        }
        for (const MetalUploadTextureItem& item : m_textureUploads) {
            result.push_back(item.diagnosticLabel(itemIndex));
            itemIndex = detail::metalUploadAddSaturating(itemIndex, 1);
        }

        return result;
    }

    void clearUploads()
    {
        m_bufferUploads.clear();
        m_textureUploads.clear();
    }

    void clear()
    {
        m_desc = {};
        clearUploads();
    }

private:
    MetalUploadBatchDesc m_desc;
    std::vector<MetalUploadBufferItem> m_bufferUploads;
    std::vector<MetalUploadTextureItem> m_textureUploads;
};

} // namespace mesh2splat::metal
