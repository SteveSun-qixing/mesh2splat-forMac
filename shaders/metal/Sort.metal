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

struct GaussianSortParams {
    uint gaussianCount;
    uint keyCapacity;
    uint indexCapacity;
    uint reserved;
};

struct RadixSortParams {
    uint itemCount;
    uint blockCount;
    uint radixShift;
    uint outputCapacity;
};

constexpr uint kRadixBinCount = 16;
constexpr uint kRadixMask = kRadixBinCount - 1u;
constexpr uint kInvalidRadixBin = kRadixBinCount;
constexpr uint kMaxRadixShift = 28;
constexpr uint kRadixSortThreadCount = 256;
constexpr float kMaxSortableDepth = 3.402823466e+38f;

static float4 transformPoint(Matrix4 matrix, float3 position)
{
    return matrix.columns[0] * position.x +
        matrix.columns[1] * position.y +
        matrix.columns[2] * position.z +
        matrix.columns[3];
}

static uint sortableFloatKey(float value)
{
    const uint bits = as_type<uint>(value);
    const uint sign = bits >> 31;
    return sign == 0 ? (bits ^ 0x80000000u) : ~bits;
}

static uint paramCapacityLimit(uint capacity, uint itemCount)
{
    return capacity == 0u ? itemCount : min(capacity, itemCount);
}

static float positiveFiniteDepth(float viewDepth)
{
    if (viewDepth <= 0.0) {
        return 0.0;
    }

    if (!isfinite(viewDepth)) {
        return viewDepth > 0.0 ? kMaxSortableDepth : 0.0;
    }

    return viewDepth;
}

static uint descendingDepthKey(float positiveDepth)
{
    return 0xffffffffu - sortableFloatKey(positiveDepth);
}

static bool validRadixParams(RadixSortParams params)
{
    return params.itemCount > 0u &&
        params.blockCount > 0u &&
        params.blockCount <= (0xffffffffu / kRadixBinCount) &&
        params.radixShift <= kMaxRadixShift;
}

static uint radixDigit(uint key, uint radixShift)
{
    return (key >> radixShift) & kRadixMask;
}

static uint saturatingAdd(uint lhs, uint rhs)
{
    return rhs > (0xffffffffu - lhs) ? 0xffffffffu : lhs + rhs;
}

kernel void gaussianDepthKeyKernel(
    uint threadID [[thread_position_in_grid]],
    const device GaussianRecord* gaussians [[buffer(0)]],
    constant FrameUniforms& frame [[buffer(1)]],
    device uint* depthKeys [[buffer(2)]],
    device uint* indices [[buffer(3)]],
    constant GaussianSortParams& params [[buffer(4)]])
{
    const uint writableCount = min(
        params.gaussianCount,
        min(
            paramCapacityLimit(params.keyCapacity, params.gaussianCount),
            paramCapacityLimit(params.indexCapacity, params.gaussianCount)));
    if (threadID >= writableCount) {
        return;
    }

    const GaussianRecord gaussian = gaussians[threadID];
    const float4 viewPosition = transformPoint(frame.viewMatrix, gaussian.position.xyz);
    const float positiveDepth = positiveFiniteDepth(-viewPosition.z);
    depthKeys[threadID] = descendingDepthKey(positiveDepth);
    indices[threadID] = threadID;
}

kernel void gaussianRadixCountKernel(
    uint localID [[thread_index_in_threadgroup]],
    uint3 blockPosition [[threadgroup_position_in_grid]],
    const device uint* depthKeys [[buffer(0)]],
    device uint* blockCounts [[buffer(1)]],
    device atomic_uint* globalOffsets [[buffer(2)]],
    constant RadixSortParams& params [[buffer(3)]])
{
    const uint blockID = blockPosition.x;
    if (blockID >= params.blockCount || !validRadixParams(params)) {
        return;
    }

    threadgroup atomic_uint localCounts[kRadixBinCount];
    if (localID < kRadixBinCount) {
        atomic_store_explicit(&localCounts[localID], 0u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    const bool participates = localID < kRadixSortThreadCount;
    const uint itemID = blockID * kRadixSortThreadCount + localID;
    if (participates && itemID < params.itemCount) {
        const uint radix = radixDigit(depthKeys[itemID], params.radixShift);
        atomic_fetch_add_explicit(&localCounts[radix], 1u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (localID < kRadixBinCount) {
        const uint radixCount = atomic_load_explicit(&localCounts[localID], memory_order_relaxed);
        blockCounts[localID * params.blockCount + blockID] = radixCount;
        atomic_fetch_add_explicit(&globalOffsets[localID], radixCount, memory_order_relaxed);
    }
}

kernel void gaussianRadixPrefixKernel(
    uint threadID [[thread_position_in_grid]],
    device uint* blockCounts [[buffer(0)]],
    device uint* globalOffsets [[buffer(1)]],
    constant RadixSortParams& params [[buffer(2)]])
{
    if (!validRadixParams(params)) {
        return;
    }

    if (threadID < kRadixBinCount) {
        uint blockRunning = 0;
        for (uint blockID = 0; blockID < params.blockCount; ++blockID) {
            const uint offset = threadID * params.blockCount + blockID;
            const uint blockCount = blockCounts[offset];
            blockCounts[offset] = blockRunning;
            blockRunning = saturatingAdd(blockRunning, blockCount);
        }
    }

    if (threadID == 0) {
        uint globalRunning = 0;
        for (uint radix = 0; radix < kRadixBinCount; ++radix) {
            const uint radixCount = globalOffsets[radix];
            globalOffsets[radix] = globalRunning;
            globalRunning = saturatingAdd(globalRunning, radixCount);
        }
    }
}

kernel void gaussianRadixReorderKernel(
    uint localID [[thread_index_in_threadgroup]],
    uint3 blockPosition [[threadgroup_position_in_grid]],
    const device uint* srcDepthKeys [[buffer(0)]],
    const device uint* srcIndices [[buffer(1)]],
    device uint* dstDepthKeys [[buffer(2)]],
    device uint* dstIndices [[buffer(3)]],
    const device uint* blockOffsets [[buffer(4)]],
    const device uint* globalOffsets [[buffer(5)]],
    constant RadixSortParams& params [[buffer(6)]])
{
    const uint blockID = blockPosition.x;
    if (blockID >= params.blockCount || !validRadixParams(params)) {
        return;
    }

    threadgroup uint digits[kRadixSortThreadCount];
    threadgroup uint prefix[kRadixSortThreadCount];

    const bool participates = localID < kRadixSortThreadCount;
    const uint outputLimit = paramCapacityLimit(params.outputCapacity, params.itemCount);
    const uint itemID = blockID * kRadixSortThreadCount + localID;
    const bool isValid = participates && itemID < params.itemCount;
    const uint key = isValid ? srcDepthKeys[itemID] : 0u;
    const uint index = isValid ? srcIndices[itemID] : 0u;
    const uint itemRadix = isValid ? radixDigit(key, params.radixShift) : kInvalidRadixBin;
    if (participates) {
        digits[localID] = itemRadix;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint radix = 0; radix < kRadixBinCount; ++radix) {
        if (participates) {
            prefix[localID] = digits[localID] == radix ? 1u : 0u;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        for (uint offset = 1; offset < kRadixSortThreadCount; offset <<= 1) {
            uint value = 0;
            if (participates && localID >= offset) {
                value = prefix[localID - offset];
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
            if (participates) {
                prefix[localID] += value;
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }

        if (isValid && itemRadix == radix) {
            const uint localOffset = prefix[localID] - 1u;
            const uint destination = saturatingAdd(
                saturatingAdd(globalOffsets[radix], blockOffsets[radix * params.blockCount + blockID]),
                localOffset);
            if (destination < outputLimit) {
                dstDepthKeys[destination] = key;
                dstIndices[destination] = index;
            }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
}
