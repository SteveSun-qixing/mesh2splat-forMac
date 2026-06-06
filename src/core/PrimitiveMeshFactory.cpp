#include "PrimitiveMeshFactory.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace mesh2splat::core {
namespace {

constexpr float kPi = 3.14159265358979323846f;

struct Vec2 {
    float x = 0.0f;
    float y = 0.0f;
};

struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
};

Vec3 subtract(Vec3 lhs, Vec3 rhs)
{
    return Vec3{lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z};
}

Vec3 scale(Vec3 value, float multiplier)
{
    return Vec3{value.x * multiplier, value.y * multiplier, value.z * multiplier};
}

float dot(Vec3 lhs, Vec3 rhs)
{
    return lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z;
}

Vec3 cross(Vec3 lhs, Vec3 rhs)
{
    return Vec3{
        lhs.y * rhs.z - lhs.z * rhs.y,
        lhs.z * rhs.x - lhs.x * rhs.z,
        lhs.x * rhs.y - lhs.y * rhs.x,
    };
}

Vec3 normalize(Vec3 value, Vec3 fallback)
{
    const float lengthSquared = dot(value, value);
    if (lengthSquared <= 1.0e-12f) {
        return fallback;
    }

    return scale(value, 1.0f / std::sqrt(lengthSquared));
}

float triangleArea(Vec3 p0, Vec3 p1, Vec3 p2)
{
    const Vec3 areaVector = cross(subtract(p1, p0), subtract(p2, p0));
    return std::sqrt(dot(areaVector, areaVector)) * 0.5f;
}

float positiveOr(float value, float fallback)
{
    return value > 0.0f ? value : fallback;
}

MeshMaterial makeMaterial(float red, float green, float blue)
{
    MeshMaterial material;
    material.baseColorFactor[0] = red;
    material.baseColorFactor[1] = green;
    material.baseColorFactor[2] = blue;
    material.baseColorFactor[3] = 1.0f;
    material.metallicFactor = 0.0f;
    material.roughnessFactor = 0.72f;
    material.occlusionStrength = 1.0f;
    material.normalScale = 1.0f;
    return material;
}

MeshVertex makeVertex(Vec3 position, Vec3 normal, Vec3 tangent, Vec2 uv, float tangentW = 1.0f)
{
    MeshVertex vertex;
    vertex.position[0] = position.x;
    vertex.position[1] = position.y;
    vertex.position[2] = position.z;
    vertex.normal[0] = normal.x;
    vertex.normal[1] = normal.y;
    vertex.normal[2] = normal.z;
    vertex.tangent[0] = tangent.x;
    vertex.tangent[1] = tangent.y;
    vertex.tangent[2] = tangent.z;
    vertex.tangent[3] = tangentW;
    vertex.uv[0] = uv.x;
    vertex.uv[1] = uv.y;
    vertex.normalizedUv[0] = uv.x;
    vertex.normalizedUv[1] = uv.y;
    return vertex;
}

Vec3 vertexPosition(const MeshVertex& vertex)
{
    return Vec3{vertex.position[0], vertex.position[1], vertex.position[2]};
}

void updateBounds(MeshBounds& bounds, Vec3 position, bool& hasBounds)
{
    if (!hasBounds) {
        bounds.min[0] = position.x;
        bounds.min[1] = position.y;
        bounds.min[2] = position.z;
        bounds.max[0] = position.x;
        bounds.max[1] = position.y;
        bounds.max[2] = position.z;
        hasBounds = true;
        return;
    }

    bounds.min[0] = std::min(bounds.min[0], position.x);
    bounds.min[1] = std::min(bounds.min[1], position.y);
    bounds.min[2] = std::min(bounds.min[2], position.z);
    bounds.max[0] = std::max(bounds.max[0], position.x);
    bounds.max[1] = std::max(bounds.max[1], position.y);
    bounds.max[2] = std::max(bounds.max[2], position.z);
}

void appendTriangle(
    MeshData& mesh,
    const MeshVertex& vertex0,
    const MeshVertex& vertex1,
    const MeshVertex& vertex2,
    bool& hasBounds)
{
    const Vec3 position0 = vertexPosition(vertex0);
    const Vec3 position1 = vertexPosition(vertex1);
    const Vec3 position2 = vertexPosition(vertex2);

    updateBounds(mesh.bounds, position0, hasBounds);
    updateBounds(mesh.bounds, position1, hasBounds);
    updateBounds(mesh.bounds, position2, hasBounds);

    mesh.vertices.push_back(vertex0);
    mesh.vertices.push_back(vertex1);
    mesh.vertices.push_back(vertex2);
    mesh.surfaceArea += triangleArea(position0, position1, position2);
}

void appendQuad(
    MeshData& mesh,
    const std::array<Vec3, 4>& positions,
    Vec3 normal,
    Vec3 tangent,
    const std::array<Vec2, 4>& uvs,
    bool& hasBounds)
{
    const MeshVertex vertex0 = makeVertex(positions[0], normal, tangent, uvs[0]);
    const MeshVertex vertex1 = makeVertex(positions[1], normal, tangent, uvs[1]);
    const MeshVertex vertex2 = makeVertex(positions[2], normal, tangent, uvs[2]);
    const MeshVertex vertex3 = makeVertex(positions[3], normal, tangent, uvs[3]);

    appendTriangle(mesh, vertex0, vertex1, vertex2, hasBounds);
    appendTriangle(mesh, vertex0, vertex2, vertex3, hasBounds);
}

void appendDrawRange(MeshData& mesh)
{
    if (mesh.vertices.empty()) {
        return;
    }

    mesh.drawRanges.push_back(MeshDrawRange{0, static_cast<uint32_t>(mesh.vertices.size()), 0, mesh.surfaceArea});
}

void translateMesh(MeshData& mesh, Vec3 offset)
{
    if (mesh.empty()) {
        return;
    }

    for (MeshVertex& vertex : mesh.vertices) {
        vertex.position[0] += offset.x;
        vertex.position[1] += offset.y;
        vertex.position[2] += offset.z;
    }

    mesh.bounds.min[0] += offset.x;
    mesh.bounds.min[1] += offset.y;
    mesh.bounds.min[2] += offset.z;
    mesh.bounds.max[0] += offset.x;
    mesh.bounds.max[1] += offset.y;
    mesh.bounds.max[2] += offset.z;
}

Vec3 sphereNormal(float latitude, float longitude)
{
    const float phi = kPi * latitude;
    const float theta = 2.0f * kPi * longitude;
    const float sinPhi = std::sin(phi);
    return Vec3{
        sinPhi * std::cos(theta),
        std::cos(phi),
        sinPhi * std::sin(theta),
    };
}

MeshVertex sphereVertex(
    float radius,
    uint32_t longitudeIndex,
    uint32_t latitudeIndex,
    uint32_t longitudeSegments,
    uint32_t latitudeSegments)
{
    const float longitude = static_cast<float>(longitudeIndex) / static_cast<float>(longitudeSegments);
    const float latitude = static_cast<float>(latitudeIndex) / static_cast<float>(latitudeSegments);
    const float theta = 2.0f * kPi * longitude;
    const Vec3 normal = normalize(sphereNormal(latitude, longitude), Vec3{0.0f, 1.0f, 0.0f});
    const Vec3 tangent = normalize(Vec3{-std::sin(theta), 0.0f, std::cos(theta)}, Vec3{1.0f, 0.0f, 0.0f});
    return makeVertex(scale(normal, radius), normal, tangent, Vec2{longitude, latitude});
}

void replaceMaterial(MeshData& mesh, MeshMaterial material)
{
    mesh.materials.clear();
    mesh.materials.push_back(material);
}

} // namespace

MeshData createPreviewTriangleMesh()
{
    MeshData mesh;
    mesh.name = "Preview Triangle";
    mesh.materials.push_back(makeMaterial(0.86f, 0.9f, 1.0f));

    bool hasBounds = false;
    appendTriangle(
        mesh,
        makeVertex(Vec3{-0.65f, -0.55f, 0.0f}, Vec3{0.0f, 0.0f, 1.0f}, Vec3{1.0f, 0.0f, 0.0f}, Vec2{0.0f, 0.0f}),
        makeVertex(Vec3{0.65f, -0.55f, 0.0f}, Vec3{0.0f, 0.0f, 1.0f}, Vec3{1.0f, 0.0f, 0.0f}, Vec2{1.0f, 0.0f}),
        makeVertex(Vec3{0.0f, 0.65f, 0.0f}, Vec3{0.0f, 0.0f, 1.0f}, Vec3{1.0f, 0.0f, 0.0f}, Vec2{0.5f, 1.0f}),
        hasBounds);
    appendDrawRange(mesh);
    return mesh;
}

MeshData createCubeMesh(float size)
{
    const float halfSize = positiveOr(size, 1.0f) * 0.5f;

    MeshData mesh;
    mesh.name = "Primitive Cube";
    mesh.vertices.reserve(36);
    mesh.materials.push_back(makeMaterial(0.42f, 0.62f, 0.95f));

    const std::array<Vec2, 4> uvs{
        Vec2{0.0f, 0.0f},
        Vec2{1.0f, 0.0f},
        Vec2{1.0f, 1.0f},
        Vec2{0.0f, 1.0f},
    };
    const float h = halfSize;
    bool hasBounds = false;

    appendQuad(
        mesh,
        {Vec3{-h, -h, h}, Vec3{h, -h, h}, Vec3{h, h, h}, Vec3{-h, h, h}},
        Vec3{0.0f, 0.0f, 1.0f},
        Vec3{1.0f, 0.0f, 0.0f},
        uvs,
        hasBounds);
    appendQuad(
        mesh,
        {Vec3{h, -h, -h}, Vec3{-h, -h, -h}, Vec3{-h, h, -h}, Vec3{h, h, -h}},
        Vec3{0.0f, 0.0f, -1.0f},
        Vec3{-1.0f, 0.0f, 0.0f},
        uvs,
        hasBounds);
    appendQuad(
        mesh,
        {Vec3{h, -h, h}, Vec3{h, -h, -h}, Vec3{h, h, -h}, Vec3{h, h, h}},
        Vec3{1.0f, 0.0f, 0.0f},
        Vec3{0.0f, 0.0f, -1.0f},
        uvs,
        hasBounds);
    appendQuad(
        mesh,
        {Vec3{-h, -h, -h}, Vec3{-h, -h, h}, Vec3{-h, h, h}, Vec3{-h, h, -h}},
        Vec3{-1.0f, 0.0f, 0.0f},
        Vec3{0.0f, 0.0f, 1.0f},
        uvs,
        hasBounds);
    appendQuad(
        mesh,
        {Vec3{-h, h, h}, Vec3{h, h, h}, Vec3{h, h, -h}, Vec3{-h, h, -h}},
        Vec3{0.0f, 1.0f, 0.0f},
        Vec3{1.0f, 0.0f, 0.0f},
        uvs,
        hasBounds);
    appendQuad(
        mesh,
        {Vec3{-h, -h, -h}, Vec3{h, -h, -h}, Vec3{h, -h, h}, Vec3{-h, -h, h}},
        Vec3{0.0f, -1.0f, 0.0f},
        Vec3{1.0f, 0.0f, 0.0f},
        uvs,
        hasBounds);

    appendDrawRange(mesh);
    return mesh;
}

MeshData createPlaneMesh(float width, float depth)
{
    const float halfWidth = positiveOr(width, 2.0f) * 0.5f;
    const float halfDepth = positiveOr(depth, 2.0f) * 0.5f;

    MeshData mesh;
    mesh.name = "Primitive Plane";
    mesh.vertices.reserve(6);
    mesh.materials.push_back(makeMaterial(0.72f, 0.76f, 0.7f));

    bool hasBounds = false;
    appendQuad(
        mesh,
        {
            Vec3{-halfWidth, 0.0f, -halfDepth},
            Vec3{-halfWidth, 0.0f, halfDepth},
            Vec3{halfWidth, 0.0f, halfDepth},
            Vec3{halfWidth, 0.0f, -halfDepth},
        },
        Vec3{0.0f, 1.0f, 0.0f},
        Vec3{1.0f, 0.0f, 0.0f},
        {Vec2{0.0f, 0.0f}, Vec2{0.0f, 1.0f}, Vec2{1.0f, 1.0f}, Vec2{1.0f, 0.0f}},
        hasBounds);

    appendDrawRange(mesh);
    return mesh;
}

MeshData createUvSphereMesh(float radius, uint32_t longitudeSegments, uint32_t latitudeSegments)
{
    const float resolvedRadius = positiveOr(radius, 0.5f);
    const uint32_t longitudes = std::clamp(longitudeSegments, 3u, 512u);
    const uint32_t latitudes = std::clamp(latitudeSegments, 2u, 256u);

    MeshData mesh;
    mesh.name = "Primitive UV Sphere";
    mesh.vertices.reserve(static_cast<std::size_t>(longitudes) * static_cast<std::size_t>(latitudes) * 6);
    mesh.materials.push_back(makeMaterial(0.95f, 0.62f, 0.34f));

    bool hasBounds = false;
    for (uint32_t latitude = 0; latitude < latitudes; ++latitude) {
        for (uint32_t longitude = 0; longitude < longitudes; ++longitude) {
            const uint32_t nextLongitude = longitude + 1;
            const uint32_t nextLatitude = latitude + 1;

            const MeshVertex vertex00 = sphereVertex(resolvedRadius, longitude, latitude, longitudes, latitudes);
            const MeshVertex vertex01 = sphereVertex(resolvedRadius, nextLongitude, latitude, longitudes, latitudes);
            const MeshVertex vertex10 = sphereVertex(resolvedRadius, longitude, nextLatitude, longitudes, latitudes);
            const MeshVertex vertex11 = sphereVertex(resolvedRadius, nextLongitude, nextLatitude, longitudes, latitudes);

            if (latitude == 0) {
                appendTriangle(mesh, vertex00, vertex11, vertex10, hasBounds);
            } else if (nextLatitude == latitudes) {
                appendTriangle(mesh, vertex00, vertex01, vertex11, hasBounds);
            } else {
                appendTriangle(mesh, vertex00, vertex01, vertex11, hasBounds);
                appendTriangle(mesh, vertex00, vertex11, vertex10, hasBounds);
            }
        }
    }

    appendDrawRange(mesh);
    return mesh;
}

MeshData createFullscreenQuadMesh()
{
    MeshData mesh;
    mesh.name = "Primitive Fullscreen Quad";
    mesh.vertices.reserve(6);
    mesh.materials.push_back(makeMaterial(1.0f, 1.0f, 1.0f));

    bool hasBounds = false;
    appendQuad(
        mesh,
        {Vec3{-1.0f, -1.0f, 0.0f}, Vec3{1.0f, -1.0f, 0.0f}, Vec3{1.0f, 1.0f, 0.0f}, Vec3{-1.0f, 1.0f, 0.0f}},
        Vec3{0.0f, 0.0f, 1.0f},
        Vec3{1.0f, 0.0f, 0.0f},
        {Vec2{0.0f, 0.0f}, Vec2{1.0f, 0.0f}, Vec2{1.0f, 1.0f}, Vec2{0.0f, 1.0f}},
        hasBounds);

    appendDrawRange(mesh);
    return mesh;
}

SceneData createPrimitivePreviewScene()
{
    SceneData scene;
    scene.name = "Primitive Preview Scene";

    MeshData plane = createPlaneMesh(3.25f, 2.6f);
    plane.name = "Preview Plane";
    replaceMaterial(plane, makeMaterial(0.55f, 0.58f, 0.52f));
    scene.meshes.push_back(plane);

    MeshData cube = createCubeMesh(0.72f);
    cube.name = "Preview Cube";
    translateMesh(cube, Vec3{-0.72f, 0.36f, 0.0f});
    scene.meshes.push_back(cube);

    MeshData sphere = createUvSphereMesh(0.42f, 32, 16);
    sphere.name = "Preview UV Sphere";
    translateMesh(sphere, Vec3{0.72f, 0.42f, 0.0f});
    scene.meshes.push_back(sphere);

    scene.bounds = aggregateSceneBounds(scene);
    scene.rebuildReferences();
    return scene;
}

} // namespace mesh2splat::core
