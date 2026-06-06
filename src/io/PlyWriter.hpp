#pragma once

#include "core/GaussianData.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace mesh2splat::io {

enum class GaussianPlyFormat : uint32_t {
    Standard3DGS = 0,
    Pbr3DGS = 1,
    CompactPbr = 2,
};

struct GaussianPlyWriteOptions {
    GaussianPlyFormat format = GaussianPlyFormat::Standard3DGS;
    float scaleMultiplier = 1.0f;
    bool skipInvalidRecords = true;
};

struct GaussianPlyWriteResult {
    uint64_t requestedCount = 0;
    uint64_t writtenCount = 0;
    uint64_t skippedInvalidCount = 0;
    uint64_t headerByteCount = 0;
    uint64_t recordByteCount = 0;
    uint64_t outputByteCount = 0;
    GaussianPlyFormat format = GaussianPlyFormat::Standard3DGS;
    float effectiveScaleMultiplier = 1.0f;
    bool scaleMultiplierWasSanitized = false;
    std::string warning;
    std::string error;

    bool succeeded() const
    {
        return error.empty();
    }
};

bool writeGaussianPly(
    const std::string& filePath,
    const std::vector<core::GaussianRecord>& gaussians,
    const GaussianPlyWriteOptions& options = {},
    GaussianPlyWriteResult* result = nullptr);

} // namespace mesh2splat::io
