#pragma once

#include <cstddef>

namespace mesh2splat::metal {

std::size_t computeThreadgroupSize1D(void* computePipelineState, std::size_t preferredThreads = 256);

} // namespace mesh2splat::metal
