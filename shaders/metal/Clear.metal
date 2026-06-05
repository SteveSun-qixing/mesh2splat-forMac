#include <metal_stdlib>

using namespace metal;

struct ClearVertexOut {
    float4 position [[position]];
};

vertex ClearVertexOut clearVertex(uint vertexID [[vertex_id]])
{
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0),
    };

    ClearVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    return out;
}

fragment float4 clearFragment()
{
    return float4(0.03, 0.04, 0.05, 1.0);
}
