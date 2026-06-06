#pragma once

#include <cmath>
#include <cstddef>
#include <limits>
#include <type_traits>

namespace mesh2splat::core {

template <typename T>
struct NumericRange {
    T minimum;
    T maximum;

    constexpr bool contains(T value) const
    {
        return !(value < minimum) && !(maximum < value);
    }
};

template <typename T>
constexpr NumericRange<T> orderedRange(T minimum, T maximum)
{
    static_assert(std::is_arithmetic<T>::value, "orderedRange requires an arithmetic type.");

    return maximum < minimum ? NumericRange<T>{maximum, minimum} : NumericRange<T>{minimum, maximum};
}

template <typename T>
constexpr T safeClamp(T value, T minimum, T maximum)
{
    static_assert(std::is_arithmetic<T>::value, "safeClamp requires an arithmetic type.");

    const NumericRange<T> range = orderedRange(minimum, maximum);

    if (value < range.minimum) {
        return range.minimum;
    }
    if (range.maximum < value) {
        return range.maximum;
    }
    return value;
}

template <typename T>
inline bool isFiniteNumber(T value)
{
    static_assert(std::is_arithmetic<T>::value, "isFiniteNumber requires an arithmetic type.");

    if constexpr (std::is_floating_point<T>::value) {
        return std::isfinite(value);
    } else {
        (void)value;
        return true;
    }
}

template <typename T>
inline T finiteOr(T value, T fallback)
{
    static_assert(std::is_floating_point<T>::value, "finiteOr requires a floating-point type.");

    return std::isfinite(value) ? value : fallback;
}

template <typename T>
inline T clampFinite(T value, T minimum, T maximum, T fallback)
{
    static_assert(std::is_floating_point<T>::value, "clampFinite requires a floating-point type.");

    const NumericRange<T> range = orderedRange(minimum, maximum);
    const T safeFallback = std::isfinite(fallback) ? safeClamp(fallback, range.minimum, range.maximum) : range.minimum;
    if (!std::isfinite(value)) {
        return safeFallback;
    }

    return safeClamp(value, range.minimum, range.maximum);
}

template <typename T>
inline bool isFiniteRange(T minimum, T maximum)
{
    static_assert(std::is_floating_point<T>::value, "isFiniteRange requires a floating-point type.");

    return std::isfinite(minimum) && std::isfinite(maximum);
}

template <typename T>
constexpr T saturatingAdd(T lhs, T rhs)
{
    static_assert(std::is_unsigned<T>::value, "saturatingAdd requires an unsigned integer type.");

    const T maxValue = std::numeric_limits<T>::max();
    if (rhs > maxValue - lhs) {
        return maxValue;
    }
    return lhs + rhs;
}

template <typename T>
constexpr T saturatingMultiply(T lhs, T rhs)
{
    static_assert(std::is_unsigned<T>::value, "saturatingMultiply requires an unsigned integer type.");

    if (lhs == 0 || rhs == 0) {
        return 0;
    }

    const T maxValue = std::numeric_limits<T>::max();
    if (lhs > maxValue / rhs) {
        return maxValue;
    }
    return lhs * rhs;
}

template <typename T>
constexpr bool checkedAdd(T lhs, T rhs, T& result)
{
    static_assert(std::is_unsigned<T>::value, "checkedAdd requires an unsigned integer type.");

    const T maxValue = std::numeric_limits<T>::max();
    if (rhs > maxValue - lhs) {
        result = 0;
        return false;
    }

    result = lhs + rhs;
    return true;
}

template <typename T>
constexpr bool checkedMultiply(T lhs, T rhs, T& result)
{
    static_assert(std::is_unsigned<T>::value, "checkedMultiply requires an unsigned integer type.");

    if (lhs != 0 && rhs > std::numeric_limits<T>::max() / lhs) {
        result = 0;
        return false;
    }

    result = lhs * rhs;
    return true;
}

constexpr bool checkedByteSize(std::size_t elementCount, std::size_t elementSize, std::size_t& byteSize)
{
    return checkedMultiply(elementCount, elementSize, byteSize);
}

template <typename T>
constexpr bool checkedByteSizeFor(std::size_t elementCount, std::size_t& byteSize)
{
    return checkedByteSize(elementCount, sizeof(T), byteSize);
}

template <typename T>
inline bool isFiniteArray(const T* values, std::size_t count)
{
    static_assert(std::is_floating_point<T>::value, "isFiniteArray requires a floating-point type.");

    if (values == nullptr) {
        return count == 0;
    }

    for (std::size_t index = 0; index < count; ++index) {
        if (!std::isfinite(values[index])) {
            return false;
        }
    }
    return true;
}

constexpr bool isPowerOfTwo(std::size_t value)
{
    return value != 0 && (value & (value - 1)) == 0;
}

constexpr bool isValidAlignment(std::size_t alignment)
{
    return alignment != 0;
}

constexpr std::size_t ceilDiv(std::size_t value, std::size_t divisor)
{
    if (value == 0 || divisor == 0) {
        return 0;
    }

    return 1 + ((value - 1) / divisor);
}

constexpr std::size_t alignDown(std::size_t value, std::size_t alignment)
{
    if (alignment <= 1) {
        return value;
    }

    return value - (value % alignment);
}

constexpr std::size_t alignmentPadding(std::size_t value, std::size_t alignment)
{
    if (alignment <= 1) {
        return 0;
    }

    const std::size_t remainder = value % alignment;
    return remainder == 0 ? 0 : alignment - remainder;
}

constexpr std::size_t alignUp(std::size_t value, std::size_t alignment)
{
    return saturatingAdd(value, alignmentPadding(value, alignment));
}

constexpr bool checkedAlignUp(std::size_t value, std::size_t alignment, std::size_t& alignedValue)
{
    return checkedAdd(value, alignmentPadding(value, alignment), alignedValue);
}

constexpr bool isAligned(std::size_t value, std::size_t alignment)
{
    return alignment <= 1 || value % alignment == 0;
}

constexpr std::size_t nextPowerOfTwo(std::size_t value)
{
    if (value <= 1) {
        return 1;
    }

    std::size_t power = 1;
    while (power < value) {
        if (power > std::numeric_limits<std::size_t>::max() / 2) {
            return std::numeric_limits<std::size_t>::max();
        }
        power *= 2;
    }
    return power;
}

} // namespace mesh2splat::core
