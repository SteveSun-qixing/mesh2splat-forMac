#include "GltfMeshLoader.hpp"

#include "tiny_gltf.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <functional>
#include <iterator>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::core {
namespace {

struct Vec2 {
    float x = 0.0f;
    float y = 0.0f;
};

struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
};

struct Vec4 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
    float w = 1.0f;
};

struct Mat4 {
    float m[16] = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f,
    };
};

struct MeshInstance {
    int meshIndex = -1;
    Mat4 transform;
};

Vec3 add(Vec3 lhs, Vec3 rhs)
{
    return Vec3{lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z};
}

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

Vec3 normalize(Vec3 value)
{
    const float length = std::sqrt(dot(value, value));
    return length <= 0.000001f ? Vec3{0.0f, 1.0f, 0.0f} : scale(value, 1.0f / length);
}

Mat4 multiply(const Mat4& lhs, const Mat4& rhs)
{
    Mat4 result;
    std::fill(std::begin(result.m), std::end(result.m), 0.0f);

    for (int column = 0; column < 4; ++column) {
        for (int row = 0; row < 4; ++row) {
            for (int index = 0; index < 4; ++index) {
                result.m[column * 4 + row] += lhs.m[index * 4 + row] * rhs.m[column * 4 + index];
            }
        }
    }

    return result;
}

Mat4 translationMatrix(const std::vector<double>& translation)
{
    Mat4 matrix;
    if (translation.size() == 3) {
        matrix.m[12] = static_cast<float>(translation[0]);
        matrix.m[13] = static_cast<float>(translation[1]);
        matrix.m[14] = static_cast<float>(translation[2]);
    }
    return matrix;
}

Mat4 scaleMatrix(const std::vector<double>& scale)
{
    Mat4 matrix;
    if (scale.size() == 3) {
        matrix.m[0] = static_cast<float>(scale[0]);
        matrix.m[5] = static_cast<float>(scale[1]);
        matrix.m[10] = static_cast<float>(scale[2]);
    }
    return matrix;
}

Mat4 rotationMatrix(const std::vector<double>& rotation)
{
    Mat4 matrix;
    if (rotation.size() != 4) {
        return matrix;
    }

    const float x = static_cast<float>(rotation[0]);
    const float y = static_cast<float>(rotation[1]);
    const float z = static_cast<float>(rotation[2]);
    const float w = static_cast<float>(rotation[3]);
    const float xx = x * x;
    const float yy = y * y;
    const float zz = z * z;
    const float xy = x * y;
    const float xz = x * z;
    const float yz = y * z;
    const float wx = w * x;
    const float wy = w * y;
    const float wz = w * z;

    matrix.m[0] = 1.0f - 2.0f * (yy + zz);
    matrix.m[1] = 2.0f * (xy + wz);
    matrix.m[2] = 2.0f * (xz - wy);
    matrix.m[4] = 2.0f * (xy - wz);
    matrix.m[5] = 1.0f - 2.0f * (xx + zz);
    matrix.m[6] = 2.0f * (yz + wx);
    matrix.m[8] = 2.0f * (xz + wy);
    matrix.m[9] = 2.0f * (yz - wx);
    matrix.m[10] = 1.0f - 2.0f * (xx + yy);
    return matrix;
}

Mat4 nodeLocalTransform(const tinygltf::Node& node)
{
    if (node.matrix.size() == 16) {
        Mat4 matrix;
        for (std::size_t i = 0; i < 16; ++i) {
            matrix.m[i] = static_cast<float>(node.matrix[i]);
        }
        return matrix;
    }

    return multiply(translationMatrix(node.translation), multiply(rotationMatrix(node.rotation), scaleMatrix(node.scale)));
}

Vec3 transformPoint(const Mat4& matrix, Vec3 point)
{
    return Vec3{
        matrix.m[0] * point.x + matrix.m[4] * point.y + matrix.m[8] * point.z + matrix.m[12],
        matrix.m[1] * point.x + matrix.m[5] * point.y + matrix.m[9] * point.z + matrix.m[13],
        matrix.m[2] * point.x + matrix.m[6] * point.y + matrix.m[10] * point.z + matrix.m[14],
    };
}

Vec3 transformVector(const Mat4& matrix, Vec3 vector)
{
    return Vec3{
        matrix.m[0] * vector.x + matrix.m[4] * vector.y + matrix.m[8] * vector.z,
        matrix.m[1] * vector.x + matrix.m[5] * vector.y + matrix.m[9] * vector.z,
        matrix.m[2] * vector.x + matrix.m[6] * vector.y + matrix.m[10] * vector.z,
    };
}

bool endsWithCaseInsensitive(const std::string& value, const std::string& suffix)
{
    if (value.size() < suffix.size()) {
        return false;
    }

    return std::equal(suffix.rbegin(), suffix.rend(), value.rbegin(), [](char lhs, char rhs) {
        return std::tolower(static_cast<unsigned char>(lhs)) == std::tolower(static_cast<unsigned char>(rhs));
    });
}

const unsigned char* accessorData(
    const tinygltf::Model& model,
    const tinygltf::Accessor& accessor,
    const tinygltf::BufferView*& bufferView,
    int& stride)
{
    if (accessor.bufferView < 0 || accessor.bufferView >= static_cast<int>(model.bufferViews.size())) {
        return nullptr;
    }

    bufferView = &model.bufferViews[accessor.bufferView];
    if (bufferView->buffer < 0 || bufferView->buffer >= static_cast<int>(model.buffers.size())) {
        return nullptr;
    }

    stride = accessor.ByteStride(*bufferView);
    if (stride <= 0) {
        return nullptr;
    }

    const tinygltf::Buffer& buffer = model.buffers[bufferView->buffer];
    const std::size_t offset = bufferView->byteOffset + accessor.byteOffset;
    if (offset >= buffer.data.size()) {
        return nullptr;
    }

    return buffer.data.data() + offset;
}

bool accessorRangeValid(
    const tinygltf::Model& model,
    const tinygltf::Accessor& accessor,
    const tinygltf::BufferView& bufferView,
    int stride)
{
    if (accessor.count == 0) {
        return false;
    }

    const tinygltf::Buffer& buffer = model.buffers[bufferView.buffer];
    const std::size_t offset = bufferView.byteOffset + accessor.byteOffset;
    const std::size_t required = offset + static_cast<std::size_t>(stride) * (accessor.count - 1) +
        tinygltf::GetComponentSizeInBytes(static_cast<uint32_t>(accessor.componentType)) *
            tinygltf::GetNumComponentsInType(static_cast<uint32_t>(accessor.type));
    return required <= buffer.data.size();
}

bool readFloatAccessor(
    const tinygltf::Model& model,
    int accessorIndex,
    int expectedType,
    std::vector<std::array<float, 4>>& values)
{
    if (accessorIndex < 0 || accessorIndex >= static_cast<int>(model.accessors.size())) {
        return false;
    }

    const tinygltf::Accessor& accessor = model.accessors[accessorIndex];
    if (accessor.componentType != TINYGLTF_COMPONENT_TYPE_FLOAT || accessor.type != expectedType) {
        return false;
    }

    const tinygltf::BufferView* bufferView = nullptr;
    int stride = 0;
    const unsigned char* data = accessorData(model, accessor, bufferView, stride);
    if (data == nullptr || bufferView == nullptr || !accessorRangeValid(model, accessor, *bufferView, stride)) {
        return false;
    }

    const int componentCount = tinygltf::GetNumComponentsInType(static_cast<uint32_t>(accessor.type));
    values.resize(accessor.count);
    for (std::size_t i = 0; i < accessor.count; ++i) {
        const float* source = reinterpret_cast<const float*>(data + stride * i);
        values[i] = {0.0f, 0.0f, 0.0f, 1.0f};
        for (int component = 0; component < componentCount; ++component) {
            values[i][component] = source[component];
        }
    }

    return true;
}

bool readIndices(const tinygltf::Model& model, int accessorIndex, std::vector<uint32_t>& indices)
{
    if (accessorIndex < 0 || accessorIndex >= static_cast<int>(model.accessors.size())) {
        return false;
    }

    const tinygltf::Accessor& accessor = model.accessors[accessorIndex];
    if (accessor.type != TINYGLTF_TYPE_SCALAR) {
        return false;
    }

    const tinygltf::BufferView* bufferView = nullptr;
    int stride = 0;
    const unsigned char* data = accessorData(model, accessor, bufferView, stride);
    if (data == nullptr || bufferView == nullptr || !accessorRangeValid(model, accessor, *bufferView, stride)) {
        return false;
    }

    indices.resize(accessor.count);
    for (std::size_t i = 0; i < accessor.count; ++i) {
        const unsigned char* source = data + stride * i;
        switch (accessor.componentType) {
        case TINYGLTF_COMPONENT_TYPE_UNSIGNED_BYTE:
            indices[i] = *source;
            break;
        case TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT: {
            uint16_t value = 0;
            std::memcpy(&value, source, sizeof(value));
            indices[i] = value;
            break;
        }
        case TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT: {
            uint32_t value = 0;
            std::memcpy(&value, source, sizeof(value));
            indices[i] = value;
            break;
        }
        default:
            return false;
        }
    }

    return true;
}

MeshMaterial parseMaterial(const tinygltf::Model& model, int materialIndex)
{
    MeshMaterial material;
    if (materialIndex < 0 || materialIndex >= static_cast<int>(model.materials.size())) {
        return material;
    }

    const tinygltf::Material& gltfMaterial = model.materials[materialIndex];
    const std::vector<double>& baseColor = gltfMaterial.pbrMetallicRoughness.baseColorFactor;
    if (baseColor.size() == 4) {
        for (std::size_t i = 0; i < 4; ++i) {
            material.baseColorFactor[i] = static_cast<float>(baseColor[i]);
        }
    }

    if (gltfMaterial.emissiveFactor.size() == 3) {
        for (std::size_t i = 0; i < 3; ++i) {
            material.emissiveFactor[i] = static_cast<float>(gltfMaterial.emissiveFactor[i]);
        }
    }

    material.metallicFactor = static_cast<float>(gltfMaterial.pbrMetallicRoughness.metallicFactor);
    material.roughnessFactor = static_cast<float>(gltfMaterial.pbrMetallicRoughness.roughnessFactor);
    material.occlusionStrength = gltfMaterial.occlusionTexture.index >= 0 ?
        static_cast<float>(gltfMaterial.occlusionTexture.strength) : 1.0f;
    material.normalScale = gltfMaterial.normalTexture.index >= 0 ?
        static_cast<float>(gltfMaterial.normalTexture.scale) : 1.0f;
    return material;
}

int32_t appendTextureImage(const tinygltf::Model& model, int textureIndex, MeshData& mesh)
{
    if (textureIndex < 0 || textureIndex >= static_cast<int>(model.textures.size())) {
        return -1;
    }

    const tinygltf::Texture& texture = model.textures[textureIndex];
    if (texture.source < 0 || texture.source >= static_cast<int>(model.images.size())) {
        return -1;
    }

    const tinygltf::Image& image = model.images[texture.source];
    if (image.width <= 0 || image.height <= 0 || image.component <= 0 || image.image.empty()) {
        return -1;
    }

    const std::size_t pixelCount = static_cast<std::size_t>(image.width) * static_cast<std::size_t>(image.height);
    const std::size_t sourceStride = static_cast<std::size_t>(image.component);
    if (image.image.size() < pixelCount * sourceStride) {
        return -1;
    }

    MeshImageData meshImage;
    meshImage.name = image.name.empty() ? ("texture_" + std::to_string(textureIndex)) : image.name;
    meshImage.width = static_cast<uint32_t>(image.width);
    meshImage.height = static_cast<uint32_t>(image.height);
    meshImage.channels = 4;
    meshImage.rgba8.resize(pixelCount * 4);

    for (std::size_t pixel = 0; pixel < pixelCount; ++pixel) {
        const unsigned char* source = image.image.data() + pixel * sourceStride;
        uint8_t* destination = meshImage.rgba8.data() + pixel * 4;
        destination[0] = source[0];
        destination[1] = sourceStride > 1 ? source[1] : source[0];
        destination[2] = sourceStride > 2 ? source[2] : source[0];
        destination[3] = sourceStride > 3 ? source[3] : 255;
    }

    mesh.images.push_back(std::move(meshImage));
    return static_cast<int32_t>(mesh.images.size() - 1);
}

float triangleArea(Vec3 a, Vec3 b, Vec3 c)
{
    return 0.5f * std::sqrt(dot(cross(subtract(b, a), subtract(c, a)), cross(subtract(b, a), subtract(c, a))));
}

void updateBounds(MeshBounds& bounds, Vec3 point, bool& hasBounds)
{
    if (!hasBounds) {
        bounds.min[0] = bounds.max[0] = point.x;
        bounds.min[1] = bounds.max[1] = point.y;
        bounds.min[2] = bounds.max[2] = point.z;
        hasBounds = true;
        return;
    }

    bounds.min[0] = std::min(bounds.min[0], point.x);
    bounds.min[1] = std::min(bounds.min[1], point.y);
    bounds.min[2] = std::min(bounds.min[2], point.z);
    bounds.max[0] = std::max(bounds.max[0], point.x);
    bounds.max[1] = std::max(bounds.max[1], point.y);
    bounds.max[2] = std::max(bounds.max[2], point.z);
}

std::vector<MeshInstance> collectMeshInstances(const tinygltf::Model& model)
{
    std::vector<MeshInstance> instances;
    std::function<void(int, const Mat4&)> traverse = [&](int nodeIndex, const Mat4& parentTransform) {
        if (nodeIndex < 0 || nodeIndex >= static_cast<int>(model.nodes.size())) {
            return;
        }

        const tinygltf::Node& node = model.nodes[nodeIndex];
        const Mat4 worldTransform = multiply(parentTransform, nodeLocalTransform(node));
        if (node.mesh >= 0 && node.mesh < static_cast<int>(model.meshes.size())) {
            instances.push_back(MeshInstance{node.mesh, worldTransform});
        }

        for (int child : node.children) {
            traverse(child, worldTransform);
        }
    };

    if (!model.scenes.empty()) {
        const int sceneIndex = model.defaultScene >= 0 ? model.defaultScene : 0;
        for (int rootNode : model.scenes[sceneIndex].nodes) {
            traverse(rootNode, Mat4{});
        }
    }

    if (instances.empty()) {
        for (int meshIndex = 0; meshIndex < static_cast<int>(model.meshes.size()); ++meshIndex) {
            instances.push_back(MeshInstance{meshIndex, Mat4{}});
        }
    }

    return instances;
}

bool appendPrimitive(
    const tinygltf::Model& model,
    const tinygltf::Mesh& gltfMesh,
    const tinygltf::Primitive& primitive,
    const Mat4& transform,
    int meshIndex,
    int primitiveIndex,
    MeshData& mesh)
{
    if (primitive.mode != TINYGLTF_MODE_TRIANGLES && primitive.mode != -1) {
        return false;
    }

    const auto positionIt = primitive.attributes.find("POSITION");
    if (positionIt == primitive.attributes.end()) {
        return false;
    }

    std::vector<std::array<float, 4>> positions;
    if (!readFloatAccessor(model, positionIt->second, TINYGLTF_TYPE_VEC3, positions)) {
        return false;
    }

    std::vector<std::array<float, 4>> normals;
    const auto normalIt = primitive.attributes.find("NORMAL");
    const bool hasNormals = normalIt != primitive.attributes.end() &&
        readFloatAccessor(model, normalIt->second, TINYGLTF_TYPE_VEC3, normals) &&
        normals.size() == positions.size();

    std::vector<std::array<float, 4>> tangents;
    const auto tangentIt = primitive.attributes.find("TANGENT");
    const bool hasTangents = tangentIt != primitive.attributes.end() &&
        readFloatAccessor(model, tangentIt->second, TINYGLTF_TYPE_VEC4, tangents) &&
        tangents.size() == positions.size();

    std::vector<std::array<float, 4>> uvs;
    const auto uvIt = primitive.attributes.find("TEXCOORD_0");
    const bool hasUvs = uvIt != primitive.attributes.end() &&
        readFloatAccessor(model, uvIt->second, TINYGLTF_TYPE_VEC2, uvs) &&
        uvs.size() == positions.size();

    std::vector<uint32_t> indices;
    if (primitive.indices >= 0) {
        if (!readIndices(model, primitive.indices, indices)) {
            return false;
        }
    } else {
        if (positions.size() > static_cast<std::size_t>(std::numeric_limits<uint32_t>::max())) {
            return false;
        }
        indices.resize(positions.size());
        for (std::size_t i = 0; i < positions.size(); ++i) {
            indices[i] = static_cast<uint32_t>(i);
        }
    }

    if (indices.size() < 3 || indices.size() % 3 != 0) {
        return false;
    }

    MeshMaterial material = parseMaterial(model, primitive.material);
    if (primitive.material >= 0 && primitive.material < static_cast<int>(model.materials.size())) {
        const tinygltf::Material& gltfMaterial = model.materials[primitive.material];
        material.baseColorTextureIndex =
            appendTextureImage(model, gltfMaterial.pbrMetallicRoughness.baseColorTexture.index, mesh);
        material.metallicRoughnessTextureIndex =
            appendTextureImage(model, gltfMaterial.pbrMetallicRoughness.metallicRoughnessTexture.index, mesh);
        material.normalTextureIndex = appendTextureImage(model, gltfMaterial.normalTexture.index, mesh);
        material.occlusionTextureIndex = appendTextureImage(model, gltfMaterial.occlusionTexture.index, mesh);
        material.emissiveTextureIndex = appendTextureImage(model, gltfMaterial.emissiveTexture.index, mesh);
    }

    const uint32_t materialIndex = static_cast<uint32_t>(mesh.materials.size());
    mesh.materials.push_back(material);
    const uint32_t vertexOffset = static_cast<uint32_t>(mesh.vertices.size());
    float primitiveSurfaceArea = 0.0f;
    bool hasBounds = !mesh.vertices.empty();
    if (hasBounds) {
        hasBounds = true;
    }

    for (std::size_t triangle = 0; triangle < indices.size(); triangle += 3) {
        const uint32_t index0 = indices[triangle];
        const uint32_t index1 = indices[triangle + 1];
        const uint32_t index2 = indices[triangle + 2];
        if (index0 >= positions.size() || index1 >= positions.size() || index2 >= positions.size()) {
            return false;
        }

        const std::array<uint32_t, 3> triangleIndices{index0, index1, index2};
        Vec3 worldPositions[3];
        for (int corner = 0; corner < 3; ++corner) {
            const auto& position = positions[triangleIndices[corner]];
            worldPositions[corner] = transformPoint(transform, Vec3{position[0], position[1], position[2]});
        }

        const Vec3 faceNormal = normalize(cross(
            subtract(worldPositions[1], worldPositions[0]),
            subtract(worldPositions[2], worldPositions[0])));
        Vec3 tangent = Vec3{1.0f, 0.0f, 0.0f};
        float tangentW = 1.0f;

        if (!hasTangents) {
            const Vec2 uv0 = hasUvs ? Vec2{uvs[index0][0], uvs[index0][1]} : Vec2{};
            const Vec2 uv1 = hasUvs ? Vec2{uvs[index1][0], uvs[index1][1]} : Vec2{};
            const Vec2 uv2 = hasUvs ? Vec2{uvs[index2][0], uvs[index2][1]} : Vec2{};
            const Vec3 dp1 = subtract(worldPositions[1], worldPositions[0]);
            const Vec3 dp2 = subtract(worldPositions[2], worldPositions[0]);
            const Vec2 duv1{uv1.x - uv0.x, uv1.y - uv0.y};
            const Vec2 duv2{uv2.x - uv0.x, uv2.y - uv0.y};
            float determinant = duv1.x * duv2.y - duv1.y * duv2.x;
            determinant = std::fabs(determinant) < 0.000001f ? 1.0f : determinant;
            tangent = normalize(scale(subtract(scale(dp1, duv2.y), scale(dp2, duv1.y)), 1.0f / determinant));
        }

        for (int corner = 0; corner < 3; ++corner) {
            const uint32_t sourceIndex = triangleIndices[corner];
            MeshVertex vertex;
            vertex.position[0] = worldPositions[corner].x;
            vertex.position[1] = worldPositions[corner].y;
            vertex.position[2] = worldPositions[corner].z;

            const Vec3 normal = hasNormals ?
                normalize(transformVector(transform, Vec3{normals[sourceIndex][0], normals[sourceIndex][1], normals[sourceIndex][2]})) :
                faceNormal;
            vertex.normal[0] = normal.x;
            vertex.normal[1] = normal.y;
            vertex.normal[2] = normal.z;

            if (hasTangents) {
                const Vec3 transformedTangent = normalize(transformVector(
                    transform,
                    Vec3{tangents[sourceIndex][0], tangents[sourceIndex][1], tangents[sourceIndex][2]}));
                vertex.tangent[0] = transformedTangent.x;
                vertex.tangent[1] = transformedTangent.y;
                vertex.tangent[2] = transformedTangent.z;
                vertex.tangent[3] = tangents[sourceIndex][3];
            } else {
                vertex.tangent[0] = tangent.x;
                vertex.tangent[1] = tangent.y;
                vertex.tangent[2] = tangent.z;
                vertex.tangent[3] = tangentW;
            }

            if (hasUvs) {
                vertex.uv[0] = uvs[sourceIndex][0];
                vertex.uv[1] = uvs[sourceIndex][1];
                vertex.normalizedUv[0] = vertex.uv[0];
                vertex.normalizedUv[1] = vertex.uv[1];
            }

            updateBounds(mesh.bounds, worldPositions[corner], hasBounds);
            mesh.vertices.push_back(vertex);
        }

        primitiveSurfaceArea += triangleArea(worldPositions[0], worldPositions[1], worldPositions[2]);
    }

    mesh.surfaceArea += primitiveSurfaceArea;
    const uint32_t vertexCount = static_cast<uint32_t>(mesh.vertices.size() - vertexOffset);
    mesh.drawRanges.push_back(MeshDrawRange{vertexOffset, vertexCount, materialIndex, primitiveSurfaceArea});
    if (mesh.name.empty()) {
        const std::string baseName = gltfMesh.name.empty() ? "mesh" : gltfMesh.name;
        mesh.name = baseName + "_" + std::to_string(meshIndex) + "_" + std::to_string(primitiveIndex);
    }

    return vertexCount > 0;
}

} // namespace

bool loadGltfMeshData(const std::string& filePath, GltfMeshLoadResult& result)
{
    result = {};
    if (filePath.empty()) {
        result.error = "glTF path is empty.";
        return false;
    }

    tinygltf::Model model;
    tinygltf::TinyGLTF loader;
    const bool loaded = endsWithCaseInsensitive(filePath, ".gltf") ?
        loader.LoadASCIIFromFile(&model, &result.error, &result.warning, filePath) :
        loader.LoadBinaryFromFile(&model, &result.error, &result.warning, filePath);
    if (!loaded) {
        if (result.error.empty()) {
            result.error = "Failed to load glTF file: " + filePath;
        }
        return false;
    }

    const std::vector<MeshInstance> instances = collectMeshInstances(model);
    int primitiveIndex = 0;
    for (const MeshInstance& instance : instances) {
        if (instance.meshIndex < 0 || instance.meshIndex >= static_cast<int>(model.meshes.size())) {
            continue;
        }

        const tinygltf::Mesh& gltfMesh = model.meshes[instance.meshIndex];
        for (const tinygltf::Primitive& primitive : gltfMesh.primitives) {
            MeshData mesh;
            if (appendPrimitive(model, gltfMesh, primitive, instance.transform, instance.meshIndex, primitiveIndex, mesh)) {
                result.scene.meshes.push_back(std::move(mesh));
            }
            ++primitiveIndex;
        }
    }

    if (result.scene.meshes.empty()) {
        result.error = "No triangle mesh data was found in glTF file: " + filePath;
        return false;
    }

    result.scene.name = filePath;
    result.scene.bounds = aggregateSceneBounds(result.scene);
    return true;
}

} // namespace mesh2splat::core
