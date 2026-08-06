#pragma once

#include <cstdint>
#include <string_view>

namespace mesh2splat::metal::bindings {

using BindingIndex = std::uint32_t;

namespace functions {

inline constexpr std::string_view kMeshVertex = "meshVertex";
inline constexpr std::string_view kMeshFragment = "meshFragment";
inline constexpr std::string_view kGaussianPreviewVertex = "gaussianPreviewVertex";
inline constexpr std::string_view kGaussianPreviewFragment = "gaussianPreviewFragment";
inline constexpr std::string_view kMeshVertexConversionKernel = "meshVertexConversionKernel";
inline constexpr std::string_view kGaussianDepthKeyKernel = "gaussianDepthKeyKernel";
inline constexpr std::string_view kGaussianRadixCountKernel = "gaussianRadixCountKernel";
inline constexpr std::string_view kGaussianRadixPrefixKernel = "gaussianRadixPrefixKernel";
inline constexpr std::string_view kGaussianRadixReorderKernel = "gaussianRadixReorderKernel";

} // namespace functions

namespace material_textures {

inline constexpr BindingIndex kBaseColor = 0;
inline constexpr BindingIndex kMetallicRoughness = 1;
inline constexpr BindingIndex kNormal = 2;
inline constexpr BindingIndex kOcclusion = 3;
inline constexpr BindingIndex kEmissive = 4;
inline constexpr BindingIndex kShadowDistance = 5;

} // namespace material_textures

namespace mesh {

namespace vertex_buffers {

inline constexpr BindingIndex kVertices = 0;
inline constexpr BindingIndex kFrameUniforms = 1;

} // namespace vertex_buffers

namespace fragment_buffers {

inline constexpr BindingIndex kMaterials = 0;
inline constexpr BindingIndex kMaterialIndex = 1;
inline constexpr BindingIndex kFrameUniforms = 2;

} // namespace fragment_buffers

namespace fragment_samplers {

inline constexpr BindingIndex kMaterialTextures = 0;

} // namespace fragment_samplers

} // namespace mesh

namespace gaussian_preview {

namespace vertex_buffers {

inline constexpr BindingIndex kGaussians = 0;
inline constexpr BindingIndex kFrameUniforms = 1;
inline constexpr BindingIndex kGaussianIndices = 2;

} // namespace vertex_buffers

namespace fragment_buffers {

inline constexpr BindingIndex kFrameUniforms = 0;

} // namespace fragment_buffers

} // namespace gaussian_preview

namespace mesh_conversion {

namespace buffers {

inline constexpr BindingIndex kVertices = 0;
inline constexpr BindingIndex kMaterials = 1;
inline constexpr BindingIndex kGaussians = 2;
inline constexpr BindingIndex kParams = 3;
inline constexpr BindingIndex kGaussianCounter = 4;

} // namespace buffers

namespace samplers {

inline constexpr BindingIndex kMaterialTextures = 0;

} // namespace samplers

} // namespace mesh_conversion

namespace gaussian_sort {

namespace depth_key_buffers {

inline constexpr BindingIndex kGaussians = 0;
inline constexpr BindingIndex kFrameUniforms = 1;
inline constexpr BindingIndex kDepthKeys = 2;
inline constexpr BindingIndex kIndices = 3;
inline constexpr BindingIndex kParams = 4;

} // namespace depth_key_buffers

namespace radix_count_buffers {

inline constexpr BindingIndex kDepthKeys = 0;
inline constexpr BindingIndex kBlockCounts = 1;
inline constexpr BindingIndex kGlobalOffsets = 2;
inline constexpr BindingIndex kParams = 3;

} // namespace radix_count_buffers

namespace radix_prefix_buffers {

inline constexpr BindingIndex kBlockCounts = 0;
inline constexpr BindingIndex kGlobalOffsets = 1;
inline constexpr BindingIndex kParams = 2;

} // namespace radix_prefix_buffers

namespace radix_reorder_buffers {

inline constexpr BindingIndex kSourceDepthKeys = 0;
inline constexpr BindingIndex kSourceIndices = 1;
inline constexpr BindingIndex kDestinationDepthKeys = 2;
inline constexpr BindingIndex kDestinationIndices = 3;
inline constexpr BindingIndex kBlockOffsets = 4;
inline constexpr BindingIndex kGlobalOffsets = 5;
inline constexpr BindingIndex kParams = 6;

} // namespace radix_reorder_buffers

} // namespace gaussian_sort

} // namespace mesh2splat::metal::bindings
