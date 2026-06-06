#include "io/PlyWriter.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <limits>
#include <string>

namespace mesh2splat::io {
namespace {

constexpr float kDefaultPlyScaleMultiplier = 1.0f;

bool isBlank(const std::string& value)
{
    return std::all_of(value.begin(), value.end(), [](char character) {
        return std::isspace(static_cast<unsigned char>(character)) != 0;
    });
}

bool hasPathFilename(const std::string& filePath)
{
    const std::size_t separator = filePath.find_last_of("/\\");
    return separator == std::string::npos || separator + 1 < filePath.size();
}

std::string parentPath(const std::string& filePath)
{
    const std::size_t separator = filePath.find_last_of("/\\");
    if (separator == std::string::npos) {
        return {};
    }
    if (separator == 0) {
        return filePath.substr(0, 1);
    }
    return filePath.substr(0, separator);
}

bool directoryExists(const std::string& path)
{
    std::error_code error;
    return std::filesystem::is_directory(path, error) && !error;
}

std::string lowerExtension(const std::string& filePath)
{
    const std::size_t separator = filePath.find_last_of("/\\");
    const std::size_t dot = filePath.find_last_of('.');
    if (dot == std::string::npos || dot + 1 >= filePath.size() ||
        (separator != std::string::npos && dot < separator)) {
        return {};
    }

    std::string extension = filePath.substr(dot);
    std::transform(extension.begin(), extension.end(), extension.begin(), [](char character) {
        return static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
    });
    return extension;
}

void appendWarning(GaussianPlyWriteResult& result, const std::string& warning)
{
    if (warning.empty()) {
        return;
    }

    if (!result.warning.empty() && result.warning.back() != '\n') {
        result.warning.push_back('\n');
    }
    result.warning += warning;
}

bool isSupportedFormat(GaussianPlyFormat format)
{
    switch (format) {
    case GaussianPlyFormat::Standard3DGS:
    case GaussianPlyFormat::Pbr3DGS:
    case GaussianPlyFormat::CompactPbr:
        return true;
    default:
        return false;
    }
}

uint64_t recordByteSize(GaussianPlyFormat format)
{
    switch (format) {
    case GaussianPlyFormat::Standard3DGS:
        return sizeof(float) * 62;
    case GaussianPlyFormat::Pbr3DGS:
        return sizeof(float) * 19;
    case GaussianPlyFormat::CompactPbr:
        return sizeof(float) * 10 + sizeof(uint8_t) * 8;
    default:
        return 0;
    }
}

uint64_t streamPosition(std::ofstream& file)
{
    const std::streampos position = file.tellp();
    if (position == std::streampos(-1)) {
        return 0;
    }

    return static_cast<uint64_t>(position);
}

bool shouldWriteGaussian(const core::GaussianRecord& gaussian, bool skipInvalidRecords)
{
    return !skipInvalidRecords || core::isFiniteGaussianRecord(gaussian);
}

uint64_t countWritableGaussians(
    const std::vector<core::GaussianRecord>& gaussians,
    bool skipInvalidRecords)
{
    uint64_t count = 0;
    for (const core::GaussianRecord& gaussian : gaussians) {
        if (shouldWriteGaussian(gaussian, skipInvalidRecords)) {
            ++count;
        }
    }
    return count;
}

float sanitizedScaleMultiplier(float scaleMultiplier)
{
    return std::isfinite(scaleMultiplier) && scaleMultiplier > 0.0f ?
        scaleMultiplier :
        kDefaultPlyScaleMultiplier;
}

uint8_t floatToByte(float value)
{
    const float clamped = std::clamp(value, 0.0f, 1.0f);
    return static_cast<uint8_t>(std::round(clamped * 255.0f));
}

void writeFloat(std::ofstream& file, float value)
{
    file.write(reinterpret_cast<const char*>(&value), sizeof(value));
}

void writeByte(std::ofstream& file, uint8_t value)
{
    file.write(reinterpret_cast<const char*>(&value), sizeof(value));
}

void writeStandardHeader(std::ofstream& file, uint64_t gaussianCount)
{
    file << "ply\n";
    file << "format binary_little_endian 1.0\n";
    file << "element vertex " << gaussianCount << "\n";
    file << "property float x\n";
    file << "property float y\n";
    file << "property float z\n";
    file << "property float nx\n";
    file << "property float ny\n";
    file << "property float nz\n";
    file << "property float f_dc_0\n";
    file << "property float f_dc_1\n";
    file << "property float f_dc_2\n";
    for (int index = 0; index <= 44; ++index) {
        file << "property float f_rest_" << index << "\n";
    }
    file << "property float opacity\n";
    file << "property float scale_0\n";
    file << "property float scale_1\n";
    file << "property float scale_2\n";
    file << "property float rot_0\n";
    file << "property float rot_1\n";
    file << "property float rot_2\n";
    file << "property float rot_3\n";
    file << "end_header\n";
}

void writePbrHeader(std::ofstream& file, uint64_t gaussianCount)
{
    file << "ply\n";
    file << "format binary_little_endian 1.0\n";
    file << "element vertex " << gaussianCount << "\n";
    file << "property float x\n";
    file << "property float y\n";
    file << "property float z\n";
    file << "property float nx\n";
    file << "property float ny\n";
    file << "property float nz\n";
    file << "property float f_dc_0\n";
    file << "property float f_dc_1\n";
    file << "property float f_dc_2\n";
    file << "property float metallicFactor\n";
    file << "property float roughnessFactor\n";
    file << "property float opacity\n";
    file << "property float scale_0\n";
    file << "property float scale_1\n";
    file << "property float scale_2\n";
    file << "property float rot_0\n";
    file << "property float rot_1\n";
    file << "property float rot_2\n";
    file << "property float rot_3\n";
    file << "end_header\n";
}

void writeCompactPbrHeader(std::ofstream& file, uint64_t gaussianCount)
{
    file << "ply\n";
    file << "format binary_little_endian 1.0\n";
    file << "element vertex " << gaussianCount << "\n";
    file << "property float x\n";
    file << "property float y\n";
    file << "property float z\n";
    file << "property uint8 red\n";
    file << "property uint8 green\n";
    file << "property uint8 blue\n";
    file << "property uint8 opacity\n";
    file << "property float rot_0\n";
    file << "property float rot_1\n";
    file << "property float rot_2\n";
    file << "property float rot_3\n";
    file << "property float scale_0\n";
    file << "property float scale_1\n";
    file << "property float scale_2\n";
    file << "property uint8 octa_nx\n";
    file << "property uint8 octa_ny\n";
    file << "property uint8 roughness\n";
    file << "property uint8 metallic\n";
    file << "end_header\n";
}

void writeCommon3DGSRecord(
    std::ofstream& file,
    const core::GaussianRecord& gaussian)
{
    writeFloat(file, gaussian.position[0]);
    writeFloat(file, gaussian.position[1]);
    writeFloat(file, gaussian.position[2]);
    writeFloat(file, gaussian.normal[0]);
    writeFloat(file, gaussian.normal[1]);
    writeFloat(file, gaussian.normal[2]);
    writeFloat(file, core::gaussianColorToSh0(gaussian.color[0]));
    writeFloat(file, core::gaussianColorToSh0(gaussian.color[1]));
    writeFloat(file, core::gaussianColorToSh0(gaussian.color[2]));
}

void writeStandardRecord(
    std::ofstream& file,
    const core::GaussianRecord& gaussian,
    float scaleMultiplier)
{
    writeCommon3DGSRecord(file, gaussian);

    constexpr float zero = 0.0f;
    for (int index = 0; index <= 44; ++index) {
        writeFloat(file, zero);
    }

    writeFloat(file, core::gaussianAlphaToOpacityLogit(gaussian.color[3]));
    writeFloat(file, core::gaussianPositiveScaleToLog(gaussian.scale[0], scaleMultiplier));
    writeFloat(file, core::gaussianPositiveScaleToLog(gaussian.scale[1], scaleMultiplier));
    writeFloat(file, core::gaussianPositiveScaleToLog(gaussian.scale[2], scaleMultiplier));
    writeFloat(file, gaussian.rotation[0]);
    writeFloat(file, gaussian.rotation[1]);
    writeFloat(file, gaussian.rotation[2]);
    writeFloat(file, gaussian.rotation[3]);
}

void writePbrRecord(
    std::ofstream& file,
    const core::GaussianRecord& gaussian,
    float scaleMultiplier)
{
    writeCommon3DGSRecord(file, gaussian);
    writeFloat(file, gaussian.pbr[0]);
    writeFloat(file, gaussian.pbr[1]);
    writeFloat(file, core::gaussianAlphaToOpacityLogit(gaussian.color[3]));
    writeFloat(file, core::gaussianPositiveScaleToLog(gaussian.scale[0], scaleMultiplier));
    writeFloat(file, core::gaussianPositiveScaleToLog(gaussian.scale[1], scaleMultiplier));
    writeFloat(file, core::gaussianPositiveScaleToLog(gaussian.scale[2], scaleMultiplier));
    writeFloat(file, gaussian.rotation[0]);
    writeFloat(file, gaussian.rotation[1]);
    writeFloat(file, gaussian.rotation[2]);
    writeFloat(file, gaussian.rotation[3]);
}

void encodeOctaNormal(const float normal[4], uint8_t& outX, uint8_t& outY)
{
    const float length = std::sqrt(
        normal[0] * normal[0] +
        normal[1] * normal[1] +
        normal[2] * normal[2]);
    if (length <= 1.0e-8f) {
        outX = 128;
        outY = 128;
        return;
    }

    float x = normal[0] / length;
    float y = normal[1] / length;
    float z = normal[2] / length;
    const float denominator = std::abs(x) + std::abs(y) + std::abs(z) + 1.0e-8f;
    x /= denominator;
    y /= denominator;
    z /= denominator;

    if (z < 0.0f) {
        const float wrappedX = (1.0f - std::abs(y)) * (x >= 0.0f ? 1.0f : -1.0f);
        const float wrappedY = (1.0f - std::abs(x)) * (y >= 0.0f ? 1.0f : -1.0f);
        x = wrappedX;
        y = wrappedY;
    }

    outX = floatToByte(x * 0.5f + 0.5f);
    outY = floatToByte(y * 0.5f + 0.5f);
}

void writeCompactPbrRecord(
    std::ofstream& file,
    const core::GaussianRecord& gaussian,
    float scaleMultiplier)
{
    writeFloat(file, gaussian.position[0]);
    writeFloat(file, gaussian.position[1]);
    writeFloat(file, gaussian.position[2]);
    writeByte(file, floatToByte(gaussian.color[0]));
    writeByte(file, floatToByte(gaussian.color[1]));
    writeByte(file, floatToByte(gaussian.color[2]));
    writeByte(file, floatToByte(gaussian.color[3]));
    writeFloat(file, gaussian.rotation[0]);
    writeFloat(file, gaussian.rotation[1]);
    writeFloat(file, gaussian.rotation[2]);
    writeFloat(file, gaussian.rotation[3]);

    const float compactZScale = std::min(gaussian.scale[0], gaussian.scale[1]);
    writeFloat(file, core::gaussianPositiveScaleToLog(gaussian.scale[0], scaleMultiplier));
    writeFloat(file, core::gaussianPositiveScaleToLog(gaussian.scale[1], scaleMultiplier));
    writeFloat(file, core::gaussianPositiveScaleToLog(compactZScale, scaleMultiplier));

    uint8_t octaX = 0;
    uint8_t octaY = 0;
    encodeOctaNormal(gaussian.normal, octaX, octaY);
    writeByte(file, octaX);
    writeByte(file, octaY);
    writeByte(file, floatToByte(gaussian.pbr[1]));
    writeByte(file, floatToByte(gaussian.pbr[0]));
}

} // namespace

bool writeGaussianPly(
    const std::string& filePath,
    const std::vector<core::GaussianRecord>& gaussians,
    const GaussianPlyWriteOptions& options,
    GaussianPlyWriteResult* result)
{
    GaussianPlyWriteResult localResult;
    localResult.requestedCount = gaussians.size();
    localResult.format = options.format;

    if (filePath.empty() || isBlank(filePath)) {
        localResult.error = "PLY output path is empty.";
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    if (!hasPathFilename(filePath)) {
        localResult.error = "PLY output path does not name a file: " + filePath;
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    if (lowerExtension(filePath) != ".ply") {
        localResult.error = "PLY output path must use the .ply extension: " + filePath;
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    const std::string outputDirectory = parentPath(filePath);
    if (!outputDirectory.empty() && !directoryExists(outputDirectory)) {
        localResult.error = "PLY output directory does not exist: " + outputDirectory;
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    if (!isSupportedFormat(options.format)) {
        localResult.error = "Unsupported Gaussian PLY format.";
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    const uint64_t writableCount = countWritableGaussians(gaussians, options.skipInvalidRecords);
    localResult.writtenCount = writableCount;
    localResult.skippedInvalidCount = localResult.requestedCount - localResult.writtenCount;
    localResult.effectiveScaleMultiplier = sanitizedScaleMultiplier(options.scaleMultiplier);
    localResult.scaleMultiplierWasSanitized =
        !std::isfinite(options.scaleMultiplier) || options.scaleMultiplier <= 0.0f;
    if (localResult.scaleMultiplierWasSanitized) {
        appendWarning(localResult, "PLY scale multiplier was invalid; using 1.0.");
    }
    if (localResult.requestedCount == 0) {
        appendWarning(localResult, "PLY writer emitted an empty point cloud.");
    } else if (localResult.writtenCount == 0) {
        appendWarning(localResult, "PLY writer skipped all gaussian records as invalid.");
    } else if (localResult.skippedInvalidCount > 0) {
        appendWarning(
            localResult,
            "PLY writer skipped " + std::to_string(localResult.skippedInvalidCount) +
                " invalid gaussian records.");
    }

    std::ofstream file(filePath, std::ios::binary | std::ios::out | std::ios::trunc);
    if (!file.is_open()) {
        localResult.error = "Failed to open PLY output file: " + filePath;
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    switch (options.format) {
    case GaussianPlyFormat::Standard3DGS:
        writeStandardHeader(file, writableCount);
        break;
    case GaussianPlyFormat::Pbr3DGS:
        writePbrHeader(file, writableCount);
        break;
    case GaussianPlyFormat::CompactPbr:
        writeCompactPbrHeader(file, writableCount);
        break;
    default:
        break;
    }
    localResult.headerByteCount = streamPosition(file);

    for (const core::GaussianRecord& gaussian : gaussians) {
        if (!shouldWriteGaussian(gaussian, options.skipInvalidRecords)) {
            continue;
        }

        switch (options.format) {
        case GaussianPlyFormat::Standard3DGS:
            writeStandardRecord(file, gaussian, localResult.effectiveScaleMultiplier);
            break;
        case GaussianPlyFormat::Pbr3DGS:
            writePbrRecord(file, gaussian, localResult.effectiveScaleMultiplier);
            break;
        case GaussianPlyFormat::CompactPbr:
            writeCompactPbrRecord(file, gaussian, localResult.effectiveScaleMultiplier);
            break;
        default:
            break;
        }
    }
    localResult.recordByteCount = recordByteSize(options.format) * localResult.writtenCount;

    file.flush();
    if (!file.good()) {
        localResult.error = "Failed while writing PLY output file: " + filePath;
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }
    localResult.outputByteCount = streamPosition(file);
    if (localResult.outputByteCount == 0) {
        localResult.outputByteCount = localResult.headerByteCount + localResult.recordByteCount;
    }

    if (result != nullptr) {
        *result = localResult;
    }
    return true;
}

} // namespace mesh2splat::io
