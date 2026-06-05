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
    uint vertexCount;
    uint materialIndex;
    uint outputOffset;
    float gaussianScale;
    float normalScale;
    uint flags;
    uint reserved;
};

kernel void meshVertexConversionKernel(
    uint threadID [[thread_position_in_grid]],
    const device float* vertices [[buffer(0)]],
    constant MeshMaterial* materials [[buffer(1)]],
    device GaussianRecord* gaussians [[buffer(2)]],
    constant MeshConversionParams& params [[buffer(3)]])
{
    if (threadID >= params.vertexCount) {
        return;
    }

    const uint vertexIndex = params.vertexOffset + threadID;
    const uint base = vertexIndex * 17;
    const MeshMaterial material = materials[params.materialIndex];

    const float3 position = float3(vertices[base + 0], vertices[base + 1], vertices[base + 2]);
    const float3 normal = normalize(float3(vertices[base + 3], vertices[base + 4], vertices[base + 5]));
    const uint outputIndex = params.outputOffset + threadID;

    GaussianRecord gaussian;
    gaussian.position = float4(position, 1.0);
    gaussian.color = material.baseColorFactor;
    gaussian.scale = float4(params.gaussianScale, params.gaussianScale, 1.0e-7, 0.0);
    gaussian.normal = float4(normal, 0.0);
    gaussian.rotation = float4(1.0, 0.0, 0.0, 0.0);
    gaussian.pbr = float4(material.metallicFactor, material.roughnessFactor, material.occlusionStrength, 1.0);
    gaussians[outputIndex] = gaussian;
}
