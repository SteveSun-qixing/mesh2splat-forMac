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
    float4 frameTiming;
    float4 lightPositionIntensity;
    float4 lightColorFlags;
};

struct GaussianRecord {
    float4 position;
    float4 color;
    float4 scale;
    float4 normal;
    float4 rotation;
    float4 pbr;
};

struct GaussianVertexOut {
    float4 position [[position]];
    float4 color;
    float2 localPosition;
    float3 worldPosition;
    float3 normal;
    float4 pbr;
    float viewDepth;
    float3 geometryColor;
    float3 sortColor;
    float screenRadiusPixels;
};

struct SymmetricCov3 {
    float xx;
    float xy;
    float xz;
    float yy;
    float yz;
    float zz;
};

struct GaussianScreenBasis {
    float2 majorAxisPixels;
    float2 minorAxisPixels;
    float radiusPixels;
    bool valid;
};

constant constexpr float kFiniteGuard = 1.0e20;
constant constexpr float kMinimumClipW = 1.0e-5;
constant constexpr float kMinimumViewDepth = 1.0e-5;
constant constexpr float kMinimumGaussianScale = 1.0e-7;
constant constexpr float kGaussianExtentSigma = 3.0;
constant constexpr float kCovarianceLowPassPixels = 0.3;
constant constexpr float kMinimumAxisPixels = 0.75;
constant constexpr float kMaximumAxisPixels = 512.0;
constant constexpr float kAlphaDiscardThreshold = 1.0e-4;
constant constexpr float kPi = 3.14159265358979323846;
constant constexpr uint kRenderModeAlbedo = 0u;
constant constexpr uint kRenderModeDepth = 1u;
constant constexpr uint kRenderModeNormal = 2u;
constant constexpr uint kRenderModeGeometry = 3u;
constant constexpr uint kRenderModeOverdraw = 4u;
constant constexpr uint kRenderModePbr = 5u;
constant constexpr uint kRenderModeFinal = 6u;
constant constexpr uint kDebugFlagShowGaussianCenters = 1u << 2u;
constant constexpr uint kDebugFlagShowSortOrder = 1u << 4u;
constant constexpr uint kDebugFlagDisableToneMapping = 1u << 6u;

static bool isFiniteFloat(float value)
{
    return value == value && abs(value) <= kFiniteGuard;
}

static bool isFiniteFloat2(float2 value)
{
    return all(value == value) && all(abs(value) <= float2(kFiniteGuard));
}

static bool isFiniteFloat3(float3 value)
{
    return all(value == value) && all(abs(value) <= float3(kFiniteGuard));
}

static bool isFiniteFloat4(float4 value)
{
    return all(value == value) && all(abs(value) <= float4(kFiniteGuard));
}

static float4 transformPoint(Matrix4 matrix, float3 position)
{
    return matrix.columns[0] * position.x +
        matrix.columns[1] * position.y +
        matrix.columns[2] * position.z +
        matrix.columns[3];
}

static float3 transformVector(Matrix4 matrix, float3 value)
{
    return matrix.columns[0].xyz * value.x +
        matrix.columns[1].xyz * value.y +
        matrix.columns[2].xyz * value.z;
}

static float2 clipToNdc(float4 clipPosition)
{
    const float safeW = abs(clipPosition.w) > 1.0e-5 ? clipPosition.w : copysign(1.0e-5, clipPosition.w);
    return clipPosition.xy / safeW;
}

static float4 safeQuaternion(float4 quaternion)
{
    const float lengthSquared = dot(quaternion, quaternion);
    return lengthSquared > 1.0e-12 ? quaternion * rsqrt(lengthSquared) : float4(1.0, 0.0, 0.0, 0.0);
}

static float3 rotateByQuaternion(float4 quaternion, float3 value)
{
    const float4 q = safeQuaternion(quaternion);
    const float3 vector = q.yzw;
    const float3 t = 2.0 * cross(vector, value);
    return value + q.x * t + cross(vector, t);
}

static float2 safeNormalize(float2 value, float2 fallback)
{
    const float lengthSquared = dot(value, value);
    return lengthSquared > 1.0e-12 ? value * rsqrt(lengthSquared) : fallback;
}

static float3 safeNormalize(float3 value, float3 fallback)
{
    const float lengthSquared = dot(value, value);
    return lengthSquared > 1.0e-12 ? value * rsqrt(lengthSquared) : fallback;
}

static float2 clampedAxisPixels(float2 axisPixels, float2 fallback, float minimumPixels, float maximumPixels)
{
    const float lengthPixels = length(axisPixels);
    if (lengthPixels <= 1.0e-4) {
        return fallback * minimumPixels;
    }

    return axisPixels * (clamp(lengthPixels, minimumPixels, maximumPixels) / lengthPixels);
}

static bool hasRenderableGaussianRecord(GaussianRecord gaussian)
{
    return isFiniteFloat4(gaussian.position) &&
        isFiniteFloat4(gaussian.color) &&
        isFiniteFloat4(gaussian.scale) &&
        isFiniteFloat4(gaussian.normal) &&
        isFiniteFloat4(gaussian.rotation) &&
        isFiniteFloat4(gaussian.pbr) &&
        gaussian.scale.x > 0.0 &&
        gaussian.scale.y > 0.0 &&
        gaussian.scale.z >= 0.0 &&
        gaussian.color.a > 0.0 &&
        gaussian.color.a <= 1.0;
}

static SymmetricCov3 covarianceFromAxes(float3 axisX, float3 axisY, float3 axisZ)
{
    SymmetricCov3 covariance;
    covariance.xx = axisX.x * axisX.x + axisY.x * axisY.x + axisZ.x * axisZ.x;
    covariance.xy = axisX.x * axisX.y + axisY.x * axisY.y + axisZ.x * axisZ.y;
    covariance.xz = axisX.x * axisX.z + axisY.x * axisY.z + axisZ.x * axisZ.z;
    covariance.yy = axisX.y * axisX.y + axisY.y * axisY.y + axisZ.y * axisZ.y;
    covariance.yz = axisX.y * axisX.z + axisY.y * axisY.z + axisZ.y * axisZ.z;
    covariance.zz = axisX.z * axisX.z + axisY.z * axisY.z + axisZ.z * axisZ.z;
    return covariance;
}

static float2 majorEigenvector(float xx, float xy, float yy, float lambda)
{
    const float2 diagonalFallback = xx >= yy ? float2(1.0, 0.0) : float2(0.0, 1.0);
    if (abs(xy) <= 1.0e-7 && abs(lambda - xx) <= 1.0e-7) {
        return diagonalFallback;
    }

    return safeNormalize(float2(xy, lambda - xx), diagonalFallback);
}

static GaussianScreenBasis computeScreenBasis(
    GaussianRecord gaussian,
    constant FrameUniforms& frame,
    float3 viewPosition)
{
    GaussianScreenBasis basis;
    basis.majorAxisPixels = float2(0.0);
    basis.minorAxisPixels = float2(0.0);
    basis.radiusPixels = 0.0;
    basis.valid = false;

    if (!isFiniteFloat3(viewPosition) || viewPosition.z >= -kMinimumViewDepth) {
        return basis;
    }

    const float2 viewportPixels = max(frame.viewport.xy, float2(1.0));
    float focalX = frame.hfovFocal.z;
    float focalY = frame.hfovFocal.w;
    if (focalX <= 0.0 || !isFiniteFloat(focalX)) {
        focalX = abs(frame.projectionMatrix.columns[0].x) * viewportPixels.x * 0.5;
    }
    if (focalY <= 0.0 || !isFiniteFloat(focalY)) {
        focalY = abs(frame.projectionMatrix.columns[1].y) * viewportPixels.y * 0.5;
    }
    if (focalX <= 0.0 || focalY <= 0.0 || !isFiniteFloat(focalX) || !isFiniteFloat(focalY)) {
        return basis;
    }

    const float splatScale = clamp(max(frame.gaussianParams.x, 0.0), 0.05, 64.0);
    const float3 scale = float3(
        max(gaussian.scale.x, kMinimumGaussianScale),
        max(gaussian.scale.y, kMinimumGaussianScale),
        max(gaussian.scale.z, kMinimumGaussianScale)) * splatScale;
    const float3 localAxisX = rotateByQuaternion(gaussian.rotation, float3(scale.x, 0.0, 0.0));
    const float3 localAxisY = rotateByQuaternion(gaussian.rotation, float3(0.0, scale.y, 0.0));
    const float3 localAxisZ = rotateByQuaternion(gaussian.rotation, float3(0.0, 0.0, scale.z));
    const float3 viewAxisX = transformVector(frame.viewMatrix, transformVector(frame.modelMatrix, localAxisX));
    const float3 viewAxisY = transformVector(frame.viewMatrix, transformVector(frame.modelMatrix, localAxisY));
    const float3 viewAxisZ = transformVector(frame.viewMatrix, transformVector(frame.modelMatrix, localAxisZ));
    if (!isFiniteFloat3(viewAxisX) || !isFiniteFloat3(viewAxisY) || !isFiniteFloat3(viewAxisZ)) {
        return basis;
    }

    const SymmetricCov3 covariance = covarianceFromAxes(viewAxisX, viewAxisY, viewAxisZ);
    const float invZ = 1.0 / viewPosition.z;
    const float invZSquared = invZ * invZ;
    const float jxx = -focalX * invZ;
    const float jxz = focalX * viewPosition.x * invZSquared;
    const float jyy = -focalY * invZ;
    const float jyz = focalY * viewPosition.y * invZSquared;
    float covXX = jxx * jxx * covariance.xx +
        2.0 * jxx * jxz * covariance.xz +
        jxz * jxz * covariance.zz +
        kCovarianceLowPassPixels;
    float covYY = jyy * jyy * covariance.yy +
        2.0 * jyy * jyz * covariance.yz +
        jyz * jyz * covariance.zz +
        kCovarianceLowPassPixels;
    float covXY = jxx * jyy * covariance.xy +
        jxx * jyz * covariance.xz +
        jxz * jyy * covariance.yz +
        jxz * jyz * covariance.zz;
    if (!isFiniteFloat(covXX) || !isFiniteFloat(covYY) || !isFiniteFloat(covXY)) {
        return basis;
    }

    covXX = max(covXX, 0.0);
    covYY = max(covYY, 0.0);
    const float trace = covXX + covYY;
    const float delta = sqrt(max((covXX - covYY) * (covXX - covYY) + 4.0 * covXY * covXY, 0.0));
    const float majorLambda = max(0.5 * (trace + delta), 0.0);
    const float minorLambda = max(0.5 * (trace - delta), 0.0);
    if (!isFiniteFloat(majorLambda) || !isFiniteFloat(minorLambda)) {
        return basis;
    }

    const float2 majorDirection = majorEigenvector(covXX, covXY, covYY, majorLambda);
    const float2 minorDirection = float2(-majorDirection.y, majorDirection.x);
    const float2 majorAxis = clampedAxisPixels(
        majorDirection * (kGaussianExtentSigma * sqrt(majorLambda)),
        majorDirection,
        kMinimumAxisPixels,
        kMaximumAxisPixels);
    const float2 minorAxis = clampedAxisPixels(
        minorDirection * (kGaussianExtentSigma * sqrt(minorLambda)),
        minorDirection,
        kMinimumAxisPixels,
        kMaximumAxisPixels);
    if (!isFiniteFloat2(majorAxis) || !isFiniteFloat2(minorAxis)) {
        return basis;
    }

    basis.majorAxisPixels = majorAxis;
    basis.minorAxisPixels = minorAxis;
    basis.radiusPixels = max(length(majorAxis), length(minorAxis));
    basis.valid = basis.radiusPixels > 0.0 && isFiniteFloat(basis.radiusPixels);
    return basis;
}

static uint hashUint(uint value)
{
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

static float hashUnitFloat(uint value)
{
    return float(hashUint(value) & 0x00ffffffu) / 16777215.0;
}

static float3 hashColor(uint value)
{
    return float3(
        hashUnitFloat(value * 3u + 1u),
        hashUnitFloat(value * 3u + 2u),
        hashUnitFloat(value * 3u + 3u));
}

static float exponentialDepth(float viewDepth, float2 nearFar)
{
    const float range = max(nearFar.y - nearFar.x, 1.0e-5);
    const float normalizedDepth = clamp((viewDepth - nearFar.x) / range, 0.0, 1.0);
    return clamp(exp(-20.0 * normalizedDepth), 0.0, 1.0);
}

static float3 fresnelSchlick(float cosTheta, float3 f0)
{
    return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

static float distributionGGX(float3 normal, float3 halfVector, float roughness)
{
    const float resolvedRoughness = clamp(roughness, 0.04, 1.0);
    const float a = resolvedRoughness * resolvedRoughness;
    const float a2 = a * a;
    const float nDotH = saturate(dot(normal, halfVector));
    const float nDotH2 = nDotH * nDotH;
    const float denom = nDotH2 * (a2 - 1.0) + 1.0;
    return a2 / max(kPi * denom * denom, 1.0e-5);
}

static float geometrySchlickGGX(float nDotV, float roughness)
{
    const float r = roughness + 1.0;
    const float k = (r * r) * 0.125;
    return nDotV / max(nDotV * (1.0 - k) + k, 1.0e-5);
}

static float geometrySmith(float3 normal, float3 viewDirection, float3 lightDirection, float roughness)
{
    const float nDotV = saturate(dot(normal, viewDirection));
    const float nDotL = saturate(dot(normal, lightDirection));
    return geometrySchlickGGX(nDotV, roughness) * geometrySchlickGGX(nDotL, roughness);
}

static float gaussianShadowFactor(
    float3 worldPosition,
    constant FrameUniforms& frame,
    texturecube<float> shadowDistanceTexture,
    sampler shadowSampler)
{
    if (frame.lightColorFlags.w < 1.5) {
        return 0.0;
    }

    const float3 sampleOffsetDirections[20] = {
        float3(1.0, 1.0, 1.0),
        float3(1.0, -1.0, 1.0),
        float3(-1.0, -1.0, 1.0),
        float3(-1.0, 1.0, 1.0),
        float3(1.0, 1.0, -1.0),
        float3(1.0, -1.0, -1.0),
        float3(-1.0, -1.0, -1.0),
        float3(-1.0, 1.0, -1.0),
        float3(1.0, 1.0, 0.0),
        float3(1.0, -1.0, 0.0),
        float3(-1.0, -1.0, 0.0),
        float3(-1.0, 1.0, 0.0),
        float3(1.0, 0.0, 1.0),
        float3(-1.0, 0.0, 1.0),
        float3(1.0, 0.0, -1.0),
        float3(-1.0, 0.0, -1.0),
        float3(0.0, 1.0, 1.0),
        float3(0.0, -1.0, 1.0),
        float3(0.0, -1.0, -1.0),
        float3(0.0, 1.0, -1.0),
    };

    const float farPlane = max(frame.clippingPlanes.y, frame.clippingPlanes.x + 1.0e-3);
    const float3 lightVector = worldPosition - frame.lightPositionIntensity.xyz;
    const float currentDepth = length(lightVector);
    if (currentDepth <= 1.0e-4 || currentDepth >= farPlane) {
        return 0.0;
    }

    const float3 sampleDirection = safeNormalize(lightVector, float3(0.0, 0.0, 1.0));
    const float bias = 0.05;
    const float diskRadius = 0.025;
    float shadow = 0.0;
    for (uint index = 0; index < 20u; ++index) {
        const float closestDepth =
            shadowDistanceTexture.sample(shadowSampler, sampleDirection + sampleOffsetDirections[index] * diskRadius).r *
            farPlane;
        shadow += currentDepth - bias > closestDepth ? 1.0 : 0.0;
    }
    return shadow / 20.0;
}

static float3 finalPreviewColor(
    GaussianVertexOut in,
    constant FrameUniforms& frame,
    texturecube<float> shadowDistanceTexture,
    sampler shadowSampler)
{
    const float3 baseColor = max(in.color.rgb, float3(0.0));
    const float3 normal = safeNormalize(in.normal, float3(0.0, 1.0, 0.0));
    const float3 fallbackLightDirection = normalize(float3(0.35, 0.8, 0.45));
    const float3 lightVector = frame.lightPositionIntensity.xyz - in.worldPosition;
    const float3 lightDirection = safeNormalize(lightVector, fallbackLightDirection);
    const float3 viewDirection = safeNormalize(frame.cameraPosition.xyz - in.worldPosition, float3(0.0, 0.0, 1.0));
    const float3 halfVector = safeNormalize(lightDirection + viewDirection, lightDirection);
    const float metallic = clamp(in.pbr.x, 0.0, 1.0);
    const float roughness = clamp(in.pbr.y, 0.04, 1.0);
    const float occlusion = clamp(in.pbr.z, 0.0, 1.0);
    const float emissiveStrength = clamp(in.pbr.w, 0.0, 4.0);
    const float3 emissive = baseColor * emissiveStrength;
    if (frame.lightColorFlags.w <= 0.5 || frame.lightPositionIntensity.w <= 0.0) {
        return baseColor * occlusion + emissive;
    }

    const float3 lightColor = max(frame.lightColorFlags.xyz, float3(0.0));
    const float lightIntensity = max(frame.lightPositionIntensity.w, 0.0);
    const float attenuation = 1.0 / max(dot(lightVector, lightVector), 1.0);
    const float3 radiance = lightColor * lightIntensity * attenuation;
    const float3 f0 = mix(float3(0.04), baseColor, metallic);
    const float3 fresnel = fresnelSchlick(saturate(dot(halfVector, viewDirection)), f0);
    const float normalDistribution = distributionGGX(normal, halfVector, roughness);
    const float geometry = geometrySmith(normal, viewDirection, lightDirection, roughness);
    const float denominator = max(4.0 * saturate(dot(normal, viewDirection)) * saturate(dot(normal, lightDirection)), 1.0e-4);
    const float3 specular = (normalDistribution * geometry * fresnel) / denominator;
    const float3 diffuseWeight = (1.0 - fresnel) * (1.0 - metallic);
    const float nDotL = saturate(dot(normal, lightDirection));
    const float shadow = gaussianShadowFactor(in.worldPosition, frame, shadowDistanceTexture, shadowSampler);
    const float3 direct = (diffuseWeight * baseColor / kPi + specular) * radiance * nDotL * (1.0 - shadow);
    const float3 ambient = 0.3 * baseColor * occlusion;
    return ambient + direct + emissive;
}

static float3 toneMappedColor(float3 color, constant FrameUniforms& frame)
{
    if ((frame.flags & kDebugFlagDisableToneMapping) != 0u) {
        return max(color, float3(0.0));
    }

    const float exposure = max(frame.gaussianParams.y, 0.0);
    const float gamma = max(frame.gaussianParams.z, 0.1);
    const float3 exposed = 1.0 - exp(-max(color, float3(0.0)) * exposure);
    return pow(saturate(exposed), float3(1.0 / gamma));
}

static bool renderModeUsesToneMapping(uint renderMode)
{
    return renderMode == kRenderModeAlbedo || renderMode == kRenderModeFinal;
}

static float3 visualizationColor(
    GaussianVertexOut in,
    constant FrameUniforms& frame,
    texturecube<float> shadowDistanceTexture,
    sampler shadowSampler)
{
    if ((frame.flags & kDebugFlagShowSortOrder) != 0u) {
        return in.sortColor;
    }

    if (frame.renderMode == kRenderModeDepth) {
        const float depth = exponentialDepth(in.viewDepth, frame.clippingPlanes.xy);
        return float3(depth);
    }

    if (frame.renderMode == kRenderModeNormal) {
        return safeNormalize(in.normal, float3(0.0, 1.0, 0.0)) * 0.5 + 0.5;
    }

    if (frame.renderMode == kRenderModeGeometry) {
        return in.geometryColor;
    }

    if (frame.renderMode == kRenderModeOverdraw) {
        return float3(1.0, 0.45, 0.08);
    }

    if (frame.renderMode == kRenderModePbr) {
        return float3(clamp(in.pbr.x, 0.0, 1.0), clamp(in.pbr.y, 0.0, 1.0), clamp(in.pbr.z, 0.0, 1.0));
    }

    if (frame.renderMode == kRenderModeFinal) {
        return finalPreviewColor(in, frame, shadowDistanceTexture, shadowSampler);
    }

    return in.color.rgb;
}

vertex GaussianVertexOut gaussianPreviewVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device GaussianRecord* gaussians [[buffer(0)]],
    constant FrameUniforms& frame [[buffer(1)]],
    const device uint* gaussianIndices [[buffer(2)]])
{
    constexpr float2 corners[6] = {
        float2(-1.0, -1.0),
        float2(1.0, -1.0),
        float2(-1.0, 1.0),
        float2(1.0, -1.0),
        float2(1.0, 1.0),
        float2(-1.0, 1.0),
    };

    const uint gaussianIndex = gaussianIndices[instanceID];
    const GaussianRecord gaussian = gaussians[gaussianIndex];
    const float2 corner = corners[vertexID % 6];

    GaussianVertexOut out;
    out.position = float4(0.0, 0.0, 1.0, 1.0);
    out.color = float4(0.0);
    out.localPosition = float2(2.0);
    out.worldPosition = float3(0.0);
    out.normal = float3(0.0, 1.0, 0.0);
    out.pbr = float4(0.0, 1.0, 1.0, 0.0);
    out.viewDepth = 0.0;
    out.geometryColor = hashColor(gaussianIndex);
    out.sortColor = hashColor(instanceID);
    out.screenRadiusPixels = 0.0;

    if (!hasRenderableGaussianRecord(gaussian)) {
        return out;
    }

    const float4 worldPosition = transformPoint(frame.modelMatrix, gaussian.position.xyz);
    const float4 viewPosition = transformPoint(frame.viewMatrix, worldPosition.xyz);
    const float4 clipPosition = transformPoint(frame.projectionMatrix, viewPosition.xyz);
    if (!isFiniteFloat4(worldPosition) || !isFiniteFloat4(viewPosition) || !isFiniteFloat4(clipPosition) ||
        clipPosition.w <= kMinimumClipW) {
        return out;
    }

    const float clipLimit = clipPosition.w * 1.05;
    if (clipPosition.z < -clipPosition.w * 0.05 ||
        clipPosition.z > clipLimit) {
        return out;
    }

    const GaussianScreenBasis screenBasis = computeScreenBasis(gaussian, frame, viewPosition.xyz);
    if (!screenBasis.valid) {
        return out;
    }

    const float2 viewportPixels = max(frame.viewport.xy, float2(1.0));
    const float2 inverseViewport = 1.0 / viewportPixels;
    const float2 centerNdc = clipToNdc(clipPosition);
    const float2 splatNdcExtent =
        (abs(screenBasis.majorAxisPixels) + abs(screenBasis.minorAxisPixels)) *
        2.0 *
        inverseViewport;
    if (centerNdc.x < -1.05 - splatNdcExtent.x ||
        centerNdc.x > 1.05 + splatNdcExtent.x ||
        centerNdc.y < -1.05 - splatNdcExtent.y ||
        centerNdc.y > 1.05 + splatNdcExtent.y) {
        return out;
    }

    const float2 ndcOffset =
        (screenBasis.majorAxisPixels * corner.x + screenBasis.minorAxisPixels * corner.y) *
        2.0 *
        inverseViewport;

    out.position = clipPosition;
    out.position.xy += ndcOffset * clipPosition.w;
    out.color = gaussian.color;
    out.localPosition = corner;
    out.worldPosition = worldPosition.xyz;
    out.normal = safeNormalize(transformVector(frame.modelMatrix, gaussian.normal.xyz), float3(0.0, 1.0, 0.0));
    out.pbr = gaussian.pbr;
    out.viewDepth = max(-viewPosition.z, 0.0);
    out.geometryColor = hashColor(gaussianIndex);
    out.sortColor = hashColor(instanceID);
    out.screenRadiusPixels = screenBasis.radiusPixels;
    return out;
}

fragment float4 gaussianPreviewFragment(
    GaussianVertexOut in [[stage_in]],
    constant FrameUniforms& frame [[buffer(0)]],
    texturecube<float> shadowDistanceTexture [[texture(0)]],
    sampler shadowSampler [[sampler(0)]])
{
    if (in.screenRadiusPixels <= 0.0 || in.color.a <= 0.0) {
        discard_fragment();
    }

    const float radiusSquared = dot(in.localPosition, in.localPosition);
    if (radiusSquared > 1.0) {
        discard_fragment();
    }

    const float falloff = exp(-0.5 * kGaussianExtentSigma * kGaussianExtentSigma * radiusSquared);
    float alpha = frame.renderMode == kRenderModeOverdraw ? falloff * 0.2 : falloff * clamp(in.color.a, 0.0, 1.0) * 0.75;
    if ((frame.flags & kDebugFlagShowGaussianCenters) != 0u) {
        alpha = radiusSquared <= 0.015625 ? 1.0 : alpha * 0.45;
    }
    if (alpha <= kAlphaDiscardThreshold) {
        discard_fragment();
    }

    float3 color = visualizationColor(in, frame, shadowDistanceTexture, shadowSampler);
    if (renderModeUsesToneMapping(frame.renderMode)) {
        color = toneMappedColor(color, frame);
    }
    return float4(color * alpha, alpha);
}
