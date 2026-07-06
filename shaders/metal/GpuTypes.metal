#include <metal_stdlib>

using namespace metal;

// Mesh2Splat shared GPU ABI definitions.
//
// Keep symbols prefixed with M2S while runtime shader fallback still concatenates
// all bundled .metal files. The active pass shaders currently carry local struct
// names, so these shared definitions are staged here without colliding with them.

constant constexpr uint kM2SDefaultMaxGaussianCount = 7000000u;
constant constexpr float kM2SSphericalHarmonicC0 = 0.28209479177387814f;

constant constexpr uint kM2SMeshVertexFloatCount = 17u;
constant constexpr uint kM2SMeshVertexByteSize = 68u;
constant constexpr uint kM2SMeshVertexPositionOffset = 0u;
constant constexpr uint kM2SMeshVertexNormalOffset = 3u;
constant constexpr uint kM2SMeshVertexTangentOffset = 6u;
constant constexpr uint kM2SMeshVertexUvOffset = 10u;
constant constexpr uint kM2SMeshVertexNormalizedUvOffset = 12u;
constant constexpr uint kM2SMeshVertexScaleOffset = 14u;

constant constexpr uint kM2SGaussianFloat4SlotCount = 6u;
constant constexpr uint kM2SGaussianRecordByteSize = 96u;
constant constexpr uint kM2SGaussianPositionSlot = 0u;
constant constexpr uint kM2SGaussianColorSlot = 1u;
constant constexpr uint kM2SGaussianScaleSlot = 2u;
constant constexpr uint kM2SGaussianNormalSlot = 3u;
constant constexpr uint kM2SGaussianRotationSlot = 4u;
constant constexpr uint kM2SGaussianPbrSlot = 5u;

constant constexpr uint kM2SMatrix4ByteSize = 64u;
constant constexpr uint kM2SFrameUniformsByteSize = 352u;
constant constexpr uint kM2SMeshMaterialByteSize = 48u;
constant constexpr uint kM2SMeshDrawRangeByteSize = 16u;
constant constexpr uint kM2SMeshConversionParamsByteSize = 32u;
constant constexpr uint kM2SGaussianSortParamsByteSize = 16u;
constant constexpr uint kM2SRadixSortParamsByteSize = 16u;

constant constexpr uint kM2SRadixBinCount = 16u;
constant constexpr uint kM2SRadixPassCount = 8u;
constant constexpr uint kM2SRadixSortThreadCount = 256u;

constant constexpr uint kM2SRenderModeColor = 0u;
constant constexpr uint kM2SRenderModeDepth = 1u;
constant constexpr uint kM2SRenderModeNormal = 2u;
constant constexpr uint kM2SRenderModeGeometryColor = 3u;
constant constexpr uint kM2SRenderModeDensity = 4u;
constant constexpr uint kM2SRenderModePbr = 5u;
constant constexpr uint kM2SRenderModeLitPreview = 6u;

constant constexpr uint kM2SMeshVertexVerticesBufferIndex = 0u;
constant constexpr uint kM2SMeshVertexFrameBufferIndex = 1u;

constant constexpr uint kM2SMeshFragmentMaterialsBufferIndex = 0u;
constant constexpr uint kM2SMeshFragmentMaterialIndexBufferIndex = 1u;

constant constexpr uint kM2SConversionVerticesBufferIndex = 0u;
constant constexpr uint kM2SConversionMaterialsBufferIndex = 1u;
constant constexpr uint kM2SConversionGaussiansBufferIndex = 2u;
constant constexpr uint kM2SConversionParamsBufferIndex = 3u;
constant constexpr uint kM2SConversionCounterBufferIndex = 4u;

constant constexpr uint kM2SGaussianVertexGaussiansBufferIndex = 0u;
constant constexpr uint kM2SGaussianVertexFrameBufferIndex = 1u;
constant constexpr uint kM2SGaussianVertexIndicesBufferIndex = 2u;
constant constexpr uint kM2SGaussianFragmentFrameBufferIndex = 0u;

constant constexpr uint kM2SSortDepthGaussiansBufferIndex = 0u;
constant constexpr uint kM2SSortDepthFrameBufferIndex = 1u;
constant constexpr uint kM2SSortDepthKeysBufferIndex = 2u;
constant constexpr uint kM2SSortDepthIndicesBufferIndex = 3u;
constant constexpr uint kM2SSortDepthParamsBufferIndex = 4u;

constant constexpr uint kM2SSortCountKeysBufferIndex = 0u;
constant constexpr uint kM2SSortCountBlockCountsBufferIndex = 1u;
constant constexpr uint kM2SSortCountGlobalOffsetsBufferIndex = 2u;
constant constexpr uint kM2SSortCountParamsBufferIndex = 3u;

constant constexpr uint kM2SSortPrefixBlockCountsBufferIndex = 0u;
constant constexpr uint kM2SSortPrefixGlobalOffsetsBufferIndex = 1u;
constant constexpr uint kM2SSortPrefixParamsBufferIndex = 2u;

constant constexpr uint kM2SSortReorderSrcKeysBufferIndex = 0u;
constant constexpr uint kM2SSortReorderSrcIndicesBufferIndex = 1u;
constant constexpr uint kM2SSortReorderDstKeysBufferIndex = 2u;
constant constexpr uint kM2SSortReorderDstIndicesBufferIndex = 3u;
constant constexpr uint kM2SSortReorderBlockOffsetsBufferIndex = 4u;
constant constexpr uint kM2SSortReorderGlobalOffsetsBufferIndex = 5u;
constant constexpr uint kM2SSortReorderParamsBufferIndex = 6u;

constant constexpr uint kM2SBaseColorTextureIndex = 0u;
constant constexpr uint kM2SMetallicRoughnessTextureIndex = 1u;
constant constexpr uint kM2SNormalTextureIndex = 2u;
constant constexpr uint kM2SOcclusionTextureIndex = 3u;
constant constexpr uint kM2SEmissiveTextureIndex = 4u;
constant constexpr uint kM2SMaterialTextureSamplerIndex = 0u;

constant constexpr uint kM2SMetallicRoughnessRoughnessChannel = 1u;
constant constexpr uint kM2SMetallicRoughnessMetallicChannel = 2u;

struct M2SMatrix4 {
    float4 columns[4];
};

struct M2SFrameUniforms {
    M2SMatrix4 modelMatrix;
    M2SMatrix4 viewMatrix;
    M2SMatrix4 projectionMatrix;
    M2SMatrix4 modelViewProjectionMatrix;
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

struct M2SGaussianRecord {
    float4 position;
    float4 color;
    float4 scale;
    float4 normal;
    float4 rotation;
    float4 pbr;
};

struct M2SMeshVertexRecord {
    float values[17];
};

struct M2SMeshMaterialRecord {
    float4 baseColorFactor;
    float4 emissiveFactor;
    float metallicFactor;
    float roughnessFactor;
    float occlusionStrength;
    float normalScale;
};

struct M2SMeshDrawRangeRecord {
    uint vertexOffset;
    uint vertexCount;
    uint materialIndex;
    float surfaceArea;
};

struct M2SMeshConversionParams {
    uint vertexOffset;
    uint triangleCount;
    uint materialIndex;
    uint maxGaussianCount;
    float gaussianScale;
    float normalScale;
    float areaSampleDensity;
    uint maxSamplesPerTriangle;
};

struct M2SGaussianSortParams {
    uint gaussianCount;
    uint keyCapacity;
    uint indexCapacity;
    uint reserved;
};

struct M2SRadixSortParams {
    uint itemCount;
    uint blockCount;
    uint radixShift;
    uint outputCapacity;
};

static_assert(sizeof(M2SMatrix4) == kM2SMatrix4ByteSize, "M2SMatrix4 must remain four float4 columns.");
static_assert(sizeof(M2SFrameUniforms) == kM2SFrameUniformsByteSize, "M2SFrameUniforms must match C++ FrameUniforms.");
static_assert(sizeof(M2SGaussianRecord) == kM2SGaussianRecordByteSize, "M2SGaussianRecord must remain six float4 slots.");
static_assert(sizeof(M2SMeshVertexRecord) == kM2SMeshVertexByteSize, "M2SMeshVertexRecord must remain 17 packed floats.");
static_assert(sizeof(M2SMeshMaterialRecord) == kM2SMeshMaterialByteSize, "M2SMeshMaterialRecord must match MetalMeshMaterial.");
static_assert(sizeof(M2SMeshDrawRangeRecord) == kM2SMeshDrawRangeByteSize, "M2SMeshDrawRangeRecord must stay 16 bytes.");
static_assert(sizeof(M2SMeshConversionParams) == kM2SMeshConversionParamsByteSize, "M2SMeshConversionParams must stay 32 bytes.");
static_assert(sizeof(M2SGaussianSortParams) == kM2SGaussianSortParamsByteSize, "M2SGaussianSortParams must stay 16 bytes.");
static_assert(sizeof(M2SRadixSortParams) == kM2SRadixSortParamsByteSize, "M2SRadixSortParams must stay 16 bytes.");

static float4 m2sTransformPoint(M2SMatrix4 matrix, float3 position)
{
    return matrix.columns[0] * position.x +
        matrix.columns[1] * position.y +
        matrix.columns[2] * position.z +
        matrix.columns[3];
}

static float3 m2sTransformVector(M2SMatrix4 matrix, float3 vector)
{
    return (matrix.columns[0] * vector.x +
        matrix.columns[1] * vector.y +
        matrix.columns[2] * vector.z).xyz;
}

static float2 m2sClipToNdc(float4 clipPosition)
{
    const float safeW = abs(clipPosition.w) > 1.0e-5 ? clipPosition.w : copysign(1.0e-5, clipPosition.w);
    return clipPosition.xy / safeW;
}

static float3 m2sSafeNormalize(float3 value, float3 fallback)
{
    const float lengthSquared = dot(value, value);
    return lengthSquared > 1.0e-12 ? value * rsqrt(lengthSquared) : fallback;
}

static float3 m2sMeshVertexFloat3(const device float* vertices, uint vertexIndex, uint componentOffset)
{
    const uint base = vertexIndex * kM2SMeshVertexFloatCount + componentOffset;
    return float3(vertices[base], vertices[base + 1u], vertices[base + 2u]);
}

static float2 m2sMeshVertexFloat2(const device float* vertices, uint vertexIndex, uint componentOffset)
{
    const uint base = vertexIndex * kM2SMeshVertexFloatCount + componentOffset;
    return float2(vertices[base], vertices[base + 1u]);
}

static float4 m2sMeshVertexFloat4(const device float* vertices, uint vertexIndex, uint componentOffset)
{
    const uint base = vertexIndex * kM2SMeshVertexFloatCount + componentOffset;
    return float4(vertices[base], vertices[base + 1u], vertices[base + 2u], vertices[base + 3u]);
}

static float3 m2sMeshVertexPosition(const device float* vertices, uint vertexIndex)
{
    return m2sMeshVertexFloat3(vertices, vertexIndex, kM2SMeshVertexPositionOffset);
}

static float3 m2sMeshVertexNormal(const device float* vertices, uint vertexIndex)
{
    return m2sMeshVertexFloat3(vertices, vertexIndex, kM2SMeshVertexNormalOffset);
}

static float4 m2sMeshVertexTangent(const device float* vertices, uint vertexIndex)
{
    return m2sMeshVertexFloat4(vertices, vertexIndex, kM2SMeshVertexTangentOffset);
}

static float2 m2sMeshVertexUv(const device float* vertices, uint vertexIndex)
{
    return m2sMeshVertexFloat2(vertices, vertexIndex, kM2SMeshVertexUvOffset);
}

static float2 m2sMeshVertexNormalizedUv(const device float* vertices, uint vertexIndex)
{
    return m2sMeshVertexFloat2(vertices, vertexIndex, kM2SMeshVertexNormalizedUvOffset);
}

static float3 m2sMeshVertexScale(const device float* vertices, uint vertexIndex)
{
    return m2sMeshVertexFloat3(vertices, vertexIndex, kM2SMeshVertexScaleOffset);
}

static float3 m2sRotateByQuaternion(float4 quaternion, float3 value)
{
    const float4 q = normalize(quaternion);
    const float3 vector = q.yzw;
    const float3 t = 2.0 * cross(vector, value);
    return value + q.x * t + cross(vector, t);
}

static uint m2sNormalizedSamplesPerTriangle(uint samplesPerTriangle)
{
    if (samplesPerTriangle <= 1u) {
        return 1u;
    }
    if (samplesPerTriangle <= 4u) {
        return 4u;
    }
    return 9u;
}

static float m2sGaussianColorToSh0(float linearColor)
{
    return (linearColor - 0.5f) / kM2SSphericalHarmonicC0;
}

static float m2sGaussianAlphaToOpacityLogit(float alpha)
{
    const float clampedAlpha = clamp(alpha, 1.0e-6f, 1.0f - 1.0e-6f);
    return log(clampedAlpha / (1.0f - clampedAlpha));
}

static float m2sGaussianPositiveScaleToLog(float scale, float multiplier)
{
    constexpr float kMinimumScale = 1.0e-20f;
    return log(max(scale * multiplier, kMinimumScale));
}
