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

struct MeshMaterial {
    float4 baseColorFactor;
    float4 emissiveFactor;
    float metallicFactor;
    float roughnessFactor;
    float occlusionStrength;
    float normalScale;
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

fragment float4 meshFragment(
    MeshVertexOut in [[stage_in]],
    constant MeshMaterial* materials [[buffer(0)]],
    constant uint& materialIndex [[buffer(1)]])
{
    const MeshMaterial material = materials[materialIndex];
    const float3 normal = normalize(in.normal);
    const float3 lightDirection = normalize(float3(0.35, 0.8, 0.45));
    const float diffuse = saturate(dot(normal, lightDirection)) * 0.75 + 0.25;
    const float3 baseColor = material.baseColorFactor.rgb * diffuse + material.emissiveFactor.rgb;
    return float4(baseColor, material.baseColorFactor.a);
}
