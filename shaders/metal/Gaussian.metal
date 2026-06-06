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
};

static float4 transformPoint(Matrix4 matrix, float3 position)
{
    return matrix.columns[0] * position.x +
        matrix.columns[1] * position.y +
        matrix.columns[2] * position.z +
        matrix.columns[3];
}

static float2 clipToNdc(float4 clipPosition)
{
    const float safeW = abs(clipPosition.w) > 1.0e-5 ? clipPosition.w : copysign(1.0e-5, clipPosition.w);
    return clipPosition.xy / safeW;
}

static float3 rotateByQuaternion(float4 quaternion, float3 value)
{
    const float4 q = normalize(quaternion);
    const float3 vector = q.yzw;
    const float3 t = 2.0 * cross(vector, value);
    return value + q.x * t + cross(vector, t);
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

static float3 finalPreviewColor(GaussianVertexOut in, constant FrameUniforms& frame)
{
    const float3 baseColor = max(in.color.rgb, float3(0.0));
    const float3 normal = safeNormalize(in.normal, float3(0.0, 1.0, 0.0));
    const float3 lightDirection = normalize(float3(0.35, 0.8, 0.45));
    const float3 viewDirection = safeNormalize(frame.cameraPosition.xyz - in.worldPosition, float3(0.0, 0.0, 1.0));
    const float3 halfVector = safeNormalize(lightDirection + viewDirection, lightDirection);
    const float metallic = clamp(in.pbr.x, 0.0, 1.0);
    const float roughness = clamp(in.pbr.y, 0.04, 1.0);
    const float occlusion = clamp(in.pbr.z, 0.0, 1.0);
    const float emissiveStrength = clamp(in.pbr.w, 0.0, 4.0);
    const float diffuse = saturate(dot(normal, lightDirection)) * 0.8 + 0.2;
    const float specularPower = mix(96.0, 4.0, roughness);
    const float specular = pow(saturate(dot(normal, halfVector)), specularPower) *
        mix(0.04, 0.45, metallic) * (1.0 - roughness * 0.65);
    const float diffuseWeight = mix(1.0, 0.6, metallic);
    return baseColor * ((diffuse * diffuseWeight + 0.08) * occlusion) + specular + baseColor * emissiveStrength;
}

static float3 visualizationColor(GaussianVertexOut in, constant FrameUniforms& frame)
{
    if (frame.renderMode == 1u) {
        const float depth = exponentialDepth(in.viewDepth, frame.clippingPlanes.xy);
        return float3(depth);
    }

    if (frame.renderMode == 2u) {
        return safeNormalize(in.normal, float3(0.0, 1.0, 0.0)) * 0.5 + 0.5;
    }

    if (frame.renderMode == 3u) {
        return in.geometryColor;
    }

    if (frame.renderMode == 4u) {
        return float3(1.0, 0.45, 0.08);
    }

    if (frame.renderMode == 5u) {
        return float3(clamp(in.pbr.x, 0.0, 1.0), clamp(in.pbr.y, 0.0, 1.0), clamp(in.pbr.z, 0.0, 1.0));
    }

    if (frame.renderMode == 6u) {
        return finalPreviewColor(in, frame);
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
    const float4 clipPosition = transformPoint(frame.modelViewProjectionMatrix, gaussian.position.xyz);
    const float4 viewPosition = transformPoint(frame.viewMatrix, gaussian.position.xyz);
    const float2 inverseViewport = max(frame.viewport.zw, float2(1.0 / 8192.0));
    const float3 scaleXPosition = gaussian.position.xyz +
        rotateByQuaternion(gaussian.rotation, float3(max(abs(gaussian.scale.x), 1.0e-7), 0.0, 0.0));
    const float3 scaleYPosition = gaussian.position.xyz +
        rotateByQuaternion(gaussian.rotation, float3(0.0, max(abs(gaussian.scale.y), 1.0e-7), 0.0));
    const float2 centerNdc = clipToNdc(clipPosition);
    const float2 scaleXNdc = clipToNdc(transformPoint(frame.modelViewProjectionMatrix, scaleXPosition));
    const float2 scaleYNdc = clipToNdc(transformPoint(frame.modelViewProjectionMatrix, scaleYPosition));
    const float2 viewportPixels = max(frame.viewport.xy, float2(1.0));
    const float previewScale = max(frame.gaussianParams.x, 1.0);
    const float2 axisXPixels = clampedAxisPixels(
        (scaleXNdc - centerNdc) * viewportPixels * 0.5 * previewScale,
        float2(1.0, 0.0),
        1.5,
        24.0);
    const float2 axisYPixels = clampedAxisPixels(
        (scaleYNdc - centerNdc) * viewportPixels * 0.5 * previewScale,
        float2(0.0, 1.0),
        1.5,
        24.0);
    const float2 ndcOffset = (axisXPixels * corner.x + axisYPixels * corner.y) * 2.0 * inverseViewport;

    GaussianVertexOut out;
    out.position = clipPosition;
    out.position.xy += ndcOffset * clipPosition.w;
    out.color = gaussian.color;
    out.localPosition = corner;
    out.worldPosition = gaussian.position.xyz;
    out.normal = safeNormalize(gaussian.normal.xyz, float3(0.0, 1.0, 0.0));
    out.pbr = gaussian.pbr;
    out.viewDepth = max(-viewPosition.z, 0.0);
    out.geometryColor = hashColor(gaussianIndex);
    return out;
}

fragment float4 gaussianPreviewFragment(
    GaussianVertexOut in [[stage_in]],
    constant FrameUniforms& frame [[buffer(0)]])
{
    const float radiusSquared = dot(in.localPosition, in.localPosition);
    if (radiusSquared > 1.0) {
        discard_fragment();
    }

    const float falloff = exp(-radiusSquared * 2.5);
    const float alpha = frame.renderMode == 4u ? falloff * 0.2 : falloff * in.color.a * 0.75;
    const float3 color = visualizationColor(in, frame);
    return float4(color * alpha, alpha);
}
