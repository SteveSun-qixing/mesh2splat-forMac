#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace mesh2splat::metal {

class MetalDiagnostics;
class MetalFrameUniformBuffer;
class MetalPipelineCache;
class MetalRenderStateCache;
class MetalRenderTarget;

enum class MetalPassRenderMode : uint32_t {
    Combined = 0,
    MeshOnly = 1,
    GaussianOnly = 2,
};

enum class MetalPassDiagnosticSeverity : uint32_t {
    Info = 0,
    Warning = 1,
    Error = 2,
};

enum class MetalPassFlag : uint32_t {
    None = 0,
    RenderMesh = 1u << 0u,
    RenderGaussians = 1u << 1u,
    SortGaussians = 1u << 2u,
    ConvertMeshToGaussians = 1u << 3u,
    HasColorTarget = 1u << 4u,
    HasDepthTarget = 1u << 5u,
    DebugCapture = 1u << 6u,
};

using MetalPassFlags = uint32_t;

constexpr MetalPassFlags toMetalPassFlags(MetalPassFlag flag)
{
    return static_cast<MetalPassFlags>(flag);
}

constexpr MetalPassFlags operator|(MetalPassFlag lhs, MetalPassFlag rhs)
{
    return toMetalPassFlags(lhs) | toMetalPassFlags(rhs);
}

constexpr MetalPassFlags operator|(MetalPassFlags lhs, MetalPassFlag rhs)
{
    return lhs | toMetalPassFlags(rhs);
}

constexpr MetalPassFlags operator|(MetalPassFlag lhs, MetalPassFlags rhs)
{
    return toMetalPassFlags(lhs) | rhs;
}

constexpr MetalPassFlags operator&(MetalPassFlags lhs, MetalPassFlag rhs)
{
    return lhs & toMetalPassFlags(rhs);
}

constexpr MetalPassFlags operator&(MetalPassFlag lhs, MetalPassFlags rhs)
{
    return toMetalPassFlags(lhs) & rhs;
}

constexpr bool hasMetalPassFlag(MetalPassFlags flags, MetalPassFlag flag)
{
    return (flags & flag) != 0;
}

struct MetalPassDrawableSize {
    uint32_t width = 0;
    uint32_t height = 0;
    float backingScale = 1.0f;

    bool isEmpty() const
    {
        return width == 0 || height == 0;
    }
};

struct MetalPassNativeHandles {
    void* commandBuffer = nullptr;
    void* renderCommandEncoder = nullptr;
    void* computeCommandEncoder = nullptr;
    void* renderPassDescriptor = nullptr;
    void* drawable = nullptr;
    void* drawableTexture = nullptr;
    void* depthTexture = nullptr;
    void* frameUniformBuffer = nullptr;
};

struct MetalPassCommandContext {
    void* commandBuffer = nullptr;
    void* renderCommandEncoder = nullptr;
    void* computeCommandEncoder = nullptr;
    void* renderPassDescriptor = nullptr;

    bool hasCommandBuffer() const
    {
        return commandBuffer != nullptr;
    }

    bool hasRenderEncoder() const
    {
        return renderCommandEncoder != nullptr;
    }

    bool hasComputeEncoder() const
    {
        return computeCommandEncoder != nullptr;
    }

    bool hasRenderPassDescriptor() const
    {
        return renderPassDescriptor != nullptr;
    }
};

struct MetalPassRenderTargetContext {
    MetalRenderTarget* target = nullptr;
    void* colorTexture = nullptr;
    void* depthTexture = nullptr;
    MetalPassDrawableSize drawableSize;

    bool hasTarget() const
    {
        return target != nullptr;
    }

    bool hasColorTexture() const
    {
        return colorTexture != nullptr;
    }

    bool hasDepthTexture() const
    {
        return depthTexture != nullptr;
    }

    bool hasDrawableSize() const
    {
        return !drawableSize.isEmpty();
    }
};

struct MetalPassFrameUniformContext {
    MetalFrameUniformBuffer* uniformBuffer = nullptr;
    void* buffer = nullptr;
    uint32_t frameSlot = 0;
    std::size_t offset = 0;
    std::size_t size = 0;
    bool valid = false;

    bool hasUniformBuffer() const
    {
        return uniformBuffer != nullptr;
    }

    bool hasBuffer() const
    {
        return buffer != nullptr;
    }

    bool isValid() const
    {
        return valid && hasBuffer();
    }
};

struct MetalPassCacheContext {
    MetalPipelineCache* pipelineCache = nullptr;
    MetalRenderStateCache* stateCache = nullptr;

    bool hasPipelineCache() const
    {
        return pipelineCache != nullptr;
    }

    bool hasStateCache() const
    {
        return stateCache != nullptr;
    }
};

struct MetalPassDiagnostic {
    MetalPassDiagnosticSeverity severity = MetalPassDiagnosticSeverity::Info;
    const char* message = nullptr;
    const char* passLabel = nullptr;
    uint64_t frameIndex = 0;
    uint64_t resourceSerial = 0;
};

using MetalPassDiagnosticSink = void (*)(const MetalPassDiagnostic& diagnostic, void* userData);

struct MetalPassDiagnosticSinkRef {
    MetalPassDiagnosticSink sink = nullptr;
    void* userData = nullptr;

    bool isValid() const
    {
        return sink != nullptr;
    }

    void report(const MetalPassDiagnostic& diagnostic) const
    {
        if (sink != nullptr) {
            sink(diagnostic, userData);
        }
    }
};

struct MetalPassContext {
    uint64_t frameIndex = 0;
    MetalPassDrawableSize drawableSize;
    MetalPassRenderMode renderMode = MetalPassRenderMode::Combined;
    uint64_t resourceSerial = 0;
    std::string debugLabel;
    MetalPassNativeHandles nativeHandles;
    MetalPassCommandContext command;
    MetalPassRenderTargetContext renderTarget;
    MetalPassFrameUniformContext frameUniform;
    MetalPassCacheContext caches;
    MetalDiagnostics* diagnostics = nullptr;
    MetalPassFlags flags = toMetalPassFlags(MetalPassFlag::None);
    MetalPassDiagnosticSinkRef diagnosticSink;

    bool hasFlag(MetalPassFlag flag) const
    {
        return hasMetalPassFlag(flags, flag);
    }

    bool hasDrawableSize() const
    {
        return !drawableSize.isEmpty();
    }

    bool hasCommandBuffer() const
    {
        return command.hasCommandBuffer() || nativeHandles.commandBuffer != nullptr;
    }

    bool hasRenderTarget() const
    {
        return renderTarget.hasTarget()
            || renderTarget.hasColorTexture()
            || renderTarget.hasDepthTexture()
            || nativeHandles.drawableTexture != nullptr
            || nativeHandles.depthTexture != nullptr;
    }

    bool hasFrameUniform() const
    {
        return frameUniform.isValid() || nativeHandles.frameUniformBuffer != nullptr;
    }

    bool hasPipelineCache() const
    {
        return caches.hasPipelineCache();
    }

    bool hasStateCache() const
    {
        return caches.hasStateCache();
    }

    bool hasDiagnostics() const
    {
        return diagnostics != nullptr || diagnosticSink.isValid();
    }

    void reportDiagnostic(MetalPassDiagnosticSeverity severity, const char* message) const
    {
        MetalPassDiagnostic diagnostic;
        diagnostic.severity = severity;
        diagnostic.message = message;
        diagnostic.passLabel = debugLabel.empty() ? nullptr : debugLabel.c_str();
        diagnostic.frameIndex = frameIndex;
        diagnostic.resourceSerial = resourceSerial;
        diagnosticSink.report(diagnostic);
    }
};

} // namespace mesh2splat::metal
