#pragma once

namespace mesh2splat::metal {

class MetalCommandScheduler {
public:
    explicit MetalCommandScheduler(void* commandQueue);

    void* createCommandBuffer(const char* label = nullptr) const;
    bool commit(void* commandBuffer) const;
    bool commitAndWait(void* commandBuffer) const;

    static bool commandBufferCompleted(void* commandBuffer);

private:
    void* m_commandQueue = nullptr;
};

} // namespace mesh2splat::metal
