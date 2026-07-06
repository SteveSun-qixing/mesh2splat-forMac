#include "io/PlyReader.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <limits>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::io {
namespace {

constexpr float kDefaultPlyScaleMultiplier = 1.0f;

enum class PlyScalarType : uint8_t {
    Unknown = 0,
    Int8,
    UInt8,
    Int16,
    UInt16,
    Int32,
    UInt32,
    Float32,
    Float64,
};

enum class PlyPropertyRole : uint8_t {
    Ignore = 0,
    PositionX,
    PositionY,
    PositionZ,
    NormalX,
    NormalY,
    NormalZ,
    Sh0R,
    Sh0G,
    Sh0B,
    Red,
    Green,
    Blue,
    Opacity,
    ScaleX,
    ScaleY,
    ScaleZ,
    Rotation0,
    Rotation1,
    Rotation2,
    Rotation3,
    MetallicFactor,
    RoughnessFactor,
    MetallicByte,
    RoughnessByte,
    OctaNormalX,
    OctaNormalY,
};

struct PlyProperty {
    std::string name;
    PlyScalarType type = PlyScalarType::Unknown;
    PlyScalarType listCountType = PlyScalarType::Unknown;
    bool isList = false;
};

struct PlyElement {
    std::string name;
    uint64_t count = 0;
    std::vector<PlyProperty> properties;
};

struct PlyHeader {
    GaussianPlyEncoding encoding = GaussianPlyEncoding::Unknown;
    std::vector<PlyElement> elements;
    uint64_t headerByteCount = 0;
};

struct VertexPropertyReader {
    PlyProperty property;
    PlyPropertyRole role = PlyPropertyRole::Ignore;
};

struct VertexScratch {
    core::GaussianRecord gaussian;
    std::array<bool, 3> hasPosition = {false, false, false};
    std::array<bool, 3> hasShColor = {false, false, false};
    std::array<bool, 3> hasByteColor = {false, false, false};
    std::array<bool, 3> hasNormal = {false, false, false};
    std::array<bool, 3> hasScale = {false, false, false};
    std::array<bool, 4> hasRotation = {false, false, false, false};
    std::array<bool, 2> hasOctaNormal = {false, false};
    float shColor[3] = {0.0f, 0.0f, 0.0f};
    float byteColor[3] = {0.0f, 0.0f, 0.0f};
    float normal[3] = {0.0f, 1.0f, 0.0f};
    float scaleLog[3] = {0.0f, 0.0f, 0.0f};
    float rotation[4] = {1.0f, 0.0f, 0.0f, 0.0f};
    float octaNormal[2] = {128.0f, 128.0f};
    float opacity = 0.0f;
    bool hasOpacity = false;
    bool opacityIsNormalized = false;
    float metallic = 0.1f;
    float roughness = 0.5f;
    bool hasMetallic = false;
    bool hasRoughness = false;
};

bool isBlank(const std::string& value)
{
    return std::all_of(value.begin(), value.end(), [](char character) {
        return std::isspace(static_cast<unsigned char>(character)) != 0;
    });
}

std::string withoutTrailingCarriageReturn(std::string line)
{
    if (!line.empty() && line.back() == '\r') {
        line.pop_back();
    }
    return line;
}

std::string asciiLower(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](char character) {
        return static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
    });
    return value;
}

std::string lowerExtension(const std::string& filePath)
{
    const std::size_t separator = filePath.find_last_of("/\\");
    const std::size_t dot = filePath.find_last_of('.');
    if (dot == std::string::npos || dot + 1 >= filePath.size() ||
        (separator != std::string::npos && dot < separator)) {
        return {};
    }

    return asciiLower(filePath.substr(dot));
}

void appendWarning(GaussianPlyReadResult& result, const std::string& warning)
{
    if (warning.empty()) {
        return;
    }

    if (!result.warning.empty() && result.warning.back() != '\n') {
        result.warning.push_back('\n');
    }
    result.warning += warning;
}

float sanitizedScaleMultiplier(float scaleMultiplier)
{
    return std::isfinite(scaleMultiplier) && scaleMultiplier > 0.0f ?
        scaleMultiplier :
        kDefaultPlyScaleMultiplier;
}

uint64_t streamPosition(std::istream& file)
{
    const std::streampos position = file.tellg();
    if (position == std::streampos(-1)) {
        return 0;
    }

    return static_cast<uint64_t>(position);
}

bool checkedMultiply(uint64_t lhs, uint64_t rhs, uint64_t& result)
{
    if (lhs != 0 && rhs > std::numeric_limits<uint64_t>::max() / lhs) {
        return false;
    }
    result = lhs * rhs;
    return true;
}

PlyScalarType parseScalarType(const std::string& value)
{
    const std::string type = asciiLower(value);
    if (type == "char" || type == "int8") {
        return PlyScalarType::Int8;
    }
    if (type == "uchar" || type == "uint8" || type == "uchar8") {
        return PlyScalarType::UInt8;
    }
    if (type == "short" || type == "int16") {
        return PlyScalarType::Int16;
    }
    if (type == "ushort" || type == "uint16") {
        return PlyScalarType::UInt16;
    }
    if (type == "int" || type == "int32") {
        return PlyScalarType::Int32;
    }
    if (type == "uint" || type == "uint32") {
        return PlyScalarType::UInt32;
    }
    if (type == "float" || type == "float32") {
        return PlyScalarType::Float32;
    }
    if (type == "double" || type == "float64") {
        return PlyScalarType::Float64;
    }
    return PlyScalarType::Unknown;
}

uint64_t scalarTypeSize(PlyScalarType type)
{
    switch (type) {
    case PlyScalarType::Int8:
    case PlyScalarType::UInt8:
        return 1;
    case PlyScalarType::Int16:
    case PlyScalarType::UInt16:
        return 2;
    case PlyScalarType::Int32:
    case PlyScalarType::UInt32:
    case PlyScalarType::Float32:
        return 4;
    case PlyScalarType::Float64:
        return 8;
    case PlyScalarType::Unknown:
        break;
    }
    return 0;
}

bool isNormalizedByteProperty(PlyScalarType type)
{
    return type == PlyScalarType::UInt8 || type == PlyScalarType::Int8;
}

bool isKnownPropertyType(const PlyProperty& property)
{
    if (property.type == PlyScalarType::Unknown) {
        return false;
    }
    if (property.isList && property.listCountType == PlyScalarType::Unknown) {
        return false;
    }
    return true;
}

PlyPropertyRole roleForPropertyName(const std::string& name)
{
    if (name == "x") {
        return PlyPropertyRole::PositionX;
    }
    if (name == "y") {
        return PlyPropertyRole::PositionY;
    }
    if (name == "z") {
        return PlyPropertyRole::PositionZ;
    }
    if (name == "nx") {
        return PlyPropertyRole::NormalX;
    }
    if (name == "ny") {
        return PlyPropertyRole::NormalY;
    }
    if (name == "nz") {
        return PlyPropertyRole::NormalZ;
    }
    if (name == "f_dc_0") {
        return PlyPropertyRole::Sh0R;
    }
    if (name == "f_dc_1") {
        return PlyPropertyRole::Sh0G;
    }
    if (name == "f_dc_2") {
        return PlyPropertyRole::Sh0B;
    }
    if (name == "red") {
        return PlyPropertyRole::Red;
    }
    if (name == "green") {
        return PlyPropertyRole::Green;
    }
    if (name == "blue") {
        return PlyPropertyRole::Blue;
    }
    if (name == "opacity" || name == "alpha") {
        return PlyPropertyRole::Opacity;
    }
    if (name == "scale_0") {
        return PlyPropertyRole::ScaleX;
    }
    if (name == "scale_1") {
        return PlyPropertyRole::ScaleY;
    }
    if (name == "scale_2") {
        return PlyPropertyRole::ScaleZ;
    }
    if (name == "rot_0") {
        return PlyPropertyRole::Rotation0;
    }
    if (name == "rot_1") {
        return PlyPropertyRole::Rotation1;
    }
    if (name == "rot_2") {
        return PlyPropertyRole::Rotation2;
    }
    if (name == "rot_3") {
        return PlyPropertyRole::Rotation3;
    }
    if (name == "metallicFactor") {
        return PlyPropertyRole::MetallicFactor;
    }
    if (name == "roughnessFactor") {
        return PlyPropertyRole::RoughnessFactor;
    }
    if (name == "metallic") {
        return PlyPropertyRole::MetallicByte;
    }
    if (name == "roughness") {
        return PlyPropertyRole::RoughnessByte;
    }
    if (name == "octa_nx") {
        return PlyPropertyRole::OctaNormalX;
    }
    if (name == "octa_ny") {
        return PlyPropertyRole::OctaNormalY;
    }
    return PlyPropertyRole::Ignore;
}

bool parseHeader(std::istream& file, PlyHeader& header, std::string& error)
{
    std::string line;
    if (!std::getline(file, line)) {
        error = "PLY file is empty.";
        return false;
    }
    line = withoutTrailingCarriageReturn(std::move(line));
    if (line != "ply") {
        error = "PLY header is missing the magic 'ply' line.";
        return false;
    }

    PlyElement* currentElement = nullptr;
    bool foundEndHeader = false;
    while (std::getline(file, line)) {
        line = withoutTrailingCarriageReturn(std::move(line));
        if (line == "end_header") {
            foundEndHeader = true;
            break;
        }
        if (line.empty()) {
            continue;
        }

        std::istringstream tokens(line);
        std::string keyword;
        tokens >> keyword;
        if (keyword.empty() || keyword == "comment" || keyword == "obj_info") {
            continue;
        }
        if (keyword == "format") {
            std::string formatName;
            std::string version;
            tokens >> formatName >> version;
            if (formatName == "ascii") {
                header.encoding = GaussianPlyEncoding::Ascii;
            } else if (formatName == "binary_little_endian") {
                header.encoding = GaussianPlyEncoding::BinaryLittleEndian;
            } else if (formatName == "binary_big_endian") {
                error = "PLY binary_big_endian encoding is not supported by the native reader.";
                return false;
            } else {
                error = "Unsupported PLY format: " + formatName;
                return false;
            }
            continue;
        }
        if (keyword == "element") {
            std::string elementName;
            uint64_t elementCount = 0;
            tokens >> elementName >> elementCount;
            if (elementName.empty() || tokens.fail()) {
                error = "Malformed PLY element declaration.";
                return false;
            }
            header.elements.push_back(PlyElement{std::move(elementName), elementCount, {}});
            currentElement = &header.elements.back();
            continue;
        }
        if (keyword == "property") {
            if (currentElement == nullptr) {
                error = "PLY property appeared before any element declaration.";
                return false;
            }

            std::string firstType;
            tokens >> firstType;
            if (firstType == "list") {
                std::string countType;
                std::string valueType;
                std::string propertyName;
                tokens >> countType >> valueType >> propertyName;
                PlyProperty property;
                property.name = std::move(propertyName);
                property.isList = true;
                property.listCountType = parseScalarType(countType);
                property.type = parseScalarType(valueType);
                if (property.name.empty() || !isKnownPropertyType(property)) {
                    error = "Unsupported or malformed PLY list property.";
                    return false;
                }
                currentElement->properties.push_back(std::move(property));
                continue;
            }

            std::string propertyName;
            tokens >> propertyName;
            PlyProperty property;
            property.name = std::move(propertyName);
            property.type = parseScalarType(firstType);
            if (property.name.empty() || !isKnownPropertyType(property)) {
                error = "Unsupported or malformed PLY scalar property.";
                return false;
            }
            currentElement->properties.push_back(std::move(property));
            continue;
        }
    }

    if (!foundEndHeader) {
        error = "PLY header is missing end_header.";
        return false;
    }
    if (header.encoding == GaussianPlyEncoding::Unknown) {
        error = "PLY header is missing a supported format declaration.";
        return false;
    }
    header.headerByteCount = streamPosition(file);
    return true;
}

const PlyElement* findVertexElement(const PlyHeader& header)
{
    for (const PlyElement& element : header.elements) {
        if (element.name == "vertex") {
            return &element;
        }
    }
    return nullptr;
}

std::vector<VertexPropertyReader> makeVertexReaders(const PlyElement& vertexElement)
{
    std::vector<VertexPropertyReader> readers;
    readers.reserve(vertexElement.properties.size());
    for (const PlyProperty& property : vertexElement.properties) {
        VertexPropertyReader reader;
        reader.property = property;
        reader.role = property.isList ? PlyPropertyRole::Ignore : roleForPropertyName(property.name);
        readers.push_back(std::move(reader));
    }
    return readers;
}

bool vertexReadersHavePosition(const std::vector<VertexPropertyReader>& readers)
{
    std::array<bool, 3> hasPosition = {false, false, false};
    for (const VertexPropertyReader& reader : readers) {
        switch (reader.role) {
        case PlyPropertyRole::PositionX:
            hasPosition[0] = true;
            break;
        case PlyPropertyRole::PositionY:
            hasPosition[1] = true;
            break;
        case PlyPropertyRole::PositionZ:
            hasPosition[2] = true;
            break;
        default:
            break;
        }
    }
    return hasPosition[0] && hasPosition[1] && hasPosition[2];
}

uint64_t readUnsignedLittleEndian(const unsigned char* bytes, uint64_t size)
{
    uint64_t value = 0;
    for (uint64_t index = 0; index < size; ++index) {
        value |= static_cast<uint64_t>(bytes[index]) << (index * 8);
    }
    return value;
}

int64_t signExtend(uint64_t value, uint64_t bits)
{
    const uint64_t signBit = 1ull << (bits - 1);
    return static_cast<int64_t>((value ^ signBit) - signBit);
}

bool readScalarBinary(std::istream& file, PlyScalarType type, double& value)
{
    const uint64_t size = scalarTypeSize(type);
    if (size == 0 || size > 8) {
        return false;
    }

    unsigned char bytes[8] = {};
    file.read(reinterpret_cast<char*>(bytes), static_cast<std::streamsize>(size));
    if (!file.good()) {
        return false;
    }

    const uint64_t raw = readUnsignedLittleEndian(bytes, size);
    switch (type) {
    case PlyScalarType::Int8:
        value = static_cast<double>(signExtend(raw, 8));
        return true;
    case PlyScalarType::UInt8:
        value = static_cast<double>(raw);
        return true;
    case PlyScalarType::Int16:
        value = static_cast<double>(signExtend(raw, 16));
        return true;
    case PlyScalarType::UInt16:
        value = static_cast<double>(raw);
        return true;
    case PlyScalarType::Int32:
        value = static_cast<double>(signExtend(raw, 32));
        return true;
    case PlyScalarType::UInt32:
        value = static_cast<double>(raw);
        return true;
    case PlyScalarType::Float32: {
        const uint32_t bits = static_cast<uint32_t>(raw);
        float floatValue = 0.0f;
        std::memcpy(&floatValue, &bits, sizeof(floatValue));
        value = static_cast<double>(floatValue);
        return true;
    }
    case PlyScalarType::Float64: {
        double doubleValue = 0.0;
        std::memcpy(&doubleValue, &raw, sizeof(doubleValue));
        value = doubleValue;
        return true;
    }
    case PlyScalarType::Unknown:
        break;
    }
    return false;
}

bool readScalarAscii(std::istream& file, PlyScalarType type, double& value)
{
    if (type == PlyScalarType::Unknown) {
        return false;
    }
    file >> value;
    return !file.fail();
}

bool skipBytes(std::istream& file, uint64_t byteCount)
{
    if (byteCount == 0) {
        return true;
    }
    if (byteCount > static_cast<uint64_t>(std::numeric_limits<std::streamoff>::max())) {
        return false;
    }

    file.seekg(static_cast<std::streamoff>(byteCount), std::ios::cur);
    return file.good();
}

bool listCountFromScalar(double value, uint64_t& count)
{
    if (!std::isfinite(value) || value < 0.0 ||
        value > static_cast<double>(std::numeric_limits<uint64_t>::max())) {
        return false;
    }
    count = static_cast<uint64_t>(value);
    return true;
}

bool skipListBinary(std::istream& file, const PlyProperty& property)
{
    double countValue = 0.0;
    if (!readScalarBinary(file, property.listCountType, countValue)) {
        return false;
    }

    uint64_t count = 0;
    uint64_t byteCount = 0;
    if (!listCountFromScalar(countValue, count) ||
        !checkedMultiply(count, scalarTypeSize(property.type), byteCount)) {
        return false;
    }
    return skipBytes(file, byteCount);
}

bool skipListAscii(std::istream& file, const PlyProperty& property)
{
    double countValue = 0.0;
    if (!readScalarAscii(file, property.listCountType, countValue)) {
        return false;
    }

    uint64_t count = 0;
    if (!listCountFromScalar(countValue, count)) {
        return false;
    }
    for (uint64_t index = 0; index < count; ++index) {
        double ignored = 0.0;
        if (!readScalarAscii(file, property.type, ignored)) {
            return false;
        }
    }
    return true;
}

float clampedUnit(double value)
{
    if (!std::isfinite(value)) {
        return 0.0f;
    }
    return static_cast<float>(std::clamp(value, 0.0, 1.0));
}

float normalizedScalar(double value, PlyScalarType type)
{
    if (!std::isfinite(value)) {
        return 0.0f;
    }
    switch (type) {
    case PlyScalarType::UInt8:
        return clampedUnit(value / 255.0);
    case PlyScalarType::Int8:
        return clampedUnit(value / 127.0);
    case PlyScalarType::UInt16:
        return clampedUnit(value / 65535.0);
    case PlyScalarType::Int16:
        return clampedUnit(value / 32767.0);
    case PlyScalarType::UInt32:
        return clampedUnit(value / 4294967295.0);
    case PlyScalarType::Int32:
        return clampedUnit(value / 2147483647.0);
    case PlyScalarType::Float32:
    case PlyScalarType::Float64:
        return clampedUnit(value);
    case PlyScalarType::Unknown:
        break;
    }
    return 0.0f;
}

float sigmoid(double value)
{
    if (!std::isfinite(value)) {
        return 1.0f;
    }
    if (value >= 0.0) {
        const double exponent = std::exp(-value);
        return static_cast<float>(1.0 / (1.0 + exponent));
    }

    const double exponent = std::exp(value);
    return static_cast<float>(exponent / (1.0 + exponent));
}

float sh0ToColor(double sh0)
{
    return static_cast<float>(sh0 * core::kSphericalHarmonicC0 + 0.5);
}

float positiveScaleFromLog(double value, float scaleMultiplier)
{
    if (!std::isfinite(value)) {
        return std::numeric_limits<float>::infinity();
    }
    const double decoded = std::exp(value) / static_cast<double>(scaleMultiplier);
    if (!std::isfinite(decoded)) {
        return std::numeric_limits<float>::infinity();
    }
    return std::max(static_cast<float>(decoded), core::kGaussianMinimumAxisScale);
}

void normalizeVector3(float values[3], const float fallback[3])
{
    const float length = std::sqrt(
        values[0] * values[0] +
        values[1] * values[1] +
        values[2] * values[2]);
    if (!std::isfinite(length) || length <= 1.0e-8f) {
        values[0] = fallback[0];
        values[1] = fallback[1];
        values[2] = fallback[2];
        return;
    }

    values[0] /= length;
    values[1] /= length;
    values[2] /= length;
}

void normalizeQuaternion(float rotation[4])
{
    const float length = std::sqrt(
        rotation[0] * rotation[0] +
        rotation[1] * rotation[1] +
        rotation[2] * rotation[2] +
        rotation[3] * rotation[3]);
    if (!std::isfinite(length) || length <= 1.0e-8f) {
        rotation[0] = 1.0f;
        rotation[1] = 0.0f;
        rotation[2] = 0.0f;
        rotation[3] = 0.0f;
        return;
    }

    for (int component = 0; component < 4; ++component) {
        rotation[component] /= length;
    }
}

void decodeOctaNormal(float encodedX, float encodedY, float normal[3])
{
    float x = clampedUnit(encodedX / 255.0f) * 2.0f - 1.0f;
    float y = clampedUnit(encodedY / 255.0f) * 2.0f - 1.0f;
    float z = 1.0f - std::abs(x) - std::abs(y);
    if (z < 0.0f) {
        const float oldX = x;
        x = (1.0f - std::abs(y)) * (oldX >= 0.0f ? 1.0f : -1.0f);
        y = (1.0f - std::abs(oldX)) * (y >= 0.0f ? 1.0f : -1.0f);
    }

    normal[0] = x;
    normal[1] = y;
    normal[2] = z;
    constexpr float fallback[3] = {0.0f, 1.0f, 0.0f};
    normalizeVector3(normal, fallback);
}

void applyScalar(VertexScratch& scratch, const VertexPropertyReader& reader, double value)
{
    const float floatValue = static_cast<float>(value);
    switch (reader.role) {
    case PlyPropertyRole::PositionX:
        scratch.gaussian.position[0] = floatValue;
        scratch.hasPosition[0] = true;
        break;
    case PlyPropertyRole::PositionY:
        scratch.gaussian.position[1] = floatValue;
        scratch.hasPosition[1] = true;
        break;
    case PlyPropertyRole::PositionZ:
        scratch.gaussian.position[2] = floatValue;
        scratch.hasPosition[2] = true;
        break;
    case PlyPropertyRole::NormalX:
        scratch.normal[0] = floatValue;
        scratch.hasNormal[0] = true;
        break;
    case PlyPropertyRole::NormalY:
        scratch.normal[1] = floatValue;
        scratch.hasNormal[1] = true;
        break;
    case PlyPropertyRole::NormalZ:
        scratch.normal[2] = floatValue;
        scratch.hasNormal[2] = true;
        break;
    case PlyPropertyRole::Sh0R:
        scratch.shColor[0] = floatValue;
        scratch.hasShColor[0] = true;
        break;
    case PlyPropertyRole::Sh0G:
        scratch.shColor[1] = floatValue;
        scratch.hasShColor[1] = true;
        break;
    case PlyPropertyRole::Sh0B:
        scratch.shColor[2] = floatValue;
        scratch.hasShColor[2] = true;
        break;
    case PlyPropertyRole::Red:
        scratch.byteColor[0] = normalizedScalar(value, reader.property.type);
        scratch.hasByteColor[0] = true;
        break;
    case PlyPropertyRole::Green:
        scratch.byteColor[1] = normalizedScalar(value, reader.property.type);
        scratch.hasByteColor[1] = true;
        break;
    case PlyPropertyRole::Blue:
        scratch.byteColor[2] = normalizedScalar(value, reader.property.type);
        scratch.hasByteColor[2] = true;
        break;
    case PlyPropertyRole::Opacity:
        scratch.opacity = floatValue;
        scratch.hasOpacity = true;
        scratch.opacityIsNormalized = isNormalizedByteProperty(reader.property.type) ||
            reader.property.name == "alpha";
        break;
    case PlyPropertyRole::ScaleX:
        scratch.scaleLog[0] = floatValue;
        scratch.hasScale[0] = true;
        break;
    case PlyPropertyRole::ScaleY:
        scratch.scaleLog[1] = floatValue;
        scratch.hasScale[1] = true;
        break;
    case PlyPropertyRole::ScaleZ:
        scratch.scaleLog[2] = floatValue;
        scratch.hasScale[2] = true;
        break;
    case PlyPropertyRole::Rotation0:
        scratch.rotation[0] = floatValue;
        scratch.hasRotation[0] = true;
        break;
    case PlyPropertyRole::Rotation1:
        scratch.rotation[1] = floatValue;
        scratch.hasRotation[1] = true;
        break;
    case PlyPropertyRole::Rotation2:
        scratch.rotation[2] = floatValue;
        scratch.hasRotation[2] = true;
        break;
    case PlyPropertyRole::Rotation3:
        scratch.rotation[3] = floatValue;
        scratch.hasRotation[3] = true;
        break;
    case PlyPropertyRole::MetallicFactor:
        scratch.metallic = clampedUnit(value);
        scratch.hasMetallic = true;
        break;
    case PlyPropertyRole::RoughnessFactor:
        scratch.roughness = clampedUnit(value);
        scratch.hasRoughness = true;
        break;
    case PlyPropertyRole::MetallicByte:
        scratch.metallic = normalizedScalar(value, reader.property.type);
        scratch.hasMetallic = true;
        break;
    case PlyPropertyRole::RoughnessByte:
        scratch.roughness = normalizedScalar(value, reader.property.type);
        scratch.hasRoughness = true;
        break;
    case PlyPropertyRole::OctaNormalX:
        scratch.octaNormal[0] = floatValue;
        scratch.hasOctaNormal[0] = true;
        break;
    case PlyPropertyRole::OctaNormalY:
        scratch.octaNormal[1] = floatValue;
        scratch.hasOctaNormal[1] = true;
        break;
    case PlyPropertyRole::Ignore:
        break;
    }
}

core::GaussianRecord finalizeScratch(VertexScratch& scratch, float scaleMultiplier)
{
    for (int component = 0; component < 3; ++component) {
        if (scratch.hasShColor[component]) {
            scratch.gaussian.color[component] = sh0ToColor(scratch.shColor[component]);
        } else if (scratch.hasByteColor[component]) {
            scratch.gaussian.color[component] = scratch.byteColor[component];
        }
    }

    if (scratch.hasOpacity) {
        scratch.gaussian.color[3] = scratch.opacityIsNormalized
            ? clampedUnit(scratch.opacity)
            : sigmoid(scratch.opacity);
    }

    if (scratch.hasScale[0]) {
        scratch.gaussian.scale[0] = positiveScaleFromLog(scratch.scaleLog[0], scaleMultiplier);
    }
    if (scratch.hasScale[1]) {
        scratch.gaussian.scale[1] = positiveScaleFromLog(scratch.scaleLog[1], scaleMultiplier);
    }
    if (scratch.hasScale[2]) {
        scratch.gaussian.scale[2] = positiveScaleFromLog(scratch.scaleLog[2], scaleMultiplier);
    }

    if (scratch.hasOctaNormal[0] && scratch.hasOctaNormal[1]) {
        decodeOctaNormal(scratch.octaNormal[0], scratch.octaNormal[1], scratch.normal);
        scratch.hasNormal = {true, true, true};
    }
    if (scratch.hasNormal[0] || scratch.hasNormal[1] || scratch.hasNormal[2]) {
        constexpr float fallback[3] = {0.0f, 1.0f, 0.0f};
        normalizeVector3(scratch.normal, fallback);
        scratch.gaussian.normal[0] = scratch.normal[0];
        scratch.gaussian.normal[1] = scratch.normal[1];
        scratch.gaussian.normal[2] = scratch.normal[2];
    }

    if (scratch.hasRotation[0] || scratch.hasRotation[1] ||
        scratch.hasRotation[2] || scratch.hasRotation[3]) {
        normalizeQuaternion(scratch.rotation);
        scratch.gaussian.rotation[0] = scratch.rotation[0];
        scratch.gaussian.rotation[1] = scratch.rotation[1];
        scratch.gaussian.rotation[2] = scratch.rotation[2];
        scratch.gaussian.rotation[3] = scratch.rotation[3];
    }

    if (scratch.hasMetallic) {
        scratch.gaussian.pbr[0] = scratch.metallic;
    }
    if (scratch.hasRoughness) {
        scratch.gaussian.pbr[1] = scratch.roughness;
    }
    return scratch.gaussian;
}

bool readVertexBinary(
    std::istream& file,
    const std::vector<VertexPropertyReader>& readers,
    float scaleMultiplier,
    core::GaussianRecord& gaussian)
{
    VertexScratch scratch;
    for (const VertexPropertyReader& reader : readers) {
        if (reader.property.isList) {
            if (!skipListBinary(file, reader.property)) {
                return false;
            }
            continue;
        }

        double value = 0.0;
        if (!readScalarBinary(file, reader.property.type, value)) {
            return false;
        }
        applyScalar(scratch, reader, value);
    }

    gaussian = finalizeScratch(scratch, scaleMultiplier);
    return true;
}

bool readVertexAscii(
    std::istream& file,
    const std::vector<VertexPropertyReader>& readers,
    float scaleMultiplier,
    core::GaussianRecord& gaussian)
{
    VertexScratch scratch;
    for (const VertexPropertyReader& reader : readers) {
        if (reader.property.isList) {
            if (!skipListAscii(file, reader.property)) {
                return false;
            }
            continue;
        }

        double value = 0.0;
        if (!readScalarAscii(file, reader.property.type, value)) {
            return false;
        }
        applyScalar(scratch, reader, value);
    }

    gaussian = finalizeScratch(scratch, scaleMultiplier);
    return true;
}

bool skipElementBinary(std::istream& file, const PlyElement& element)
{
    uint64_t fixedRecordSize = 0;
    bool allScalar = true;
    for (const PlyProperty& property : element.properties) {
        if (property.isList) {
            allScalar = false;
            break;
        }
        fixedRecordSize += scalarTypeSize(property.type);
    }

    if (allScalar) {
        uint64_t byteCount = 0;
        if (!checkedMultiply(element.count, fixedRecordSize, byteCount)) {
            return false;
        }
        return skipBytes(file, byteCount);
    }

    for (uint64_t record = 0; record < element.count; ++record) {
        for (const PlyProperty& property : element.properties) {
            if (property.isList) {
                if (!skipListBinary(file, property)) {
                    return false;
                }
                continue;
            }
            if (!skipBytes(file, scalarTypeSize(property.type))) {
                return false;
            }
        }
    }
    return true;
}

bool skipElementAscii(std::istream& file, const PlyElement& element)
{
    for (uint64_t record = 0; record < element.count; ++record) {
        for (const PlyProperty& property : element.properties) {
            if (property.isList) {
                if (!skipListAscii(file, property)) {
                    return false;
                }
                continue;
            }
            double ignored = 0.0;
            if (!readScalarAscii(file, property.type, ignored)) {
                return false;
            }
        }
    }
    return true;
}

bool readVertexElement(
    std::istream& file,
    const PlyHeader& header,
    const PlyElement& vertexElement,
    const std::vector<VertexPropertyReader>& readers,
    const GaussianPlyReadOptions& options,
    GaussianPlyReadResult& result,
    std::vector<core::GaussianRecord>& gaussians)
{
    gaussians.clear();
    if (!core::gaussianCountFitsBuffer(static_cast<std::size_t>(vertexElement.count))) {
        result.error = "PLY vertex count exceeds GaussianRecord buffer limits.";
        return false;
    }

    gaussians.reserve(static_cast<std::size_t>(vertexElement.count));
    const uint64_t dataStart = streamPosition(file);
    for (const PlyElement& element : header.elements) {
        if (&element == &vertexElement) {
            for (uint64_t index = 0; index < vertexElement.count; ++index) {
                core::GaussianRecord gaussian;
                const bool readOk = header.encoding == GaussianPlyEncoding::BinaryLittleEndian
                    ? readVertexBinary(file, readers, result.effectiveScaleMultiplier, gaussian)
                    : readVertexAscii(file, readers, result.effectiveScaleMultiplier, gaussian);
                if (!readOk) {
                    result.error = "Failed while reading PLY vertex record " + std::to_string(index) + ".";
                    return false;
                }

                if (options.skipInvalidRecords && !core::isValidGaussianRecordForGpuUpload(gaussian)) {
                    ++result.skippedInvalidCount;
                    continue;
                }
                gaussians.push_back(gaussian);
            }
            break;
        }

        const bool skipped = header.encoding == GaussianPlyEncoding::BinaryLittleEndian
            ? skipElementBinary(file, element)
            : skipElementAscii(file, element);
        if (!skipped) {
            result.error = "Failed while skipping PLY element before vertex data: " + element.name;
            return false;
        }
    }

    const uint64_t dataEnd = streamPosition(file);
    if (dataEnd >= dataStart) {
        result.dataByteCount = dataEnd - dataStart;
    }
    result.readCount = gaussians.size();
    return true;
}

} // namespace

bool readGaussianPly(
    const std::string& filePath,
    std::vector<core::GaussianRecord>& gaussians,
    const GaussianPlyReadOptions& options,
    GaussianPlyReadResult* result)
{
    gaussians.clear();

    GaussianPlyReadResult localResult;
    localResult.effectiveScaleMultiplier = sanitizedScaleMultiplier(options.scaleMultiplier);
    localResult.scaleMultiplierWasSanitized =
        !std::isfinite(options.scaleMultiplier) || options.scaleMultiplier <= 0.0f;
    if (localResult.scaleMultiplierWasSanitized) {
        appendWarning(localResult, "PLY scale multiplier was invalid; using 1.0.");
    }

    if (filePath.empty() || isBlank(filePath)) {
        localResult.error = "PLY input path is empty.";
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    if (lowerExtension(filePath) != ".ply") {
        localResult.error = "PLY input path must use the .ply extension: " + filePath;
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    std::ifstream file(filePath, std::ios::binary);
    if (!file.is_open()) {
        localResult.error = "Failed to open PLY input file: " + filePath;
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    PlyHeader header;
    std::string parseError;
    if (!parseHeader(file, header, parseError)) {
        localResult.error = parseError.empty() ? "Failed to parse PLY header." : parseError;
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    localResult.encoding = header.encoding;
    localResult.headerByteCount = header.headerByteCount;
    const PlyElement* vertexElement = findVertexElement(header);
    if (vertexElement == nullptr) {
        localResult.error = "PLY file does not contain a vertex element.";
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    localResult.vertexCount = vertexElement->count;
    const std::vector<VertexPropertyReader> readers = makeVertexReaders(*vertexElement);
    if (!vertexReadersHavePosition(readers)) {
        localResult.error = "Gaussian PLY vertex data requires x, y, and z properties.";
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    if (!readVertexElement(file, header, *vertexElement, readers, options, localResult, gaussians)) {
        if (result != nullptr) {
            *result = localResult;
        }
        return false;
    }

    if (localResult.vertexCount == 0) {
        appendWarning(localResult, "PLY reader loaded an empty point cloud.");
    } else if (localResult.readCount == 0) {
        appendWarning(localResult, "PLY reader skipped all gaussian records as invalid.");
    } else if (localResult.skippedInvalidCount > 0) {
        appendWarning(
            localResult,
            "PLY reader skipped " + std::to_string(localResult.skippedInvalidCount) +
                " invalid gaussian records.");
    }

    if (result != nullptr) {
        *result = localResult;
    }
    return true;
}

} // namespace mesh2splat::io
