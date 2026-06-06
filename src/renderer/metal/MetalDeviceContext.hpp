#pragma once

#include <cstddef>
#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalDeviceContext {
public:
    enum class ArgumentBufferTier {
        Unsupported,
        Tier1,
        Tier2,
    };

    struct Capabilities {
        std::string deviceName;
        std::size_t maxBufferLength = 0;
        ArgumentBufferTier argumentBufferTier = ArgumentBufferTier::Unsupported;
        bool supportsArgumentBuffers = false;
        bool hasUnifiedMemory = false;
        bool isLowPower = false;
        bool isRemovable = false;
        bool isHeadless = false;
    };

    explicit MetalDeviceContext(void* metalDevice);
    ~MetalDeviceContext();

    MetalDeviceContext(const MetalDeviceContext&) = delete;
    MetalDeviceContext& operator=(const MetalDeviceContext&) = delete;

    bool initialize();
    bool isValid() const;

    void* nativeDevice() const;
    void* nativeCommandQueue() const;

    const Capabilities& capabilities() const;
    const std::string& deviceName() const;
    std::size_t maxBufferLength() const;
    ArgumentBufferTier argumentBufferTier() const;
    bool supportsArgumentBuffers() const;
    bool hasUnifiedMemory() const;
    bool isLowPower() const;
    bool isRemovable() const;
    bool isHeadless() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
