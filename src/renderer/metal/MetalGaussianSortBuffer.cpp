#include "MetalGaussianSortBuffer.hpp"

#include "MetalBuffer.hpp"
#include "MetalDeviceContext.hpp"

#include <limits>
#include <string>

namespace mesh2splat::metal {

struct MetalGaussianSortBuffer::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    std::unique_ptr<MetalBuffer> keyBuffer;
    std::unique_ptr<MetalBuffer> indexBuffer;
    std::size_t capacity = 0;
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

    const std::string baseLabel = label != nullptr ? label : "Metal Gaussian Sort";
    auto keyBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto indexBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    const std::size_t bufferSize = capacity * sizeof(uint32_t);
    if (!keyBuffer->createPrivate(bufferSize, (baseLabel + " Keys").c_str()) ||
        !indexBuffer->createPrivate(bufferSize, (baseLabel + " Indices").c_str())) {
        return false;
    }

    m_impl->keyBuffer = std::move(keyBuffer);
    m_impl->indexBuffer = std::move(indexBuffer);
    m_impl->capacity = capacity;
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
    m_impl->capacity = 0;
    m_impl->count = 0;
}

bool MetalGaussianSortBuffer::isValid() const
{
    return m_impl->keyBuffer != nullptr && m_impl->keyBuffer->isValid() &&
        m_impl->indexBuffer != nullptr && m_impl->indexBuffer->isValid() &&
        m_impl->capacity > 0;
}

std::size_t MetalGaussianSortBuffer::capacity() const
{
    return m_impl->capacity;
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

} // namespace mesh2splat::metal
