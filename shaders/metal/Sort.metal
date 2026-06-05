#include <metal_stdlib>

using namespace metal;

struct Matrix4 {
    float4 columns[4];
};

struct FrameUniforms {
    Matrix4 modelMatrix;
    Matrix4 viewMatrix;
    Matrix4 projectionMatrix;
    Matrix4 modelViewProjectionMatrix;
    float4 cameraPosition;
    float4 hfovFocal;
    float4 viewport;
    float4 clippingPlanes;
    float4 gaussianParams;
    uint frameIndex;
    uint renderMode;
    uint flags;
    uint reserved;
};

struct GaussianRecord {
    float4 position;
    float4 color;
    float4 scale;
    float4 normal;
    float4 rotation;
    float4 pbr;
};

struct GaussianSortParams {
    uint gaussianCount;
    uint flags;
    uint reserved0;
    uint reserved1;
};

static float4 transformPoint(Matrix4 matrix, float3 position)
{
    return matrix.columns[0] * position.x +
        matrix.columns[1] * position.y +
        matrix.columns[2] * position.z +
        matrix.columns[3];
}

static uint sortableFloatKey(float value)
{
    const uint bits = as_type<uint>(value);
    const uint sign = bits >> 31;
    return sign == 0 ? (bits ^ 0x80000000u) : ~bits;
}

kernel void gaussianDepthKeyKernel(
    uint threadID [[thread_position_in_grid]],
    const device GaussianRecord* gaussians [[buffer(0)]],
    constant FrameUniforms& frame [[buffer(1)]],
    device uint* depthKeys [[buffer(2)]],
    device uint* indices [[buffer(3)]],
    constant GaussianSortParams& params [[buffer(4)]])
{
    if (threadID >= params.gaussianCount) {
        return;
    }

    const GaussianRecord gaussian = gaussians[threadID];
    const float4 viewPosition = transformPoint(frame.viewMatrix, gaussian.position.xyz);
    const float positiveDepth = max(-viewPosition.z, 0.0);
    depthKeys[threadID] = sortableFloatKey(positiveDepth);
    indices[threadID] = threadID;
}
