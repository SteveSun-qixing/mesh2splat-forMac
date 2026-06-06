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
    float areaSampleDensity;
    uint maxSamplesPerTriangle;
};

constexpr uint kConversionMeshVertexFloatStride = 17u;
constexpr float kConversionMinimumLengthSquared = 1.0e-12;
constexpr float kConversionMinimumGaussianAxisScale = 1.0e-7;
constexpr float kConversionMaximumGaussianAxisScale = 1.0e7;
constexpr float kConversionCapacityCeilBias = 1.0e-5;

static bool conversionFinite(float value)
{
    return isfinite(value);
}

static bool conversionFinite(float2 value)
{
    return all(isfinite(value));
}

static bool conversionFinite(float3 value)
{
    return all(isfinite(value));
}

static bool conversionFinite(float4 value)
{
    return all(isfinite(value));
}

static float conversionFiniteOr(float value, float fallback)
{
    return conversionFinite(value) ? value : fallback;
}

static float2 conversionFiniteOr(float2 value, float2 fallback)
{
    return conversionFinite(value) ? value : fallback;
}

static float3 conversionFiniteOr(float3 value, float3 fallback)
{
    return conversionFinite(value) ? value : fallback;
}

static float4 conversionFiniteOr(float4 value, float4 fallback)
{
    return conversionFinite(value) ? value : fallback;
}

static float3 conversionSafeNormalize(float3 value, float3 fallback)
{
    const float lengthSquared = dot(value, value);
    return conversionFinite(lengthSquared) && lengthSquared > kConversionMinimumLengthSquared ?
        value * rsqrt(lengthSquared) :
        fallback;
}

static float4 conversionSafeNormalize(float4 value, float4 fallback)
{
    const float lengthSquared = dot(value, value);
    return conversionFinite(lengthSquared) && lengthSquared > kConversionMinimumLengthSquared ?
        value * rsqrt(lengthSquared) :
        fallback;
}

static float conversionPositiveOr(float value, float fallback)
{
    return conversionFinite(value) && value > 0.0 ? value : fallback;
}

static float conversionUnitOr(float value, float fallback)
{
    return clamp(conversionFiniteOr(value, fallback), 0.0, 1.0);
}

static float conversionAxisScaleOr(float value, float fallback)
{
    return clamp(
        conversionPositiveOr(value, fallback),
        kConversionMinimumGaussianAxisScale,
        kConversionMaximumGaussianAxisScale);
}

static float3 conversionOrthogonalVector(float3 normal)
{
    const float3 normalizedNormal = conversionSafeNormalize(normal, float3(0.0, 1.0, 0.0));
    const float3 reference = abs(normalizedNormal.y) < 0.999 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
    return conversionSafeNormalize(cross(reference, normalizedNormal), float3(1.0, 0.0, 0.0));
}

static uint conversionNormalizedSamplesPerTriangle(uint samplesPerTriangle)
{
    if (samplesPerTriangle <= 1u) {
        return 1u;
    }

    if (samplesPerTriangle <= 4u) {
        return 4u;
    }

    return 9u;
}

static float4 conversionQuaternionFromBasis(float3 xAxis, float3 yAxis, float3 zAxis)
{
    const float trace = xAxis.x + yAxis.y + zAxis.z;
    float4 q;

    if (trace > 0.0) {
        const float scale = max(sqrt(max(trace + 1.0, 0.0)) * 2.0, 1.0e-8);
        q = float4(
            0.25 * scale,
            (yAxis.z - zAxis.y) / scale,
            (zAxis.x - xAxis.z) / scale,
            (xAxis.y - yAxis.x) / scale);
    } else if (xAxis.x > yAxis.y && xAxis.x > zAxis.z) {
        const float scale = max(sqrt(max(1.0 + xAxis.x - yAxis.y - zAxis.z, 0.0)) * 2.0, 1.0e-8);
        q = float4(
            (yAxis.z - zAxis.y) / scale,
            0.25 * scale,
            (yAxis.x + xAxis.y) / scale,
            (zAxis.x + xAxis.z) / scale);
    } else if (yAxis.y > zAxis.z) {
        const float scale = max(sqrt(max(1.0 + yAxis.y - xAxis.x - zAxis.z, 0.0)) * 2.0, 1.0e-8);
        q = float4(
            (zAxis.x - xAxis.z) / scale,
            (yAxis.x + xAxis.y) / scale,
            0.25 * scale,
            (zAxis.y + yAxis.z) / scale);
    } else {
        const float scale = max(sqrt(max(1.0 + zAxis.z - xAxis.x - yAxis.y, 0.0)) * 2.0, 1.0e-8);
        q = float4(
            (xAxis.y - yAxis.x) / scale,
            (zAxis.x + xAxis.z) / scale,
            (zAxis.y + yAxis.z) / scale,
            0.25 * scale);
    }

    return conversionSafeNormalize(q, float4(1.0, 0.0, 0.0, 0.0));
}

static float3 conversionBarycentricSample(uint sampleID, uint samplesPerTriangle)
{
    if (samplesPerTriangle <= 1) {
        return float3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0);
    }

    if (samplesPerTriangle <= 4) {
        const float3 samples[4] = {
            float3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0),
            float3(0.6, 0.2, 0.2),
            float3(0.2, 0.6, 0.2),
            float3(0.2, 0.2, 0.6),
        };
        return samples[sampleID % 4];
    }

    const float3 samples[9] = {
        float3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0),
        float3(0.75, 0.125, 0.125),
        float3(0.125, 0.75, 0.125),
        float3(0.125, 0.125, 0.75),
        float3(0.5, 0.25, 0.25),
        float3(0.25, 0.5, 0.25),
        float3(0.25, 0.25, 0.5),
        float3(0.45, 0.45, 0.1),
        float3(0.45, 0.1, 0.45),
    };
    return samples[sampleID % 9];
}

static uint conversionActiveSamplesForTriangle(float triangleArea, constant MeshConversionParams& params)
{
    const uint maxSamplesPerTriangle = conversionNormalizedSamplesPerTriangle(params.maxSamplesPerTriangle);
    if (maxSamplesPerTriangle <= 1u ||
        params.areaSampleDensity <= 0.0 ||
        triangleArea <= kConversionMinimumLengthSquared) {
        return maxSamplesPerTriangle;
    }

    const float scaledSamples = triangleArea * params.areaSampleDensity + kConversionCapacityCeilBias;
    if (!conversionFinite(scaledSamples) || scaledSamples >= float(maxSamplesPerTriangle)) {
        return maxSamplesPerTriangle;
    }

    const uint areaSamples = max(uint(ceil(max(scaledSamples, 0.0))), 1u);
    return min(areaSamples, maxSamplesPerTriangle);
}

static float3 conversionReadVertexFloat3(const device float* vertices, uint base, uint offset)
{
    return float3(vertices[base + offset + 0u], vertices[base + offset + 1u], vertices[base + offset + 2u]);
}

static float2 conversionReadVertexFloat2(const device float* vertices, uint base, uint offset)
{
    return float2(vertices[base + offset + 0u], vertices[base + offset + 1u]);
}

static float2 conversionTriangleAtlasScale(
    float3 edge0,
    float3 edge1,
    float triangleArea,
    float2 uv0,
    float2 uv1,
    float2 uv2,
    uint activeSamples,
    float2 fallbackScale)
{
    if (!conversionFinite(uv0) ||
        !conversionFinite(uv1) ||
        !conversionFinite(uv2) ||
        triangleArea <= kConversionMinimumLengthSquared) {
        return fallbackScale;
    }

    const float2 uvEdge0 = uv1 - uv0;
    const float2 uvEdge1 = uv2 - uv0;
    const float determinant = uvEdge0.x * uvEdge1.y - uvEdge0.y * uvEdge1.x;
    if (!conversionFinite(determinant) || abs(determinant) <= 1.0e-8) {
        return fallbackScale;
    }

    const float inverseDeterminant = 1.0 / determinant;
    const float3 dPdu = (edge0 * uvEdge1.y - edge1 * uvEdge0.y) * inverseDeterminant;
    const float3 dPdv = (edge1 * uvEdge0.x - edge0 * uvEdge1.x) * inverseDeterminant;
    const float atlasSampleRadius = sqrt(max(abs(determinant) * 0.5 / float(max(activeSamples, 1u)), 1.0e-12));
    const float2 axisScale = float2(length(dPdu), length(dPdv)) * atlasSampleRadius;
    return conversionFinite(axisScale) && axisScale.x > 0.0 && axisScale.y > 0.0 ? axisScale : fallbackScale;
}

static bool conversionReserveGaussianIndex(device atomic_uint* counter, uint capacity, thread uint& outputIndex)
{
    outputIndex = 0u;
    if (capacity == 0u) {
        return false;
    }

    uint observed = atomic_load_explicit(counter, memory_order_relaxed);
    while (observed < capacity) {
        if (atomic_compare_exchange_weak_explicit(
                counter,
                &observed,
                observed + 1u,
                memory_order_relaxed,
                memory_order_relaxed)) {
            outputIndex = observed;
            return true;
        }
    }

    return false;
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
    texture2d<float> normalTexture [[texture(2)]],
    texture2d<float> occlusionTexture [[texture(3)]],
    texture2d<float> emissiveTexture [[texture(4)]],
    sampler textureSampler [[sampler(0)]])
{
    const uint maxSamplesPerTriangle = conversionNormalizedSamplesPerTriangle(params.maxSamplesPerTriangle);
    const uint triangleID = threadID / maxSamplesPerTriangle;
    const uint sampleID = threadID - triangleID * maxSamplesPerTriangle;
    if (params.triangleCount == 0u || triangleID >= params.triangleCount) {
        return;
    }

    if (triangleID > (0xffffffffu - params.vertexOffset) / 3u) {
        return;
    }

    const uint firstVertexIndex = params.vertexOffset + triangleID * 3;
    if (firstVertexIndex > (0xffffffffu - (kConversionMeshVertexFloatStride - 1u)) / kConversionMeshVertexFloatStride - 2u) {
        return;
    }

    const uint base0 = firstVertexIndex * kConversionMeshVertexFloatStride;
    const uint base1 = (firstVertexIndex + 1u) * kConversionMeshVertexFloatStride;
    const uint base2 = (firstVertexIndex + 2u) * kConversionMeshVertexFloatStride;
    const float3 p0 = conversionReadVertexFloat3(vertices, base0, 0u);
    const float3 p1 = conversionReadVertexFloat3(vertices, base1, 0u);
    const float3 p2 = conversionReadVertexFloat3(vertices, base2, 0u);
    if (!conversionFinite(p0) || !conversionFinite(p1) || !conversionFinite(p2)) {
        return;
    }

    const float3 edge0 = p1 - p0;
    const float3 edge1 = p2 - p0;
    const float3 edge2 = p2 - p1;
    const float3 faceCross = cross(edge0, edge1);
    const float triangleArea = conversionFinite(faceCross) ? length(faceCross) * 0.5 : 0.0;
    const uint activeSamples = conversionActiveSamplesForTriangle(triangleArea, params);
    if (sampleID >= activeSamples) {
        return;
    }

    const float edge0Length = conversionFinite(edge0) ? length(edge0) : 0.0;
    const float edge1Length = conversionFinite(edge1) ? length(edge1) : 0.0;
    const float edge2Length = conversionFinite(edge2) ? length(edge2) : 0.0;
    float3 majorEdge = edge0;
    float majorEdgeLength = edge0Length;
    if (edge1Length > majorEdgeLength) {
        majorEdge = edge1;
        majorEdgeLength = edge1Length;
    }
    if (edge2Length > majorEdgeLength) {
        majorEdge = edge2;
        majorEdgeLength = edge2Length;
    }

    const float3 faceNormal = conversionSafeNormalize(faceCross, float3(0.0, 1.0, 0.0));
    const float3 xAxisFallback = conversionOrthogonalVector(faceNormal);
    const float3 xAxis = conversionSafeNormalize(majorEdge, xAxisFallback);
    const float3 yAxis = conversionSafeNormalize(
        cross(faceNormal, xAxis),
        conversionSafeNormalize(cross(faceNormal, xAxisFallback), float3(0.0, 0.0, 1.0)));
    const float4 rotation = conversionQuaternionFromBasis(xAxis, yAxis, faceNormal);
    const float gaussianScale = conversionPositiveOr(params.gaussianScale, 0.22);
    const float sampleScale = gaussianScale * rsqrt(float(max(activeSamples, 1u)));
    const float fallbackX = conversionAxisScaleOr(
        max(majorEdgeLength, edge0Length) * sampleScale,
        kConversionMinimumGaussianAxisScale);
    const float fallbackY = conversionAxisScaleOr(
        max(min(edge0Length, edge1Length), triangleArea / max(majorEdgeLength, kConversionMinimumGaussianAxisScale)) *
            sampleScale,
        fallbackX);

    const float3 barycentric = conversionBarycentricSample(sampleID, activeSamples);
    const float3 position = conversionFiniteOr(
        p0 * barycentric.x + p1 * barycentric.y + p2 * barycentric.z,
        (p0 + p1 + p2) / 3.0);
    const float3 n0 = conversionSafeNormalize(conversionReadVertexFloat3(vertices, base0, 3u), faceNormal);
    const float3 n1 = conversionSafeNormalize(conversionReadVertexFloat3(vertices, base1, 3u), faceNormal);
    const float3 n2 = conversionSafeNormalize(conversionReadVertexFloat3(vertices, base2, 3u), faceNormal);
    const float3 vertexNormal = conversionSafeNormalize(n0 * barycentric.x + n1 * barycentric.y + n2 * barycentric.z, faceNormal);

    uint outputIndex = 0u;
    if (!conversionReserveGaussianIndex(gaussianCounter, params.maxGaussianCount, outputIndex)) {
        return;
    }

    const MeshMaterial material = materials[params.materialIndex];
    const float4 baseColorFactor = conversionFiniteOr(material.baseColorFactor, float4(1.0));
    const float4 emissiveFactor = conversionFiniteOr(material.emissiveFactor, float4(0.0));
    const float metallicFactor = conversionUnitOr(material.metallicFactor, 1.0);
    const float roughnessFactor = conversionPositiveOr(material.roughnessFactor, 1.0);
    const float occlusionStrength = conversionUnitOr(material.occlusionStrength, 1.0);
    const float normalScale =
        conversionPositiveOr(params.normalScale, 1.0) * conversionPositiveOr(material.normalScale, 1.0);

    const float2 uv0 = conversionFiniteOr(conversionReadVertexFloat2(vertices, base0, 10u), float2(0.0));
    const float2 uv1 = conversionFiniteOr(conversionReadVertexFloat2(vertices, base1, 10u), uv0);
    const float2 uv2 = conversionFiniteOr(conversionReadVertexFloat2(vertices, base2, 10u), uv0);
    const float2 uv = conversionFiniteOr(uv0 * barycentric.x + uv1 * barycentric.y + uv2 * barycentric.z, float2(0.0));
    const float2 atlasUv0 = conversionFiniteOr(conversionReadVertexFloat2(vertices, base0, 12u), uv0);
    const float2 atlasUv1 = conversionFiniteOr(conversionReadVertexFloat2(vertices, base1, 12u), uv1);
    const float2 atlasUv2 = conversionFiniteOr(conversionReadVertexFloat2(vertices, base2, 12u), uv2);
    const float2 atlasScale = conversionTriangleAtlasScale(
        edge0,
        edge1,
        triangleArea,
        atlasUv0,
        atlasUv1,
        atlasUv2,
        activeSamples,
        float2(fallbackX, fallbackY) / gaussianScale) * gaussianScale;
    const float3 vertexScale = conversionFiniteOr(
        conversionReadVertexFloat3(vertices, base0, 14u) * barycentric.x +
            conversionReadVertexFloat3(vertices, base1, 14u) * barycentric.y +
            conversionReadVertexFloat3(vertices, base2, 14u) * barycentric.z,
        float3(1.0));
    const float scaleX = conversionAxisScaleOr(atlasScale.x * conversionPositiveOr(abs(vertexScale.x), 1.0), fallbackX);
    const float scaleY = conversionAxisScaleOr(atlasScale.y * conversionPositiveOr(abs(vertexScale.y), 1.0), fallbackY);
    const bool hasExplicitZScale = conversionFinite(vertexScale.z) &&
        vertexScale.z > kConversionMinimumGaussianAxisScale &&
        abs(vertexScale.z - 1.0) > 1.0e-4;
    const float scaleZ = hasExplicitZScale ?
        conversionAxisScaleOr(abs(vertexScale.z) * gaussianScale, kConversionMinimumGaussianAxisScale) :
        kConversionMinimumGaussianAxisScale;

    const float4 baseColorSample = conversionFiniteOr(baseColorTexture.sample(textureSampler, uv), float4(1.0));
    const float4 metallicRoughnessSample =
        conversionFiniteOr(metallicRoughnessTexture.sample(textureSampler, uv), float4(1.0, 0.5, 0.1, 1.0));
    const float occlusionSample = conversionUnitOr(occlusionTexture.sample(textureSampler, uv).r, 1.0);
    const float3 emissiveSample =
        max(conversionFiniteOr(emissiveTexture.sample(textureSampler, uv).rgb, float3(1.0)), float3(0.0));
    const float4 baseColor = float4(
        max(baseColorFactor.rgb, float3(0.0)) * max(baseColorSample.rgb, float3(0.0)),
        conversionUnitOr(baseColorFactor.a, 1.0) * conversionUnitOr(baseColorSample.a, 1.0));
    const float occlusion = mix(1.0, occlusionSample, occlusionStrength);
    const float3 emissive = max(emissiveFactor.rgb, float3(0.0)) * emissiveSample;
    const float emissiveStrength = max(max(emissive.r, emissive.g), emissive.b);

    const float3 t0 = conversionReadVertexFloat3(vertices, base0, 6u);
    const float3 t1 = conversionReadVertexFloat3(vertices, base1, 6u);
    const float3 t2 = conversionReadVertexFloat3(vertices, base2, 6u);
    const float3 tangent = conversionFiniteOr(t0 * barycentric.x + t1 * barycentric.y + t2 * barycentric.z, xAxis);
    const float tangentW =
        vertices[base0 + 9] * barycentric.x +
        vertices[base1 + 9] * barycentric.y +
        vertices[base2 + 9] * barycentric.z;
    const float tangentSign = conversionFinite(tangentW) && tangentW < 0.0 ? -1.0 : 1.0;
    const float3 tangentBasis = conversionSafeNormalize(
        tangent - vertexNormal * dot(vertexNormal, tangent),
        conversionOrthogonalVector(vertexNormal));
    const float3 bitangentBasis = conversionSafeNormalize(
        cross(vertexNormal, tangentBasis) * tangentSign,
        cross(vertexNormal, tangentBasis));
    float3 normalSample = conversionFiniteOr(normalTexture.sample(textureSampler, uv).xyz, float3(0.5, 0.5, 1.0)) *
        2.0 - 1.0;
    normalSample.xy *= normalScale;
    const float3 normal = conversionSafeNormalize(
        tangentBasis * normalSample.x + bitangentBasis * normalSample.y + vertexNormal * normalSample.z,
        faceNormal);

    GaussianRecord gaussian;
    gaussian.position = float4(position, 1.0);
    gaussian.color = float4(max(baseColor.rgb + emissive, float3(0.0)), baseColor.a);
    gaussian.scale = float4(scaleX, scaleY, scaleZ, 0.0);
    gaussian.normal = float4(normal, 0.0);
    gaussian.rotation = rotation;
    gaussian.pbr = float4(
        conversionUnitOr(metallicFactor * conversionUnitOr(metallicRoughnessSample.b, 1.0), 0.1),
        clamp(roughnessFactor * conversionUnitOr(metallicRoughnessSample.g, 1.0), 0.04, 1.0),
        occlusion,
        max(emissiveStrength, 0.0));
    gaussians[outputIndex] = gaussian;
}
