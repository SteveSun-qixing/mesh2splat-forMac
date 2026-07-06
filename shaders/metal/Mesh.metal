#include <metal_stdlib>

using namespace metal;

constant constexpr uint kM2SMeshShaderVertexFloatCount = 17u;
constant constexpr uint kM2SMeshShaderPositionOffset = 0u;
constant constexpr uint kM2SMeshShaderNormalOffset = 3u;
constant constexpr uint kM2SMeshShaderTangentOffset = 6u;
constant constexpr uint kM2SMeshShaderUvOffset = 10u;
constant constexpr uint kM2SMeshShaderNormalizedUvOffset = 12u;

constant constexpr uint kM2SMeshShaderRenderModeDepth = 1u;
constant constexpr uint kM2SMeshShaderRenderModeNormal = 2u;
constant constexpr uint kM2SMeshShaderRenderModeGeometryColor = 3u;
constant constexpr uint kM2SMeshShaderRenderModeDensity = 4u;
constant constexpr uint kM2SMeshShaderRenderModePbr = 5u;
constant constexpr uint kM2SMeshShaderRenderModeLitPreview = 6u;
constant constexpr uint kM2SMeshShaderDebugFlagDisableToneMapping = 1u << 6u;

constant constexpr float kM2SMeshShaderMinimumLengthSquared = 1.0e-12f;
constant constexpr float kM2SMeshShaderAlphaDiscardThreshold = 1.0e-4f;
constant constexpr float kM2SMeshShaderPi = 3.14159265358979323846f;

struct M2SMeshShaderMatrix4 {
    float4 columns[4];
};

struct M2SMeshShaderFrameUniforms {
    M2SMeshShaderMatrix4 modelMatrix;
    M2SMeshShaderMatrix4 viewMatrix;
    M2SMeshShaderMatrix4 projectionMatrix;
    M2SMeshShaderMatrix4 modelViewProjectionMatrix;
    float4 cameraPosition;
    float4 hfovFocal;
    float4 viewport;
    float4 clippingPlanes;
    float4 gaussianParams;
    uint frameIndex;
    uint renderMode;
    uint flags;
    uint reserved;
    float4 frameTiming;
    float4 lightPositionIntensity;
    float4 lightColorFlags;
};

struct M2SMeshShaderMaterial {
    float4 baseColorFactor;
    float4 emissiveFactor;
    float metallicFactor;
    float roughnessFactor;
    float occlusionStrength;
    float normalScale;
};

struct M2SMeshShaderVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float4 tangent;
    float2 uv;
    float2 normalizedUv;
    float viewDepth;
    float2 clippingPlanes;
    float3 viewDirection;
    uint renderMode [[flat]];
};

static_assert(sizeof(M2SMeshShaderMatrix4) == 64, "Mesh matrix ABI must remain four float4 columns.");
static_assert(sizeof(M2SMeshShaderFrameUniforms) == 400, "Mesh frame uniforms must match FrameUniforms.");
static_assert(sizeof(M2SMeshShaderMaterial) == 48, "Mesh material must match MetalMeshMaterial.");

static bool m2sMeshShaderFinite(float value)
{
    return isfinite(value);
}

static bool m2sMeshShaderFinite(float2 value)
{
    return all(isfinite(value));
}

static bool m2sMeshShaderFinite(float3 value)
{
    return all(isfinite(value));
}

static bool m2sMeshShaderFinite(float4 value)
{
    return all(isfinite(value));
}

static float m2sMeshShaderFiniteOr(float value, float fallback)
{
    return m2sMeshShaderFinite(value) ? value : fallback;
}

static float2 m2sMeshShaderFiniteOr(float2 value, float2 fallback)
{
    return m2sMeshShaderFinite(value) ? value : fallback;
}

static float3 m2sMeshShaderFiniteOr(float3 value, float3 fallback)
{
    return m2sMeshShaderFinite(value) ? value : fallback;
}

static float4 m2sMeshShaderFiniteOr(float4 value, float4 fallback)
{
    return m2sMeshShaderFinite(value) ? value : fallback;
}

static float3 m2sMeshShaderSafeNormalize(float3 value, float3 fallback)
{
    const float lengthSquared = dot(value, value);
    return m2sMeshShaderFinite(lengthSquared) && lengthSquared > kM2SMeshShaderMinimumLengthSquared ?
        value * rsqrt(lengthSquared) :
        fallback;
}

static float4 m2sMeshShaderTransformPoint(M2SMeshShaderMatrix4 matrix, float3 position)
{
    return matrix.columns[0] * position.x +
        matrix.columns[1] * position.y +
        matrix.columns[2] * position.z +
        matrix.columns[3];
}

static float3 m2sMeshShaderTransformVector(M2SMeshShaderMatrix4 matrix, float3 value)
{
    return (matrix.columns[0] * value.x +
        matrix.columns[1] * value.y +
        matrix.columns[2] * value.z).xyz;
}

static float3 m2sMeshShaderReadFloat3(const device float* vertices, uint vertexIndex, uint offset)
{
    const uint base = vertexIndex * kM2SMeshShaderVertexFloatCount + offset;
    return float3(vertices[base], vertices[base + 1u], vertices[base + 2u]);
}

static float2 m2sMeshShaderReadFloat2(const device float* vertices, uint vertexIndex, uint offset)
{
    const uint base = vertexIndex * kM2SMeshShaderVertexFloatCount + offset;
    return float2(vertices[base], vertices[base + 1u]);
}

static float4 m2sMeshShaderReadFloat4(const device float* vertices, uint vertexIndex, uint offset)
{
    const uint base = vertexIndex * kM2SMeshShaderVertexFloatCount + offset;
    return float4(vertices[base], vertices[base + 1u], vertices[base + 2u], vertices[base + 3u]);
}

static float3 m2sMeshShaderOrthogonalVector(float3 normal)
{
    const float3 reference = abs(normal.y) < 0.999f ? float3(0.0f, 1.0f, 0.0f) : float3(1.0f, 0.0f, 0.0f);
    return m2sMeshShaderSafeNormalize(cross(reference, normal), float3(1.0f, 0.0f, 0.0f));
}

static float4 m2sMeshShaderSampleOr(
    texture2d<float> texture,
    sampler textureSampler,
    float2 uv,
    float4 fallback)
{
    if (texture.get_width() == 0u || texture.get_height() == 0u || !m2sMeshShaderFinite(uv)) {
        return fallback;
    }

    return m2sMeshShaderFiniteOr(texture.sample(textureSampler, uv), fallback);
}

static float m2sMeshShaderExponentialDepth(float viewDepth, float2 nearFar)
{
    const float2 resolvedNearFar = m2sMeshShaderFiniteOr(nearFar, float2(0.1f, 1000.0f));
    const float range = max(resolvedNearFar.y - resolvedNearFar.x, 1.0e-5f);
    const float normalizedDepth = clamp((viewDepth - resolvedNearFar.x) / range, 0.0f, 1.0f);
    return clamp(exp(-20.0f * normalizedDepth), 0.0f, 1.0f);
}

static float3 m2sMeshShaderFresnelSchlick(float cosTheta, float3 f0)
{
    return f0 + (1.0f - f0) * pow(clamp(1.0f - cosTheta, 0.0f, 1.0f), 5.0f);
}

static float m2sMeshShaderDistributionGGX(float3 normal, float3 halfVector, float roughness)
{
    const float resolvedRoughness = clamp(roughness, 0.04f, 1.0f);
    const float a = resolvedRoughness * resolvedRoughness;
    const float a2 = a * a;
    const float nDotH = saturate(dot(normal, halfVector));
    const float nDotH2 = nDotH * nDotH;
    const float denom = nDotH2 * (a2 - 1.0f) + 1.0f;
    return a2 / max(kM2SMeshShaderPi * denom * denom, 1.0e-5f);
}

static float m2sMeshShaderGeometrySchlickGGX(float nDotV, float roughness)
{
    const float r = roughness + 1.0f;
    const float k = (r * r) * 0.125f;
    return nDotV / max(nDotV * (1.0f - k) + k, 1.0e-5f);
}

static float m2sMeshShaderGeometrySmith(float3 normal, float3 viewDirection, float3 lightDirection, float roughness)
{
    const float nDotV = saturate(dot(normal, viewDirection));
    const float nDotL = saturate(dot(normal, lightDirection));
    return m2sMeshShaderGeometrySchlickGGX(nDotV, roughness) *
        m2sMeshShaderGeometrySchlickGGX(nDotL, roughness);
}

static float m2sMeshShaderShadowFactor(
    float3 worldPosition,
    constant M2SMeshShaderFrameUniforms& frame,
    texturecube<float> shadowDistanceTexture,
    sampler shadowSampler)
{
    if (frame.lightColorFlags.w < 1.5f) {
        return 0.0f;
    }

    const float3 sampleOffsetDirections[20] = {
        float3(1.0f, 1.0f, 1.0f),
        float3(1.0f, -1.0f, 1.0f),
        float3(-1.0f, -1.0f, 1.0f),
        float3(-1.0f, 1.0f, 1.0f),
        float3(1.0f, 1.0f, -1.0f),
        float3(1.0f, -1.0f, -1.0f),
        float3(-1.0f, -1.0f, -1.0f),
        float3(-1.0f, 1.0f, -1.0f),
        float3(1.0f, 1.0f, 0.0f),
        float3(1.0f, -1.0f, 0.0f),
        float3(-1.0f, -1.0f, 0.0f),
        float3(-1.0f, 1.0f, 0.0f),
        float3(1.0f, 0.0f, 1.0f),
        float3(-1.0f, 0.0f, 1.0f),
        float3(1.0f, 0.0f, -1.0f),
        float3(-1.0f, 0.0f, -1.0f),
        float3(0.0f, 1.0f, 1.0f),
        float3(0.0f, -1.0f, 1.0f),
        float3(0.0f, -1.0f, -1.0f),
        float3(0.0f, 1.0f, -1.0f),
    };

    const float farPlane = max(frame.clippingPlanes.y, frame.clippingPlanes.x + 1.0e-3f);
    const float3 lightVector = worldPosition - frame.lightPositionIntensity.xyz;
    const float currentDepth = length(lightVector);
    if (currentDepth <= 1.0e-4f || currentDepth >= farPlane) {
        return 0.0f;
    }

    const float3 sampleDirection = m2sMeshShaderSafeNormalize(lightVector, float3(0.0f, 0.0f, 1.0f));
    const float bias = 0.05f;
    const float diskRadius = 0.025f;
    float shadow = 0.0f;
    for (uint index = 0; index < 20u; ++index) {
        const float closestDepth =
            shadowDistanceTexture.sample(shadowSampler, sampleDirection + sampleOffsetDirections[index] * diskRadius).r *
            farPlane;
        shadow += currentDepth - bias > closestDepth ? 1.0f : 0.0f;
    }
    return shadow / 20.0f;
}

static float3 m2sMeshShaderNormalFromTexture(
    M2SMeshShaderVertexOut in,
    M2SMeshShaderMaterial material,
    texture2d<float> normalTexture,
    sampler textureSampler)
{
    const float3 vertexNormal = m2sMeshShaderSafeNormalize(in.normal, float3(0.0f, 1.0f, 0.0f));
    const float3 tangentCandidate = in.tangent.xyz - vertexNormal * dot(vertexNormal, in.tangent.xyz);
    const float3 tangent = m2sMeshShaderSafeNormalize(
        tangentCandidate,
        m2sMeshShaderOrthogonalVector(vertexNormal));
    const float tangentHandedness = m2sMeshShaderFinite(in.tangent.w) && in.tangent.w < 0.0f ? -1.0f : 1.0f;
    const float3 bitangent = m2sMeshShaderSafeNormalize(
        cross(vertexNormal, tangent) * tangentHandedness,
        m2sMeshShaderOrthogonalVector(vertexNormal));

    float3 normalSample = m2sMeshShaderSampleOr(
        normalTexture,
        textureSampler,
        in.uv,
        float4(0.5f, 0.5f, 1.0f, 1.0f)).xyz * 2.0f - 1.0f;
    normalSample.xy *= clamp(m2sMeshShaderFiniteOr(material.normalScale, 1.0f), 0.0f, 4.0f);
    normalSample = m2sMeshShaderSafeNormalize(normalSample, float3(0.0f, 0.0f, 1.0f));

    return m2sMeshShaderSafeNormalize(
        tangent * normalSample.x + bitangent * normalSample.y + vertexNormal * normalSample.z,
        vertexNormal);
}

static float3 m2sMeshShaderLitPreviewColor(
    float3 baseColor,
    float3 normal,
    float3 worldPosition,
    float3 viewDirection,
    float metallic,
    float roughness,
    float occlusion,
    float3 emissive,
    constant M2SMeshShaderFrameUniforms& frame,
    texturecube<float> shadowDistanceTexture,
    sampler shadowSampler)
{
    const float3 fallbackLightDirection = normalize(float3(0.35f, 0.8f, 0.45f));
    const float3 lightVector = frame.lightPositionIntensity.xyz - worldPosition;
    const float3 lightDirection = m2sMeshShaderSafeNormalize(lightVector, fallbackLightDirection);
    const float3 resolvedViewDirection = m2sMeshShaderSafeNormalize(viewDirection, float3(0.0f, 0.0f, 1.0f));
    const float3 halfVector = m2sMeshShaderSafeNormalize(lightDirection + resolvedViewDirection, lightDirection);
    if (frame.lightColorFlags.w <= 0.5f || frame.lightPositionIntensity.w <= 0.0f) {
        return baseColor * occlusion + emissive;
    }

    const float3 lightColor = max(frame.lightColorFlags.xyz, float3(0.0f));
    const float lightIntensity = max(frame.lightPositionIntensity.w, 0.0f);
    const float attenuation = 1.0f / max(dot(lightVector, lightVector), 1.0f);
    const float3 radiance = lightColor * lightIntensity * attenuation;
    const float3 f0 = mix(float3(0.04f), baseColor, metallic);
    const float3 fresnel = m2sMeshShaderFresnelSchlick(saturate(dot(halfVector, resolvedViewDirection)), f0);
    const float normalDistribution = m2sMeshShaderDistributionGGX(normal, halfVector, roughness);
    const float geometry = m2sMeshShaderGeometrySmith(normal, resolvedViewDirection, lightDirection, roughness);
    const float denominator = max(
        4.0f * saturate(dot(normal, resolvedViewDirection)) * saturate(dot(normal, lightDirection)),
        1.0e-4f);
    const float3 specular = (normalDistribution * geometry * fresnel) / denominator;
    const float3 diffuseWeight = (1.0f - fresnel) * (1.0f - metallic);
    const float nDotL = saturate(dot(normal, lightDirection));
    const float shadow = m2sMeshShaderShadowFactor(worldPosition, frame, shadowDistanceTexture, shadowSampler);
    const float3 direct =
        (diffuseWeight * baseColor / kM2SMeshShaderPi + specular) * radiance * nDotL * (1.0f - shadow);
    const float3 ambient = 0.3f * baseColor * occlusion;
    return ambient + direct + emissive;
}

static float3 m2sMeshShaderToneMappedColor(float3 color, constant M2SMeshShaderFrameUniforms& frame)
{
    if ((frame.flags & kM2SMeshShaderDebugFlagDisableToneMapping) != 0u) {
        return max(color, float3(0.0f));
    }

    const float exposure = max(frame.gaussianParams.y, 0.0f);
    const float gamma = max(frame.gaussianParams.z, 0.1f);
    const float3 exposed = 1.0f - exp(-max(color, float3(0.0f)) * exposure);
    return pow(saturate(exposed), float3(1.0f / gamma));
}

vertex M2SMeshShaderVertexOut meshVertex(
    uint vertexID [[vertex_id]],
    const device float* vertices [[buffer(0)]],
    constant M2SMeshShaderFrameUniforms& frame [[buffer(1)]])
{
    const float3 localPosition = m2sMeshShaderReadFloat3(vertices, vertexID, kM2SMeshShaderPositionOffset);
    const float3 localNormal = m2sMeshShaderReadFloat3(vertices, vertexID, kM2SMeshShaderNormalOffset);
    const float4 localTangent = m2sMeshShaderReadFloat4(vertices, vertexID, kM2SMeshShaderTangentOffset);
    const float2 uv = m2sMeshShaderReadFloat2(vertices, vertexID, kM2SMeshShaderUvOffset);
    const float2 normalizedUv = m2sMeshShaderReadFloat2(vertices, vertexID, kM2SMeshShaderNormalizedUvOffset);
    const float4 worldPosition = m2sMeshShaderTransformPoint(frame.modelMatrix, localPosition);
    const float4 viewPosition = m2sMeshShaderTransformPoint(frame.viewMatrix, worldPosition.xyz);

    M2SMeshShaderVertexOut out;
    out.position = m2sMeshShaderTransformPoint(frame.modelViewProjectionMatrix, localPosition);
    out.worldPosition = worldPosition.xyz;
    out.normal = m2sMeshShaderSafeNormalize(
        m2sMeshShaderTransformVector(frame.modelMatrix, localNormal),
        float3(0.0f, 1.0f, 0.0f));
    out.tangent = float4(
        m2sMeshShaderSafeNormalize(
            m2sMeshShaderTransformVector(frame.modelMatrix, localTangent.xyz),
            m2sMeshShaderOrthogonalVector(out.normal)),
        localTangent.w);
    out.uv = m2sMeshShaderFiniteOr(uv, float2(0.0f));
    out.normalizedUv = m2sMeshShaderFiniteOr(normalizedUv, out.uv);
    out.viewDepth = max(-viewPosition.z, 0.0f);
    out.clippingPlanes = frame.clippingPlanes.xy;
    out.viewDirection = m2sMeshShaderSafeNormalize(
        frame.cameraPosition.xyz - worldPosition.xyz,
        float3(0.0f, 0.0f, 1.0f));
    out.renderMode = frame.renderMode;
    return out;
}

fragment float4 meshFragment(
    M2SMeshShaderVertexOut in [[stage_in]],
    constant M2SMeshShaderMaterial* materials [[buffer(0)]],
    constant uint& materialIndex [[buffer(1)]],
    constant M2SMeshShaderFrameUniforms& frame [[buffer(2)]],
    texture2d<float> baseColorTexture [[texture(0)]],
    texture2d<float> metallicRoughnessTexture [[texture(1)]],
    texture2d<float> normalTexture [[texture(2)]],
    texture2d<float> occlusionTexture [[texture(3)]],
    texture2d<float> emissiveTexture [[texture(4)]],
    texturecube<float> shadowDistanceTexture [[texture(5)]],
    sampler materialTextureSampler [[sampler(0)]])
{
    const M2SMeshShaderMaterial material = materials[materialIndex];
    const float4 baseColorFactor = clamp(
        m2sMeshShaderFiniteOr(material.baseColorFactor, float4(1.0f)),
        float4(0.0f),
        float4(1.0f));
    const float4 baseColorSample = m2sMeshShaderSampleOr(
        baseColorTexture,
        materialTextureSampler,
        in.uv,
        float4(1.0f));
    const float4 baseColor = clamp(baseColorFactor * baseColorSample, float4(0.0f), float4(1.0f));

    if (baseColor.a <= kM2SMeshShaderAlphaDiscardThreshold) {
        discard_fragment();
    }

    const float4 metallicRoughnessSample = m2sMeshShaderSampleOr(
        metallicRoughnessTexture,
        materialTextureSampler,
        in.uv,
        float4(1.0f));
    const float metallic = clamp(
        m2sMeshShaderFiniteOr(material.metallicFactor, 1.0f) * metallicRoughnessSample.b,
        0.0f,
        1.0f);
    const float roughness = clamp(
        m2sMeshShaderFiniteOr(material.roughnessFactor, 1.0f) * metallicRoughnessSample.g,
        0.04f,
        1.0f);
    const float occlusionStrength = clamp(m2sMeshShaderFiniteOr(material.occlusionStrength, 1.0f), 0.0f, 1.0f);
    const float occlusionSample = clamp(
        m2sMeshShaderSampleOr(occlusionTexture, materialTextureSampler, in.uv, float4(1.0f)).r,
        0.0f,
        1.0f);
    const float occlusion = mix(1.0f, occlusionSample, occlusionStrength);
    const float3 emissiveFactor = max(
        m2sMeshShaderFiniteOr(material.emissiveFactor.rgb, float3(0.0f)),
        float3(0.0f));
    const float3 emissive = emissiveFactor * max(
        m2sMeshShaderSampleOr(emissiveTexture, materialTextureSampler, in.uv, float4(0.0f)).rgb,
        float3(0.0f));
    const float3 normal = m2sMeshShaderNormalFromTexture(
        in,
        material,
        normalTexture,
        materialTextureSampler);

    if (in.renderMode == kM2SMeshShaderRenderModeDepth) {
        const float depth = m2sMeshShaderExponentialDepth(in.viewDepth, in.clippingPlanes);
        return float4(float3(depth), baseColor.a);
    }

    if (in.renderMode == kM2SMeshShaderRenderModeNormal) {
        return float4(normal * 0.5f + 0.5f, baseColor.a);
    }

    if (in.renderMode == kM2SMeshShaderRenderModeGeometryColor) {
        const float2 geometryUv = fract(abs(m2sMeshShaderFiniteOr(in.normalizedUv, in.uv)));
        return float4(float3(geometryUv, 0.5f), baseColor.a);
    }

    if (in.renderMode == kM2SMeshShaderRenderModeDensity) {
        return float4(1.0f, 0.45f, 0.08f, baseColor.a);
    }

    if (in.renderMode == kM2SMeshShaderRenderModePbr) {
        return float4(float3(metallic, roughness, occlusion), baseColor.a);
    }

    if (in.renderMode == kM2SMeshShaderRenderModeLitPreview) {
        const float3 litColor = m2sMeshShaderLitPreviewColor(
            baseColor.rgb,
            normal,
            in.worldPosition,
            in.viewDirection,
            metallic,
            roughness,
            occlusion,
            emissive,
            frame,
            shadowDistanceTexture,
            materialTextureSampler);
        return float4(m2sMeshShaderToneMappedColor(litColor, frame), baseColor.a);
    }

    return float4(m2sMeshShaderToneMappedColor(baseColor.rgb + emissive, frame), baseColor.a);
}
