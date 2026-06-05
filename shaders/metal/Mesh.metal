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

struct MeshVertexOut {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    float2 normalizedUv;
};

static float4 transformPoint(Matrix4 matrix, float3 position)
{
    return matrix.columns[0] * position.x +
        matrix.columns[1] * position.y +
        matrix.columns[2] * position.z +
        matrix.columns[3];
}

vertex MeshVertexOut meshVertex(
    uint vertexID [[vertex_id]],
    const device float* vertices [[buffer(0)]],
    constant FrameUniforms& frame [[buffer(1)]])
{
    const uint base = vertexID * 17;

    MeshVertexOut out;
    const float3 position = float3(vertices[base + 0], vertices[base + 1], vertices[base + 2]);
    out.position = transformPoint(frame.modelViewProjectionMatrix, position);
    out.normal = normalize(float3(vertices[base + 3], vertices[base + 4], vertices[base + 5]));
    out.uv = float2(vertices[base + 10], vertices[base + 11]);
    out.normalizedUv = float2(vertices[base + 12], vertices[base + 13]);
    return out;
}

fragment float4 meshFragment(MeshVertexOut in [[stage_in]])
{
    const float3 normalColor = in.normal * 0.5 + 0.5;
    const float3 uvColor = float3(in.normalizedUv.x, in.normalizedUv.y, 1.0 - in.normalizedUv.x);
    return float4(mix(normalColor, uvColor, 0.65), 1.0);
}
