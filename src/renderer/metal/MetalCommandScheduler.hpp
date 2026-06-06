#pragma once

#include <string>

namespace mesh2splat::metal {

struct MetalCommandBufferDiagnostics {
    bool valid = false;
    bool completed = false;
    bool failed = false;
    int status = -1;
    double gpuMilliseconds = 0.0;
    std::string label;
    std::string statusDescription;
    std::string errorDescription;
};

class MetalCommandScheduler {
public:
    explicit MetalCommandScheduler(void* commandQueue);

    void* createCommandBuffer(const char* label = nullptr) const;
    bool commit(void* commandBuffer) const;
    bool commitAndWait(void* commandBuffer) const;

    static bool setCommandBufferLabel(void* commandBuffer, const char* label);
    static std::string commandBufferLabel(void* commandBuffer);
    static bool commitCommandBuffer(void* commandBuffer);
    static bool waitUntilCompleted(void* commandBuffer);
    static bool presentDrawable(void* commandBuffer, void* drawable);
    static bool commandBufferCompleted(void* commandBuffer);
    static int commandBufferStatus(void* commandBuffer);
    static double commandBufferGpuMilliseconds(void* commandBuffer);
    static std::string commandBufferStatusDescription(int status);
    static std::string commandBufferStatusDescription(void* commandBuffer);
    static std::string commandBufferErrorDescription(void* commandBuffer);
    static MetalCommandBufferDiagnostics commandBufferDiagnostics(void* commandBuffer);

private:
    void* m_commandQueue = nullptr;
};

} // namespace mesh2splat::metal
