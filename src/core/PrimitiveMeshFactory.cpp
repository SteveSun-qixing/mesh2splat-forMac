#include "PrimitiveMeshFactory.hpp"

namespace mesh2splat::core {

MeshData createPreviewTriangleMesh()
{
    MeshData mesh;
    mesh.name = "Preview Triangle";
    mesh.vertices.resize(3);

    mesh.vertices[0].position[0] = -0.65f;
    mesh.vertices[0].position[1] = -0.55f;
    mesh.vertices[0].uv[0] = 0.0f;
    mesh.vertices[0].uv[1] = 0.0f;
    mesh.vertices[0].normalizedUv[0] = 0.0f;
    mesh.vertices[0].normalizedUv[1] = 0.0f;

    mesh.vertices[1].position[0] = 0.65f;
    mesh.vertices[1].position[1] = -0.55f;
    mesh.vertices[1].uv[0] = 1.0f;
    mesh.vertices[1].uv[1] = 0.0f;
    mesh.vertices[1].normalizedUv[0] = 1.0f;
    mesh.vertices[1].normalizedUv[1] = 0.0f;

    mesh.vertices[2].position[0] = 0.0f;
    mesh.vertices[2].position[1] = 0.65f;
    mesh.vertices[2].uv[0] = 0.5f;
    mesh.vertices[2].uv[1] = 1.0f;
    mesh.vertices[2].normalizedUv[0] = 0.5f;
    mesh.vertices[2].normalizedUv[1] = 1.0f;

    mesh.materials.emplace_back();
    mesh.drawRanges.push_back(MeshDrawRange{0, 3, 0, 0.78f});
    mesh.bounds.min[0] = -0.65f;
    mesh.bounds.min[1] = -0.55f;
    mesh.bounds.max[0] = 0.65f;
    mesh.bounds.max[1] = 0.65f;
    mesh.surfaceArea = 0.78f;
    return mesh;
}

} // namespace mesh2splat::core
