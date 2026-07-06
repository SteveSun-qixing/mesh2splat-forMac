#pragma once

#include "core/GaussianData.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace mesh2splat::io {

enum class GaussianPlyEncoding : uint32_t {
    Unknown = 0,
    Ascii = 1,
    BinaryLittleEndian = 2,
};

struct GaussianPlyReadOptions {
    float scaleMultiplier = 1.0f;
    bool skipInvalidRecords = true;
};

struct GaussianPlyReadResult {
    uint64_t vertexCount = 0;
    uint64_t readCount = 0;
    uint64_t skippedInvalidCount = 0;
    uint64_t headerByteCount = 0;
    uint64_t dataByteCount = 0;
    GaussianPlyEncoding encoding = GaussianPlyEncoding::Unknown;
    float effectiveScaleMultiplier = 1.0f;
    bool scaleMultiplierWasSanitized = false;
    std::string warning;
    std::string error;

    bool succeeded() const
    {
        return error.empty();
    }
};

bool readGaussianPly(
    const std::string& filePath,
    std::vector<core::GaussianRecord>& gaussians,
    const GaussianPlyReadOptions& options = {},
    GaussianPlyReadResult* result = nullptr);

} // namespace mesh2splat::io
