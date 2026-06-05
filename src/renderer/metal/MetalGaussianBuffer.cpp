#include "MetalGaussianBuffer.hpp"

#include "MetalBuffer.hpp"
#include "MetalDeviceContext.hpp"

namespace mesh2splat::metal {

struct MetalGaussianBuffer::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    std::unique_ptr<MetalBuffer> buffer;
    std::size_t capacity = 0;
    uint32_t count = 0;
};

MetalGaussianBuffer::MetalGaussianBuffer(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = &deviceContext;
}

MetalGaussianBuffer::~MetalGaussianBuffer() = default;

MetalGaussianBuffer::MetalGaussianBuffer(MetalGaussianBuffer&&) noexcept = default;

MetalGaussianBuffer& MetalGaussianBuffer::operator=(MetalGaussianBuffer&&) noexcept = default;

bool MetalGaussianBuffer::create(std::size_t capacity, const char* label)
{
    if (m_impl->deviceContext == nullptr || capacity == 0 || !core::gaussianCountFitsBuffer(capacity)) {
        return false;
    }

    auto buffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    if (!buffer->createShared(core::gaussianBufferByteSize(capacity), nullptr, label)) {
        return false;
    }

    m_impl->buffer = std::move(buffer);
    m_impl->capacity = capacity;
    m_impl->count = 0;
    return true;
}

bool MetalGaussianBuffer::upload(const std::vector<core::GaussianRecord>& gaussians, const char* label)
{
    if (m_impl->deviceContext == nullptr || gaussians.empty() || !core::gaussianCountFitsBuffer(gaussians.size())) {
        reset();
        return false;
    }

    auto buffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    if (!buffer->createShared(
            core::gaussianBufferByteSize(gaussians.size()),
            gaussians.data(),
            label)) {
        reset();
        return false;
    }

    m_impl->buffer = std::move(buffer);
    m_impl->capacity = gaussians.size();
    m_impl->count = static_cast<uint32_t>(gaussians.size());
    return true;
}

bool MetalGaussianBuffer::setCount(uint32_t count)
{
    if (count > m_impl->capacity) {
        return false;
    }

    m_impl->count = count;
    return true;
}

void MetalGaussianBuffer::reset()
{
    m_impl->buffer.reset();
    m_impl->capacity = 0;
    m_impl->count = 0;
}

bool MetalGaussianBuffer::isValid() const
{
    return m_impl->buffer != nullptr && m_impl->buffer->isValid() && m_impl->capacity > 0;
}

std::size_t MetalGaussianBuffer::capacity() const
{
    return m_impl->capacity;
}

uint32_t MetalGaussianBuffer::count() const
{
    return m_impl->count;
}

std::size_t MetalGaussianBuffer::sizeBytes() const
{
    return m_impl->buffer == nullptr ? 0 : m_impl->buffer->size();
}

void* MetalGaussianBuffer::nativeBuffer() const
{
    return m_impl->buffer == nullptr ? nullptr : m_impl->buffer->nativeBuffer();
}

} // namespace mesh2splat::metal
