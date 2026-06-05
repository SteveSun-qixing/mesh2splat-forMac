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
    uint samplesPerTriangle;
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
    device atomic_uint* gaussianCounter [[buffer(4)]],
    texture2d<float> baseColorTexture [[texture(0)]],
    texture2d<float> metallicRoughnessTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]])
{
    const uint samplesPerTriangle = max(params.samplesPerTriangle, 1u);
    const uint triangleID = threadID / samplesPerTriangle;
    const uint sampleID = threadID - triangleID * samplesPerTriangle;
    if (triangleID >= params.triangleCount) {
        return;
    }

    const uint outputIndex = atomic_fetch_add_explicit(gaussianCounter, 1u, memory_order_relaxed);
    if (outputIndex >= params.maxGaussianCount) {
        return;
    }

    const uint firstVertexIndex = params.vertexOffset + triangleID * 3;
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

    const float3 barycentricSamples[4] = {
        float3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0),
        float3(0.6, 0.2, 0.2),
        float3(0.2, 0.6, 0.2),
        float3(0.2, 0.2, 0.6),
    };
    const float3 barycentric = barycentricSamples[sampleID % 4];
    const float3 position = p0 * barycentric.x + p1 * barycentric.y + p2 * barycentric.z;
    const float3 n0 = safeNormalize(float3(vertices[base0 + 3], vertices[base0 + 4], vertices[base0 + 5]), faceNormal);
    const float3 n1 = safeNormalize(float3(vertices[base1 + 3], vertices[base1 + 4], vertices[base1 + 5]), faceNormal);
    const float3 n2 = safeNormalize(float3(vertices[base2 + 3], vertices[base2 + 4], vertices[base2 + 5]), faceNormal);
    const float3 vertexNormal = safeNormalize(n0 * barycentric.x + n1 * barycentric.y + n2 * barycentric.z, faceNormal);
    const float3 normal = safeNormalize(vertexNormal + faceNormal * params.normalScale, faceNormal);
    const float2 uv0 = float2(vertices[base0 + 10], vertices[base0 + 11]);
    const float2 uv1 = float2(vertices[base1 + 10], vertices[base1 + 11]);
    const float2 uv2 = float2(vertices[base2 + 10], vertices[base2 + 11]);
    const float2 uv = uv0 * barycentric.x + uv1 * barycentric.y + uv2 * barycentric.z;
    const float4 baseColor = material.baseColorFactor * baseColorTexture.sample(textureSampler, uv);
    const float4 metallicRoughness = metallicRoughnessTexture.sample(textureSampler, uv);

    GaussianRecord gaussian;
    gaussian.position = float4(position, 1.0);
    gaussian.color = baseColor;
    gaussian.scale = float4(scaleX, scaleY, 1.0e-7, 0.0);
    gaussian.normal = float4(normal, 0.0);
    gaussian.rotation = float4(1.0, 0.0, 0.0, 0.0);
    gaussian.pbr = float4(
        material.metallicFactor * metallicRoughness.b,
        material.roughnessFactor * metallicRoughness.g,
        material.occlusionStrength,
        1.0);
    gaussians[outputIndex] = gaussian;
}
