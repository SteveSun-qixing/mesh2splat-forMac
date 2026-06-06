#pragma once

#include "SceneData.hpp"

#include <cstdint>

namespace mesh2splat::core {

MeshData createPreviewTriangleMesh();
MeshData createCubeMesh(float size = 1.0f);
MeshData createPlaneMesh(float width = 2.0f, float depth = 2.0f);
MeshData createUvSphereMesh(float radius = 0.5f, uint32_t longitudeSegments = 32, uint32_t latitudeSegments = 16);
MeshData createFullscreenQuadMesh();
SceneData createPrimitivePreviewScene();

} // namespace mesh2splat::core
