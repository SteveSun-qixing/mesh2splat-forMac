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
    float4 tangent;
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
    out.tangent = float4(
        normalize(float3(vertices[base + 6], vertices[base + 7], vertices[base + 8])),
        vertices[base + 9]);
    out.uv = float2(vertices[base + 10], vertices[base + 11]);
    out.normalizedUv = float2(vertices[base + 12], vertices[base + 13]);
    return out;
}

fragment float4 meshFragment(
    MeshVertexOut in [[stage_in]],
    constant MeshMaterial* materials [[buffer(0)]],
    constant uint& materialIndex [[buffer(1)]],
    texture2d<float> baseColorTexture [[texture(0)]],
    texture2d<float> metallicRoughnessTexture [[texture(1)]],
    texture2d<float> normalTexture [[texture(2)]],
    texture2d<float> occlusionTexture [[texture(3)]],
    texture2d<float> emissiveTexture [[texture(4)]],
    sampler baseColorSampler [[sampler(0)]])
{
    const MeshMaterial material = materials[materialIndex];
    const float4 textureColor = baseColorTexture.sample(baseColorSampler, in.uv);
    const float4 metallicRoughness = metallicRoughnessTexture.sample(baseColorSampler, in.uv);
    const float occlusion = mix(1.0, occlusionTexture.sample(baseColorSampler, in.uv).r, material.occlusionStrength);
    const float3 emissive = material.emissiveFactor.rgb * emissiveTexture.sample(baseColorSampler, in.uv).rgb;
    const float roughness = clamp(material.roughnessFactor * metallicRoughness.g, 0.04, 1.0);
    const float metallic = clamp(material.metallicFactor * metallicRoughness.b, 0.0, 1.0);
    const float3 vertexNormal = normalize(in.normal);
    const float3 tangent = normalize(in.tangent.xyz - vertexNormal * dot(vertexNormal, in.tangent.xyz));
    const float3 bitangent = normalize(cross(vertexNormal, tangent) * in.tangent.w);
    float3 normalSample = normalTexture.sample(baseColorSampler, in.uv).xyz * 2.0 - 1.0;
    normalSample.xy *= material.normalScale;
    const float3 normal = normalize(tangent * normalSample.x + bitangent * normalSample.y + vertexNormal * normalSample.z);
    const float3 lightDirection = normalize(float3(0.35, 0.8, 0.45));
    const float diffuse = saturate(dot(normal, lightDirection)) * 0.75 + 0.25 * occlusion;
    const float4 baseColor = material.baseColorFactor * textureColor;
    const float specular = pow(saturate(dot(normal, lightDirection)), mix(32.0, 2.0, roughness)) *
        mix(0.04, 0.35, metallic) * (1.0 - roughness);
    const float diffuseWeight = mix(1.0, 0.65, metallic);
    return float4(baseColor.rgb * diffuse * diffuseWeight + specular + emissive, baseColor.a);
}
