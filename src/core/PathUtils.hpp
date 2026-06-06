#pragma once

#include <cstddef>
#include <cstdint>
#include <initializer_list>
#include <string>
#include <string_view>

namespace mesh2splat::core {

enum class PathExtensionFormat : std::uint8_t {
    WithoutDot = 0,
    WithDot = 1,
};

constexpr char pathAsciiLower(char value)
{
    return value >= 'A' && value <= 'Z'
        ? static_cast<char>(value - 'A' + 'a')
        : value;
}

constexpr bool pathIsAsciiWhitespace(char value)
{
    return value == ' ' ||
        value == '\t' ||
        value == '\n' ||
        value == '\r' ||
        value == '\f' ||
        value == '\v';
}

constexpr bool isPathSeparator(char value)
{
    return value == '/' || value == '\\';
}

constexpr bool pathEqualsIgnoreCase(std::string_view lhs, std::string_view rhs)
{
    if (lhs.size() != rhs.size()) {
        return false;
    }

    for (std::size_t index = 0; index < lhs.size(); ++index) {
        if (pathAsciiLower(lhs[index]) != pathAsciiLower(rhs[index])) {
            return false;
        }
    }
    return true;
}

constexpr std::string_view trimAsciiWhitespace(std::string_view value)
{
    std::size_t first = 0;
    while (first < value.size() && pathIsAsciiWhitespace(value[first])) {
        ++first;
    }

    std::size_t last = value.size();
    while (last > first && pathIsAsciiWhitespace(value[last - 1])) {
        --last;
    }

    return value.substr(first, last - first);
}

constexpr bool isBlankPathInput(std::string_view value)
{
    for (char character : value) {
        if (!pathIsAsciiWhitespace(character)) {
            return false;
        }
    }
    return true;
}

constexpr std::string_view pathExtensionWithoutDotView(std::string_view extension)
{
    extension = trimAsciiWhitespace(extension);
    while (!extension.empty() && extension.front() == '.') {
        extension.remove_prefix(1);
    }
    return extension;
}

inline std::size_t pathFilenameStart(std::string_view path)
{
    const std::size_t separator = path.find_last_of("/\\");
    return separator == std::string_view::npos ? 0 : separator + 1;
}

inline std::size_t pathDirectoryEnd(std::string_view path)
{
    const std::size_t separator = path.find_last_of("/\\");
    return separator == std::string_view::npos ? 0 : separator + 1;
}

inline std::string_view pathDirectoryView(std::string_view path)
{
    return path.substr(0, pathDirectoryEnd(path));
}

inline std::string pathDirectory(std::string_view path)
{
    const std::string_view directory = pathDirectoryView(path);
    return std::string(directory);
}

inline std::string_view pathBasenameView(std::string_view path)
{
    return path.substr(pathFilenameStart(path));
}

inline std::string pathBasename(std::string_view path)
{
    const std::string_view basename = pathBasenameView(path);
    return std::string(basename);
}

inline std::size_t pathExtensionDotPosition(std::string_view path)
{
    const std::size_t filenameStart = pathFilenameStart(path);
    const std::size_t dot = path.find_last_of('.');
    if (dot == std::string_view::npos ||
        dot < filenameStart ||
        dot == filenameStart ||
        dot + 1 >= path.size()) {
        return std::string_view::npos;
    }
    return dot;
}

inline bool hasPathExtension(std::string_view path)
{
    return pathExtensionDotPosition(path) != std::string_view::npos;
}

inline std::size_t pathReplaceExtensionDotPosition(std::string_view path)
{
    const std::size_t filenameStart = pathFilenameStart(path);
    const std::size_t dot = path.find_last_of('.');
    if (dot == std::string_view::npos ||
        dot < filenameStart ||
        dot == filenameStart) {
        return std::string_view::npos;
    }
    return dot;
}

inline std::string_view pathStemView(std::string_view path)
{
    const std::size_t filenameStart = pathFilenameStart(path);
    const std::size_t dot = pathReplaceExtensionDotPosition(path);
    const std::size_t filenameEnd = dot == std::string_view::npos ? path.size() : dot;
    return path.substr(filenameStart, filenameEnd - filenameStart);
}

inline std::string pathStem(std::string_view path)
{
    const std::string_view stem = pathStemView(path);
    return std::string(stem);
}

inline std::string normalizeFileExtension(
    std::string_view extension,
    PathExtensionFormat format = PathExtensionFormat::WithDot)
{
    std::string_view normalized = pathExtensionWithoutDotView(extension);

    if (normalized.empty()) {
        return {};
    }

    std::string result;
    result.reserve(normalized.size() + (format == PathExtensionFormat::WithDot ? 1 : 0));
    if (format == PathExtensionFormat::WithDot) {
        result.push_back('.');
    }

    for (char character : normalized) {
        result.push_back(pathAsciiLower(character));
    }
    return result;
}

inline std::string_view pathExtensionView(
    std::string_view path,
    PathExtensionFormat format = PathExtensionFormat::WithDot)
{
    const std::size_t dot = pathExtensionDotPosition(path);
    if (dot == std::string_view::npos) {
        return {};
    }
    return format == PathExtensionFormat::WithDot
        ? path.substr(dot)
        : path.substr(dot + 1);
}

inline std::string pathExtension(
    std::string_view path,
    PathExtensionFormat format = PathExtensionFormat::WithDot)
{
    return normalizeFileExtension(pathExtensionView(path, PathExtensionFormat::WithoutDot), format);
}

inline bool pathExtensionEquals(std::string_view path, std::string_view extension)
{
    return pathEqualsIgnoreCase(
        pathExtensionView(path, PathExtensionFormat::WithoutDot),
        pathExtensionWithoutDotView(extension));
}

inline std::string replaceExtension(std::string_view path, std::string_view extension)
{
    const std::string normalizedExtension = normalizeFileExtension(extension);
    const std::size_t dot = pathReplaceExtensionDotPosition(path);
    std::string result = dot == std::string_view::npos
        ? std::string(path)
        : std::string(path.substr(0, dot));

    result += normalizedExtension;
    return result;
}

inline std::string appendExtensionIfMissing(std::string_view path, std::string_view extension)
{
    if (hasPathExtension(path)) {
        return std::string(path);
    }

    std::string result(path);
    result += normalizeFileExtension(extension);
    return result;
}

inline std::string pathDisplayName(std::string_view path, std::string_view fallback = "Untitled")
{
    const std::string_view stem = pathStemView(path);
    if (!stem.empty() && stem != "." && stem != "..") {
        return std::string(stem);
    }

    const std::string_view basename = pathBasenameView(path);
    if (!basename.empty() && basename != "." && basename != "..") {
        return std::string(basename);
    }

    return std::string(fallback);
}

inline std::string pathDisplayBasename(std::string_view path, std::string_view fallback = "Untitled")
{
    const std::string_view basename = pathBasenameView(path);
    if (!basename.empty() && basename != "." && basename != "..") {
        return std::string(basename);
    }

    return std::string(fallback);
}

inline bool hasPathFilename(std::string_view path)
{
    const std::string_view basename = pathBasenameView(path);
    return !basename.empty() && basename != "." && basename != "..";
}

inline bool isLikelyFilePath(std::string_view path)
{
    if (path.empty() || isBlankPathInput(path) || path.find('\0') != std::string_view::npos) {
        return false;
    }

    if (path.find("://") != std::string_view::npos) {
        return false;
    }

    return hasPathFilename(path);
}

inline std::string joinDiagnosticPath(std::string_view lhs, std::string_view rhs)
{
    if (lhs.empty()) {
        return std::string(rhs);
    }
    if (rhs.empty()) {
        return std::string(lhs);
    }

    const bool lhsHasSeparator = isPathSeparator(lhs.back());
    std::size_t rhsStart = 0;
    while (rhsStart < rhs.size() && isPathSeparator(rhs[rhsStart])) {
        ++rhsStart;
    }

    std::string joined;
    joined.reserve(lhs.size() + rhs.size() + (lhsHasSeparator ? 0 : 1));
    joined.append(lhs.data(), lhs.size());
    if (!lhsHasSeparator) {
        joined.push_back('/');
    }
    joined.append(rhs.data() + rhsStart, rhs.size() - rhsStart);
    return joined;
}

inline std::string joinDiagnosticPath(std::initializer_list<std::string_view> segments)
{
    std::string joined;
    for (std::string_view segment : segments) {
        if (segment.empty()) {
            continue;
        }

        joined = joined.empty()
            ? std::string(segment)
            : joinDiagnosticPath(joined, segment);
    }
    return joined;
}

} // namespace mesh2splat::core
