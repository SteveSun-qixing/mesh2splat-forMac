#include <metal_stdlib>

using namespace metal;

constant constexpr float kM2SShadowFiniteGuard = 1.0e20f;
constant constexpr float kM2SShadowMinimumClipW = 1.0e-5f;
constant constexpr float kM2SShadowMinimumViewDepth = 1.0e-5f;
constant constexpr float kM2SShadowMinimumGaussianScale = 1.0e-7f;
constant constexpr float kM2SShadowGaussianExtentSigma = 3.0f;
constant constexpr float kM2SShadowCovarianceLowPassPixels = 0.3f;
constant constexpr float kM2SShadowMinimumAxisPixels = 0.75f;
constant constexpr float kM2SShadowMaximumAxisPixels = 1024.0f;

struct M2SShadowMatrix4 {
    float4 columns[4];
};

struct M2SShadowFrameUniforms {
    M2SShadowMatrix4 modelMatrix;
    M2SShadowMatrix4 viewMatrix;
    M2SShadowMatrix4 projectionMatrix;
    M2SShadowMatrix4 modelViewProjectionMatrix;
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

struct M2SShadowGaussianRecord {
    float4 position;
    float4 color;
    float4 scale;
    float4 normal;
    float4 rotation;
    float4 pbr;
};

struct M2SShadowVertexOut {
    float4 position [[position]];
    float2 localPosition;
    float linearDistance;
    float clipDepth;
    float screenRadiusPixels;
};

struct M2SShadowFragmentOut {
    float distance [[color(0)]];
    float depth [[depth(any)]];
};

struct M2SShadowSymmetricCov3 {
    float xx;
    float xy;
    float xz;
    float yy;
    float yz;
    float zz;
};

struct M2SShadowScreenBasis {
    float2 majorAxisPixels;
    float2 minorAxisPixels;
    float radiusPixels;
    bool valid;
};

static_assert(sizeof(M2SShadowMatrix4) == 64, "Shadow matrix ABI must remain four float4 columns.");
static_assert(sizeof(M2SShadowFrameUniforms) == 400, "Shadow frame uniforms must match FrameUniforms.");
static_assert(sizeof(M2SShadowGaussianRecord) == 96, "Shadow gaussian record must remain six float4 slots.");

static bool m2sShadowFinite(float value)
{
    return value == value && abs(value) <= kM2SShadowFiniteGuard;
}

static bool m2sShadowFinite(float2 value)
{
    return all(value == value) && all(abs(value) <= float2(kM2SShadowFiniteGuard));
}

static bool m2sShadowFinite(float3 value)
{
    return all(value == value) && all(abs(value) <= float3(kM2SShadowFiniteGuard));
}

static bool m2sShadowFinite(float4 value)
{
    return all(value == value) && all(abs(value) <= float4(kM2SShadowFiniteGuard));
}

static float4 m2sShadowTransformPoint(M2SShadowMatrix4 matrix, float3 position)
{
    return matrix.columns[0] * position.x +
        matrix.columns[1] * position.y +
        matrix.columns[2] * position.z +
        matrix.columns[3];
}

static float3 m2sShadowTransformVector(M2SShadowMatrix4 matrix, float3 value)
{
    return matrix.columns[0].xyz * value.x +
        matrix.columns[1].xyz * value.y +
        matrix.columns[2].xyz * value.z;
}

static float2 m2sShadowClipToNdc(float4 clipPosition)
{
    const float safeW = abs(clipPosition.w) > kM2SShadowMinimumClipW ?
        clipPosition.w :
        copysign(kM2SShadowMinimumClipW, clipPosition.w);
    return clipPosition.xy / safeW;
}

static float4 m2sShadowSafeQuaternion(float4 quaternion)
{
    const float lengthSquared = dot(quaternion, quaternion);
    return lengthSquared > 1.0e-12f ? quaternion * rsqrt(lengthSquared) : float4(1.0f, 0.0f, 0.0f, 0.0f);
}

static float3 m2sShadowRotateByQuaternion(float4 quaternion, float3 value)
{
    const float4 q = m2sShadowSafeQuaternion(quaternion);
    const float3 vector = q.yzw;
    const float3 t = 2.0f * cross(vector, value);
    return value + q.x * t + cross(vector, t);
}

static float2 m2sShadowSafeNormalize(float2 value, float2 fallback)
{
    const float lengthSquared = dot(value, value);
    return lengthSquared > 1.0e-12f ? value * rsqrt(lengthSquared) : fallback;
}

static float2 m2sShadowClampedAxisPixels(float2 axisPixels, float2 fallback, float minimumPixels, float maximumPixels)
{
    const float lengthPixels = length(axisPixels);
    if (lengthPixels <= 1.0e-4f) {
        return fallback * minimumPixels;
    }

    return axisPixels * (clamp(lengthPixels, minimumPixels, maximumPixels) / lengthPixels);
}

static bool m2sShadowRenderableGaussian(M2SShadowGaussianRecord gaussian)
{
    return m2sShadowFinite(gaussian.position) &&
        m2sShadowFinite(gaussian.color) &&
        m2sShadowFinite(gaussian.scale) &&
        m2sShadowFinite(gaussian.rotation) &&
        gaussian.scale.x > 0.0f &&
        gaussian.scale.y > 0.0f &&
        gaussian.scale.z >= 0.0f &&
        gaussian.color.a > 0.0f &&
        gaussian.color.a <= 1.0f;
}

static M2SShadowSymmetricCov3 m2sShadowCovarianceFromAxes(float3 axisX, float3 axisY, float3 axisZ)
{
    M2SShadowSymmetricCov3 covariance;
    covariance.xx = axisX.x * axisX.x + axisY.x * axisY.x + axisZ.x * axisZ.x;
    covariance.xy = axisX.x * axisX.y + axisY.x * axisY.y + axisZ.x * axisZ.y;
    covariance.xz = axisX.x * axisX.z + axisY.x * axisY.z + axisZ.x * axisZ.z;
    covariance.yy = axisX.y * axisX.y + axisY.y * axisY.y + axisZ.y * axisZ.y;
    covariance.yz = axisX.y * axisX.z + axisY.y * axisY.z + axisZ.y * axisZ.z;
    covariance.zz = axisX.z * axisX.z + axisY.z * axisY.z + axisZ.z * axisZ.z;
    return covariance;
}

static float2 m2sShadowMajorEigenvector(float xx, float xy, float yy, float lambda)
{
    const float2 diagonalFallback = xx >= yy ? float2(1.0f, 0.0f) : float2(0.0f, 1.0f);
    if (abs(xy) <= 1.0e-7f && abs(lambda - xx) <= 1.0e-7f) {
        return diagonalFallback;
    }

    return m2sShadowSafeNormalize(float2(xy, lambda - xx), diagonalFallback);
}

static M2SShadowScreenBasis m2sShadowComputeScreenBasis(
    M2SShadowGaussianRecord gaussian,
    constant M2SShadowFrameUniforms& frame,
    float3 viewPosition)
{
    M2SShadowScreenBasis basis;
    basis.majorAxisPixels = float2(0.0f);
    basis.minorAxisPixels = float2(0.0f);
    basis.radiusPixels = 0.0f;
    basis.valid = false;

    if (!m2sShadowFinite(viewPosition) || viewPosition.z >= -kM2SShadowMinimumViewDepth) {
        return basis;
    }

    const float2 viewportPixels = max(frame.viewport.xy, float2(1.0f));
    float focalX = frame.hfovFocal.z;
    float focalY = frame.hfovFocal.w;
    if (focalX <= 0.0f || !m2sShadowFinite(focalX)) {
        focalX = abs(frame.projectionMatrix.columns[0].x) * viewportPixels.x * 0.5f;
    }
    if (focalY <= 0.0f || !m2sShadowFinite(focalY)) {
        focalY = abs(frame.projectionMatrix.columns[1].y) * viewportPixels.y * 0.5f;
    }
    if (focalX <= 0.0f || focalY <= 0.0f || !m2sShadowFinite(focalX) || !m2sShadowFinite(focalY)) {
        return basis;
    }

    const float splatScale = clamp(max(frame.gaussianParams.x, 0.0f), 0.05f, 64.0f);
    const float3 scale = float3(
        max(gaussian.scale.x, kM2SShadowMinimumGaussianScale),
        max(gaussian.scale.y, kM2SShadowMinimumGaussianScale),
        max(gaussian.scale.z, kM2SShadowMinimumGaussianScale)) * splatScale;
    const float3 localAxisX = m2sShadowRotateByQuaternion(gaussian.rotation, float3(scale.x, 0.0f, 0.0f));
    const float3 localAxisY = m2sShadowRotateByQuaternion(gaussian.rotation, float3(0.0f, scale.y, 0.0f));
    const float3 localAxisZ = m2sShadowRotateByQuaternion(gaussian.rotation, float3(0.0f, 0.0f, scale.z));
    const float3 viewAxisX = m2sShadowTransformVector(frame.viewMatrix, m2sShadowTransformVector(frame.modelMatrix, localAxisX));
    const float3 viewAxisY = m2sShadowTransformVector(frame.viewMatrix, m2sShadowTransformVector(frame.modelMatrix, localAxisY));
    const float3 viewAxisZ = m2sShadowTransformVector(frame.viewMatrix, m2sShadowTransformVector(frame.modelMatrix, localAxisZ));
    if (!m2sShadowFinite(viewAxisX) || !m2sShadowFinite(viewAxisY) || !m2sShadowFinite(viewAxisZ)) {
        return basis;
    }

    const M2SShadowSymmetricCov3 covariance = m2sShadowCovarianceFromAxes(viewAxisX, viewAxisY, viewAxisZ);
    const float invZ = 1.0f / viewPosition.z;
    const float invZSquared = invZ * invZ;
    const float jxx = -focalX * invZ;
    const float jxz = focalX * viewPosition.x * invZSquared;
    const float jyy = -focalY * invZ;
    const float jyz = focalY * viewPosition.y * invZSquared;
    float covXX = jxx * jxx * covariance.xx +
        2.0f * jxx * jxz * covariance.xz +
        jxz * jxz * covariance.zz +
        kM2SShadowCovarianceLowPassPixels;
    float covYY = jyy * jyy * covariance.yy +
        2.0f * jyy * jyz * covariance.yz +
        jyz * jyz * covariance.zz +
        kM2SShadowCovarianceLowPassPixels;
    float covXY = jxx * jyy * covariance.xy +
        jxx * jyz * covariance.xz +
        jxz * jyy * covariance.yz +
        jxz * jyz * covariance.zz;
    if (!m2sShadowFinite(covXX) || !m2sShadowFinite(covYY) || !m2sShadowFinite(covXY)) {
        return basis;
    }

    covXX = max(covXX, 0.0f);
    covYY = max(covYY, 0.0f);
    const float trace = covXX + covYY;
    const float delta = sqrt(max((covXX - covYY) * (covXX - covYY) + 4.0f * covXY * covXY, 0.0f));
    const float majorLambda = max(0.5f * (trace + delta), 0.0f);
    const float minorLambda = max(0.5f * (trace - delta), 0.0f);
    if (!m2sShadowFinite(majorLambda) || !m2sShadowFinite(minorLambda)) {
        return basis;
    }

    const float2 majorDirection = m2sShadowMajorEigenvector(covXX, covXY, covYY, majorLambda);
    const float2 minorDirection = float2(-majorDirection.y, majorDirection.x);
    const float2 majorAxis = m2sShadowClampedAxisPixels(
        majorDirection * (kM2SShadowGaussianExtentSigma * sqrt(majorLambda)),
        majorDirection,
        kM2SShadowMinimumAxisPixels,
        kM2SShadowMaximumAxisPixels);
    const float2 minorAxis = m2sShadowClampedAxisPixels(
        minorDirection * (kM2SShadowGaussianExtentSigma * sqrt(minorLambda)),
        minorDirection,
        kM2SShadowMinimumAxisPixels,
        kM2SShadowMaximumAxisPixels);
    if (!m2sShadowFinite(majorAxis) || !m2sShadowFinite(minorAxis)) {
        return basis;
    }

    basis.majorAxisPixels = majorAxis;
    basis.minorAxisPixels = minorAxis;
    basis.radiusPixels = max(length(majorAxis), length(minorAxis));
    basis.valid = basis.radiusPixels > 0.0f && m2sShadowFinite(basis.radiusPixels);
    return basis;
}

vertex M2SShadowVertexOut gaussianShadowVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device M2SShadowGaussianRecord* gaussians [[buffer(0)]],
    constant M2SShadowFrameUniforms& frame [[buffer(1)]])
{
    constexpr float2 corners[6] = {
        float2(-1.0f, -1.0f),
        float2(1.0f, -1.0f),
        float2(-1.0f, 1.0f),
        float2(1.0f, -1.0f),
        float2(1.0f, 1.0f),
        float2(-1.0f, 1.0f),
    };

    const M2SShadowGaussianRecord gaussian = gaussians[instanceID];
    const float2 corner = corners[vertexID % 6u];

    M2SShadowVertexOut out;
    out.position = float4(0.0f, 0.0f, 1.0f, 1.0f);
    out.localPosition = float2(2.0f);
    out.linearDistance = 1.0f;
    out.clipDepth = 1.0f;
    out.screenRadiusPixels = 0.0f;

    if (!m2sShadowRenderableGaussian(gaussian)) {
        return out;
    }

    const float4 worldPosition = m2sShadowTransformPoint(frame.modelMatrix, gaussian.position.xyz);
    const float4 viewPosition = m2sShadowTransformPoint(frame.viewMatrix, worldPosition.xyz);
    const float4 clipPosition = m2sShadowTransformPoint(frame.projectionMatrix, viewPosition.xyz);
    if (!m2sShadowFinite(worldPosition) || !m2sShadowFinite(viewPosition) || !m2sShadowFinite(clipPosition) ||
        clipPosition.w <= kM2SShadowMinimumClipW) {
        return out;
    }

    const float clipLimit = clipPosition.w * 1.05f;
    if (clipPosition.z < -clipPosition.w * 0.05f || clipPosition.z > clipLimit) {
        return out;
    }

    const M2SShadowScreenBasis screenBasis = m2sShadowComputeScreenBasis(gaussian, frame, viewPosition.xyz);
    if (!screenBasis.valid) {
        return out;
    }

    const float2 viewportPixels = max(frame.viewport.xy, float2(1.0f));
    const float2 inverseViewport = 1.0f / viewportPixels;
    const float2 centerNdc = m2sShadowClipToNdc(clipPosition);
    const float2 splatNdcExtent =
        (abs(screenBasis.majorAxisPixels) + abs(screenBasis.minorAxisPixels)) *
        2.0f *
        inverseViewport;
    if (centerNdc.x < -1.05f - splatNdcExtent.x ||
        centerNdc.x > 1.05f + splatNdcExtent.x ||
        centerNdc.y < -1.05f - splatNdcExtent.y ||
        centerNdc.y > 1.05f + splatNdcExtent.y) {
        return out;
    }

    const float2 ndcOffset =
        (screenBasis.majorAxisPixels * corner.x + screenBasis.minorAxisPixels * corner.y) *
        2.0f *
        inverseViewport;

    const float farPlane = max(frame.clippingPlanes.y, frame.clippingPlanes.x + 1.0e-3f);
    out.position = clipPosition;
    out.position.xy += ndcOffset * clipPosition.w;
    out.localPosition = corner;
    out.linearDistance = clamp(length(worldPosition.xyz - frame.lightPositionIntensity.xyz) / farPlane, 0.0f, 1.0f);
    out.clipDepth = clamp(clipPosition.z / clipPosition.w, 0.0f, 1.0f);
    out.screenRadiusPixels = screenBasis.radiusPixels;
    return out;
}

fragment M2SShadowFragmentOut gaussianShadowFragment(M2SShadowVertexOut in [[stage_in]])
{
    if (in.screenRadiusPixels <= 0.0f || dot(in.localPosition, in.localPosition) > 1.0f) {
        discard_fragment();
    }

    M2SShadowFragmentOut out;
    out.distance = in.linearDistance;
    out.depth = in.clipDepth;
    return out;
}
