#include "MetalGaussianSortBuffer.hpp"

#include "MetalBuffer.hpp"
#include "MetalDeviceContext.hpp"

#include <limits>
#include <string>

namespace mesh2splat::metal {
namespace {

constexpr std::size_t kRadixBinCount = 16;
constexpr std::size_t kRadixSortThreadCount = 256;

std::size_t radixBlockCount(std::size_t capacity)
{
    return (capacity + kRadixSortThreadCount - 1) / kRadixSortThreadCount;
}

} // namespace

struct MetalGaussianSortBuffer::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    std::unique_ptr<MetalBuffer> keyBuffer;
    std::unique_ptr<MetalBuffer> indexBuffer;
    std::unique_ptr<MetalBuffer> scratchKeyBuffer;
    std::unique_ptr<MetalBuffer> scratchIndexBuffer;
    std::unique_ptr<MetalBuffer> blockCountBuffer;
    std::unique_ptr<MetalBuffer> globalOffsetBuffer;
    std::size_t capacity = 0;
    std::size_t blockCount = 0;
    uint32_t count = 0;
};

MetalGaussianSortBuffer::MetalGaussianSortBuffer(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = &deviceContext;
}

MetalGaussianSortBuffer::~MetalGaussianSortBuffer() = default;

MetalGaussianSortBuffer::MetalGaussianSortBuffer(MetalGaussianSortBuffer&&) noexcept = default;

MetalGaussianSortBuffer& MetalGaussianSortBuffer::operator=(MetalGaussianSortBuffer&&) noexcept = default;

bool MetalGaussianSortBuffer::create(std::size_t capacity, const char* label)
{
    if (m_impl->deviceContext == nullptr || capacity == 0 ||
        capacity > static_cast<std::size_t>(std::numeric_limits<uint32_t>::max()) ||
        capacity > std::numeric_limits<std::size_t>::max() / sizeof(uint32_t)) {
        return false;
    }

    const std::size_t blockCount = radixBlockCount(capacity);
    if (blockCount == 0 ||
        blockCount > static_cast<std::size_t>(std::numeric_limits<uint32_t>::max()) ||
        blockCount > std::numeric_limits<std::size_t>::max() / kRadixBinCount ||
        blockCount * kRadixBinCount > std::numeric_limits<std::size_t>::max() / sizeof(uint32_t)) {
        return false;
    }

    const std::string baseLabel = label != nullptr ? label : "Metal Gaussian Sort";
    auto keyBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto indexBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto scratchKeyBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto scratchIndexBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto blockCountBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto globalOffsetBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    const std::size_t bufferSize = capacity * sizeof(uint32_t);
    const std::size_t blockCountBufferSize = blockCount * kRadixBinCount * sizeof(uint32_t);
    if (!keyBuffer->createPrivate(bufferSize, (baseLabel + " Keys").c_str()) ||
        !indexBuffer->createPrivate(bufferSize, (baseLabel + " Indices").c_str()) ||
        !scratchKeyBuffer->createPrivate(bufferSize, (baseLabel + " Scratch Keys").c_str()) ||
        !scratchIndexBuffer->createPrivate(bufferSize, (baseLabel + " Scratch Indices").c_str()) ||
        !blockCountBuffer->createPrivate(blockCountBufferSize, (baseLabel + " Radix Block Counts").c_str()) ||
        !globalOffsetBuffer->createPrivate(kRadixBinCount * sizeof(uint32_t), (baseLabel + " Radix Global Offsets").c_str())) {
        return false;
    }

    m_impl->keyBuffer = std::move(keyBuffer);
    m_impl->indexBuffer = std::move(indexBuffer);
    m_impl->scratchKeyBuffer = std::move(scratchKeyBuffer);
    m_impl->scratchIndexBuffer = std::move(scratchIndexBuffer);
    m_impl->blockCountBuffer = std::move(blockCountBuffer);
    m_impl->globalOffsetBuffer = std::move(globalOffsetBuffer);
    m_impl->capacity = capacity;
    m_impl->blockCount = blockCount;
    m_impl->count = 0;
    return true;
}

bool MetalGaussianSortBuffer::setCount(uint32_t count)
{
    if (count > m_impl->capacity) {
        return false;
    }

    m_impl->count = count;
    return true;
}

void MetalGaussianSortBuffer::reset()
{
    m_impl->keyBuffer.reset();
    m_impl->indexBuffer.reset();
    m_impl->scratchKeyBuffer.reset();
    m_impl->scratchIndexBuffer.reset();
    m_impl->blockCountBuffer.reset();
    m_impl->globalOffsetBuffer.reset();
    m_impl->capacity = 0;
    m_impl->blockCount = 0;
    m_impl->count = 0;
}

bool MetalGaussianSortBuffer::isValid() const
{
    return m_impl->keyBuffer != nullptr && m_impl->keyBuffer->isValid() &&
        m_impl->indexBuffer != nullptr && m_impl->indexBuffer->isValid() &&
        m_impl->scratchKeyBuffer != nullptr && m_impl->scratchKeyBuffer->isValid() &&
        m_impl->scratchIndexBuffer != nullptr && m_impl->scratchIndexBuffer->isValid() &&
        m_impl->blockCountBuffer != nullptr && m_impl->blockCountBuffer->isValid() &&
        m_impl->globalOffsetBuffer != nullptr && m_impl->globalOffsetBuffer->isValid() &&
        m_impl->blockCount > 0 &&
        m_impl->capacity > 0;
}

std::size_t MetalGaussianSortBuffer::capacity() const
{
    return m_impl->capacity;
}

std::size_t MetalGaussianSortBuffer::blockCount() const
{
    return m_impl->blockCount;
}

std::size_t MetalGaussianSortBuffer::sizeBytes() const
{
    std::size_t total = 0;
    const auto addBufferSize = [&total](const std::unique_ptr<MetalBuffer>& buffer) {
        const std::size_t size = buffer == nullptr ? 0 : buffer->size();
        if (size > std::numeric_limits<std::size_t>::max() - total) {
            total = std::numeric_limits<std::size_t>::max();
            return;
        }

        total += size;
    };

    addBufferSize(m_impl->keyBuffer);
    addBufferSize(m_impl->indexBuffer);
    addBufferSize(m_impl->scratchKeyBuffer);
    addBufferSize(m_impl->scratchIndexBuffer);
    addBufferSize(m_impl->blockCountBuffer);
    addBufferSize(m_impl->globalOffsetBuffer);
    return total;
}

uint32_t MetalGaussianSortBuffer::count() const
{
    return m_impl->count;
}

void* MetalGaussianSortBuffer::nativeKeyBuffer() const
{
    return m_impl->keyBuffer == nullptr ? nullptr : m_impl->keyBuffer->nativeBuffer();
}

void* MetalGaussianSortBuffer::nativeIndexBuffer() const
{
    return m_impl->indexBuffer == nullptr ? nullptr : m_impl->indexBuffer->nativeBuffer();
}

void* MetalGaussianSortBuffer::nativeScratchKeyBuffer() const
{
    return m_impl->scratchKeyBuffer == nullptr ? nullptr : m_impl->scratchKeyBuffer->nativeBuffer();
}

void* MetalGaussianSortBuffer::nativeScratchIndexBuffer() const
{
    return m_impl->scratchIndexBuffer == nullptr ? nullptr : m_impl->scratchIndexBuffer->nativeBuffer();
}

void* MetalGaussianSortBuffer::nativeBlockCountBuffer() const
{
    return m_impl->blockCountBuffer == nullptr ? nullptr : m_impl->blockCountBuffer->nativeBuffer();
}

void* MetalGaussianSortBuffer::nativeGlobalOffsetBuffer() const
{
    return m_impl->globalOffsetBuffer == nullptr ? nullptr : m_impl->globalOffsetBuffer->nativeBuffer();
}

} // namespace mesh2splat::metal
