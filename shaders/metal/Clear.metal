#include <metal_stdlib>

using namespace metal;

struct ClearVertexOut {
    float4 position [[position]];
};

vertex ClearVertexOut clearVertex(uint vertexID [[vertex_id]])
{
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0),
    };

    ClearVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    return out;
}

fragment float4 clearFragment()
{
    return float4(0.03, 0.04, 0.05, 1.0);
}

struct ClearBufferParams {
    uint elementOffset;
    uint elementCount;
    uint value;
    uint reserved;
};

struct ClearCounterParams {
    uint counterOffset;
    uint counterCount;
    uint value;
    uint reserved;
};

struct ClearTexture2DFloatParams {
    uint2 origin;
    uint2 extent;
    float4 value;
};

struct ClearTexture2DUintParams {
    uint2 origin;
    uint2 extent;
    uint4 value;
};

struct ClearTexturePackParams {
    uint2 origin;
    uint2 extent;
    uint destinationOffsetPixels;
    uint destinationRowStridePixels;
    uint reserved0;
    uint reserved1;
};

struct ClearGaussianTexturePackParams {
    uint2 origin;
    uint2 extent;
    uint maxGaussianCount;
    uint flags;
    uint reserved0;
    uint reserved1;
};

struct ClearGaussianRecord {
    float4 position;
    float4 color;
    float4 scale;
    float4 normal;
    float4 rotation;
    float4 pbr;
};

static uint2 clearResolveExtent2D(uint2 origin, uint2 requestedExtent, uint2 textureSize)
{
    if (origin.x >= textureSize.x || origin.y >= textureSize.y) {
        return uint2(0);
    }

    const uint2 remaining = textureSize - origin;
    return uint2(
        requestedExtent.x == 0u ? remaining.x : min(requestedExtent.x, remaining.x),
        requestedExtent.y == 0u ? remaining.y : min(requestedExtent.y, remaining.y));
}

static uint clearPackRgba8Unorm(float4 value)
{
    const uint4 packed = uint4(round(clamp(value, float4(0.0), float4(1.0)) * 255.0));
    return packed.x | (packed.y << 8u) | (packed.z << 16u) | (packed.w << 24u);
}

kernel void clearBufferUintKernel(
    uint threadID [[thread_position_in_grid]],
    device uint* buffer [[buffer(0)]],
    constant ClearBufferParams& params [[buffer(1)]])
{
    if (threadID >= params.elementCount) {
        return;
    }

    buffer[params.elementOffset + threadID] = params.value;
}

kernel void resetCounterKernel(
    uint threadID [[thread_position_in_grid]],
    device atomic_uint* counters [[buffer(0)]],
    constant ClearCounterParams& params [[buffer(1)]])
{
    if (threadID >= params.counterCount) {
        return;
    }

    atomic_store_explicit(
        &counters[params.counterOffset + threadID],
        params.value,
        memory_order_relaxed);
}

kernel void resetGaussianCounterKernel(
    uint threadID [[thread_position_in_grid]],
    device atomic_uint* gaussianCounter [[buffer(0)]])
{
    if (threadID == 0u) {
        atomic_store_explicit(gaussianCounter, 0u, memory_order_relaxed);
    }
}

kernel void clearTexture2DFloatKernel(
    uint2 threadID [[thread_position_in_grid]],
    texture2d<float, access::write> target [[texture(0)]],
    constant ClearTexture2DFloatParams& params [[buffer(0)]])
{
    const uint2 textureSize = uint2(target.get_width(), target.get_height());
    const uint2 extent = clearResolveExtent2D(params.origin, params.extent, textureSize);
    if (threadID.x >= extent.x || threadID.y >= extent.y) {
        return;
    }

    target.write(params.value, params.origin + threadID);
}

kernel void clearTexture2DUintKernel(
    uint2 threadID [[thread_position_in_grid]],
    texture2d<uint, access::write> target [[texture(0)]],
    constant ClearTexture2DUintParams& params [[buffer(0)]])
{
    const uint2 textureSize = uint2(target.get_width(), target.get_height());
    const uint2 extent = clearResolveExtent2D(params.origin, params.extent, textureSize);
    if (threadID.x >= extent.x || threadID.y >= extent.y) {
        return;
    }

    target.write(params.value, params.origin + threadID);
}

kernel void packTexture2DRgba8Kernel(
    uint2 threadID [[thread_position_in_grid]],
    texture2d<float, access::read> source [[texture(0)]],
    device uint* packedPixels [[buffer(0)]],
    constant ClearTexturePackParams& params [[buffer(1)]])
{
    const uint2 textureSize = uint2(source.get_width(), source.get_height());
    const uint2 extent = clearResolveExtent2D(params.origin, params.extent, textureSize);
    if (threadID.x >= extent.x || threadID.y >= extent.y) {
        return;
    }

    const uint rowStride = params.destinationRowStridePixels == 0u
        ? extent.x
        : params.destinationRowStridePixels;
    const uint destinationIndex =
        params.destinationOffsetPixels + threadID.y * rowStride + threadID.x;
    packedPixels[destinationIndex] = clearPackRgba8Unorm(source.read(params.origin + threadID));
}

kernel void packGaussianTexturesKernel(
    uint2 threadID [[thread_position_in_grid]],
    device ClearGaussianRecord* gaussians [[buffer(0)]],
    device atomic_uint* gaussianCounter [[buffer(1)]],
    constant ClearGaussianTexturePackParams& params [[buffer(2)]],
    texture2d<float, access::read> positionAndScaleXTexture [[texture(0)]],
    texture2d<float, access::read> scaleZAndNormalTexture [[texture(1)]],
    texture2d<float, access::read> rotationTexture [[texture(2)]],
    texture2d<float, access::read> colorTexture [[texture(3)]],
    texture2d<float, access::read> pbrAndScaleYTexture [[texture(4)]])
{
    const uint2 textureSize = uint2(
        positionAndScaleXTexture.get_width(),
        positionAndScaleXTexture.get_height());
    const uint2 extent = clearResolveExtent2D(params.origin, params.extent, textureSize);
    if (threadID.x >= extent.x || threadID.y >= extent.y) {
        return;
    }

    const uint2 sourceCoordinate = params.origin + threadID;
    const float4 positionAndScaleX = positionAndScaleXTexture.read(sourceCoordinate);
    if ((params.flags & 1u) != 0u && all(positionAndScaleX == float4(0.0))) {
        return;
    }

    const uint outputIndex = atomic_fetch_add_explicit(
        gaussianCounter,
        1u,
        memory_order_relaxed);
    if (outputIndex >= params.maxGaussianCount) {
        return;
    }

    const float4 scaleZAndNormal = scaleZAndNormalTexture.read(sourceCoordinate);
    const float4 pbrAndScaleY = pbrAndScaleYTexture.read(sourceCoordinate);

    ClearGaussianRecord gaussian;
    gaussian.position = float4(positionAndScaleX.xyz, 1.0);
    gaussian.color = colorTexture.read(sourceCoordinate);
    gaussian.scale = float4(positionAndScaleX.w, pbrAndScaleY.z, scaleZAndNormal.x, 0.0);
    gaussian.normal = float4(scaleZAndNormal.yzw, 0.0);
    gaussian.rotation = rotationTexture.read(sourceCoordinate);
    gaussian.pbr = float4(pbrAndScaleY.x, pbrAndScaleY.y, 1.0, pbrAndScaleY.w);
    gaussians[outputIndex] = gaussian;
}
