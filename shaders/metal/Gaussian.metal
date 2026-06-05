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

struct GaussianVertexOut {
    float4 position [[position]];
    float4 color;
    float2 localPosition;
};

static float4 transformPoint(Matrix4 matrix, float3 position)
{
    return matrix.columns[0] * position.x +
        matrix.columns[1] * position.y +
        matrix.columns[2] * position.z +
        matrix.columns[3];
}

static float2 clipToNdc(float4 clipPosition)
{
    const float safeW = abs(clipPosition.w) > 1.0e-5 ? clipPosition.w : copysign(1.0e-5, clipPosition.w);
    return clipPosition.xy / safeW;
}

vertex GaussianVertexOut gaussianPreviewVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device GaussianRecord* gaussians [[buffer(0)]],
    constant FrameUniforms& frame [[buffer(1)]],
    const device uint* gaussianIndices [[buffer(2)]])
{
    constexpr float2 corners[6] = {
        float2(-1.0, -1.0),
        float2(1.0, -1.0),
        float2(-1.0, 1.0),
        float2(1.0, -1.0),
        float2(1.0, 1.0),
        float2(-1.0, 1.0),
    };

    const GaussianRecord gaussian = gaussians[gaussianIndices[instanceID]];
    const float2 corner = corners[vertexID % 6];
    const float4 clipPosition = transformPoint(frame.modelViewProjectionMatrix, gaussian.position.xyz);
    const float2 inverseViewport = max(frame.viewport.zw, float2(1.0 / 8192.0));
    const float3 scaleXPosition = gaussian.position.xyz + float3(max(abs(gaussian.scale.x), 1.0e-7), 0.0, 0.0);
    const float3 scaleYPosition = gaussian.position.xyz + float3(0.0, max(abs(gaussian.scale.y), 1.0e-7), 0.0);
    const float2 centerNdc = clipToNdc(clipPosition);
    const float2 scaleXNdc = clipToNdc(transformPoint(frame.modelViewProjectionMatrix, scaleXPosition));
    const float2 scaleYNdc = clipToNdc(transformPoint(frame.modelViewProjectionMatrix, scaleYPosition));
    const float2 viewportPixels = max(frame.viewport.xy, float2(1.0));
    const float radiusX = length((scaleXNdc - centerNdc) * viewportPixels * 0.5);
    const float radiusY = length((scaleYNdc - centerNdc) * viewportPixels * 0.5);
    const float radiusPixels = clamp(max(radiusX, radiusY) * max(frame.gaussianParams.x, 1.0), 1.5, 24.0);
    const float2 ndcOffset = corner * radiusPixels * 2.0 * inverseViewport;

    GaussianVertexOut out;
    out.position = clipPosition;
    out.position.xy += ndcOffset * clipPosition.w;
    out.color = gaussian.color;
    out.localPosition = corner;
    return out;
}

fragment float4 gaussianPreviewFragment(GaussianVertexOut in [[stage_in]])
{
    const float radiusSquared = dot(in.localPosition, in.localPosition);
    if (radiusSquared > 1.0) {
        discard_fragment();
    }

    const float alpha = exp(-radiusSquared * 2.5) * in.color.a * 0.75;
    return float4(in.color.rgb * alpha, alpha);
}
