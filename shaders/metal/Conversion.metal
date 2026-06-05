#include <metal_stdlib>

using namespace metal;

struct MeshMaterial {
    float4 baseColorFactor;
    float4 emissiveFactor;
    float metallicFactor;
    float roughnessFactor;
    float occlusionStrength;
    float normalScale;
};

struct GaussianRecord {
    float4 position;
    float4 color;
    float4 scale;
    float4 normal;
    float4 rotation;
    float4 pbr;
};

struct MeshConversionParams {
    uint vertexOffset;
    uint triangleCount;
    uint materialIndex;
    uint maxGaussianCount;
    float gaussianScale;
    float normalScale;
    uint flags;
    uint reserved;
};

static float3 safeNormalize(float3 value, float3 fallback)
{
    const float lengthSquared = dot(value, value);
    return lengthSquared > 1.0e-12 ? value * rsqrt(lengthSquared) : fallback;
}

kernel void meshVertexConversionKernel(
    uint threadID [[thread_position_in_grid]],
    const device float* vertices [[buffer(0)]],
    constant MeshMaterial* materials [[buffer(1)]],
    device GaussianRecord* gaussians [[buffer(2)]],
    constant MeshConversionParams& params [[buffer(3)]],
    device atomic_uint* gaussianCounter [[buffer(4)]])
{
    if (threadID >= params.triangleCount) {
        return;
    }

    const uint outputBase = atomic_fetch_add_explicit(gaussianCounter, 3u, memory_order_relaxed);
    if (outputBase + 2u >= params.maxGaussianCount) {
        return;
    }

    const uint firstVertexIndex = params.vertexOffset + threadID * 3;
    const MeshMaterial material = materials[params.materialIndex];

    const uint base0 = firstVertexIndex * 17;
    const uint base1 = (firstVertexIndex + 1) * 17;
    const uint base2 = (firstVertexIndex + 2) * 17;
    const float3 p0 = float3(vertices[base0 + 0], vertices[base0 + 1], vertices[base0 + 2]);
    const float3 p1 = float3(vertices[base1 + 0], vertices[base1 + 1], vertices[base1 + 2]);
    const float3 p2 = float3(vertices[base2 + 0], vertices[base2 + 1], vertices[base2 + 2]);
    const float3 edge0 = p1 - p0;
    const float3 edge1 = p2 - p0;
    const float3 faceNormal = safeNormalize(cross(edge0, edge1), float3(0.0, 1.0, 0.0));
    const float scaleX = max(length(edge0) * params.gaussianScale, 1.0e-7);
    const float scaleY = max(length(edge1) * params.gaussianScale, 1.0e-7);

    for (uint corner = 0; corner < 3; ++corner) {
        const uint vertexIndex = firstVertexIndex + corner;
        const uint base = vertexIndex * 17;
        const float3 position = float3(vertices[base + 0], vertices[base + 1], vertices[base + 2]);
        const float3 vertexNormal = safeNormalize(
            float3(vertices[base + 3], vertices[base + 4], vertices[base + 5]),
            faceNormal);
        const float3 normal = safeNormalize(vertexNormal + faceNormal * params.normalScale, faceNormal);
        const uint outputIndex = outputBase + corner;

        GaussianRecord gaussian;
        gaussian.position = float4(position, 1.0);
        gaussian.color = material.baseColorFactor;
        gaussian.scale = float4(scaleX, scaleY, 1.0e-7, 0.0);
        gaussian.normal = float4(normal, 0.0);
        gaussian.rotation = float4(1.0, 0.0, 0.0, 0.0);
        gaussian.pbr = float4(material.metallicFactor, material.roughnessFactor, material.occlusionStrength, 1.0);
        gaussians[outputIndex] = gaussian;
    }
}
