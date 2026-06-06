#pragma once

#include <cstddef>
#include <cstdint>
#include <limits>

namespace mesh2splat::metal {

class MetalSortPlanner {
public:
    static constexpr uint32_t kDefaultKeyBits = 32;
    static constexpr uint32_t kDefaultRadixBits = 4;
    static constexpr uint32_t kDefaultRadixBinCount = 16;
    static constexpr std::size_t kDefaultSortThreadgroupSize = 256;
    static constexpr std::size_t kKeyBytes = sizeof(uint32_t);
    static constexpr std::size_t kIndexBytes = sizeof(uint32_t);
    static constexpr std::size_t kCounterBytes = sizeof(uint32_t);

    enum class BufferRole : uint8_t {
        Primary,
        Scratch,
    };

    enum class ValidationStatus : uint8_t {
        Valid,
        InvalidConfig,
        EmptyCapacity,
        ItemCountExceedsCapacity,
        CapacityExceedsUInt32,
        BlockCountExceedsUInt32,
        ByteCountOverflow,
    };

    struct Config {
        uint32_t keyBits;
        uint32_t radixBits;
        std::size_t sortThreadgroupSize;

        constexpr Config()
            : keyBits(kDefaultKeyBits)
            , radixBits(kDefaultRadixBits)
            , sortThreadgroupSize(kDefaultSortThreadgroupSize)
        {
        }

        constexpr Config(
            uint32_t keyBitsValue,
            uint32_t radixBitsValue,
            std::size_t sortThreadgroupSizeValue)
            : keyBits(keyBitsValue)
            , radixBits(radixBitsValue)
            , sortThreadgroupSize(sortThreadgroupSizeValue)
        {
        }
    };

    struct ThreadgroupPlan {
        std::size_t sort = kDefaultSortThreadgroupSize;
        std::size_t prefix = kDefaultRadixBinCount;
        uint32_t radixBinCount = kDefaultRadixBinCount;
        uint32_t radixPassCount = (kDefaultKeyBits + kDefaultRadixBits - 1u) / kDefaultRadixBits;

        constexpr bool isValid() const
        {
            return sort > 0 && prefix > 0 && radixBinCount > 0 && radixPassCount > 0;
        }
    };

    struct ByteEstimate {
        std::size_t keyBytes = 0;
        std::size_t indexBytes = 0;
        std::size_t scratchKeyBytes = 0;
        std::size_t scratchIndexBytes = 0;
        std::size_t blockCountBytes = 0;
        std::size_t globalOffsetBytes = 0;
        std::size_t totalBytes = 0;
        bool overflowed = false;

        constexpr std::size_t primaryBytes() const { return keyBytes + indexBytes; }
        constexpr std::size_t pingPongBytes() const
        {
            return keyBytes + indexBytes + scratchKeyBytes + scratchIndexBytes;
        }
        constexpr std::size_t scratchBytes() const
        {
            return scratchKeyBytes + scratchIndexBytes + blockCountBytes + globalOffsetBytes;
        }
        constexpr std::size_t counterBytes() const { return blockCountBytes + globalOffsetBytes; }
        constexpr bool isValid() const { return !overflowed; }
    };

    struct PingPongPass {
        uint32_t passIndex = 0;
        uint32_t radixShift = 0;
        BufferRole sourceKeyRole = BufferRole::Primary;
        BufferRole sourceIndexRole = BufferRole::Primary;
        BufferRole destinationKeyRole = BufferRole::Scratch;
        BufferRole destinationIndexRole = BufferRole::Scratch;
    };

    struct PingPongPlan {
        uint32_t passCount = 0;
        BufferRole initialKeyRole = BufferRole::Primary;
        BufferRole initialIndexRole = BufferRole::Primary;
        BufferRole finalKeyRole = BufferRole::Primary;
        BufferRole finalIndexRole = BufferRole::Primary;
        bool finalIsPrimary = true;
        bool needsCopyToPrimary = false;
    };

    struct CapacityValidation {
        ValidationStatus status = ValidationStatus::Valid;
        std::size_t capacity = 0;
        std::size_t itemCount = 0;
        std::size_t blockCount = 0;
        std::size_t activeBlockCount = 0;
        std::size_t capacityBlockCount = 0;
        ByteEstimate bytes;

        constexpr bool isValid() const { return status == ValidationStatus::Valid; }
    };

    struct Plan {
        Config config;
        std::size_t itemCount = 0;
        std::size_t capacity = 0;
        std::size_t activeBlockCount = 0;
        std::size_t capacityBlockCount = 0;
        uint32_t radixBinCount = 0;
        uint32_t radixPassCount = 0;
        ThreadgroupPlan threadgroups;
        ByteEstimate bytes;
        PingPongPlan pingPong;
        CapacityValidation validation;

        constexpr bool isValid() const { return validation.isValid(); }
        constexpr bool hasWork() const { return isValid() && itemCount > 0; }
        constexpr bool needsRadixSort() const { return hasWork() && itemCount > 1; }
    };

    static constexpr Config defaultConfig()
    {
        return Config();
    }

    static constexpr std::size_t maxSupportedCapacity()
    {
        return maxUInt32AsSize();
    }

    static constexpr uint32_t radixBinCount(uint32_t radixBits = kDefaultRadixBits)
    {
        return radixBits == 0 || radixBits >= 32 ? 0u : (uint32_t{1} << radixBits);
    }

    static constexpr uint32_t radixPassCount(
        uint32_t keyBits = kDefaultKeyBits,
        uint32_t radixBits = kDefaultRadixBits)
    {
        return keyBits == 0 || radixBits == 0 ? 0u : ((keyBits + radixBits - 1u) / radixBits);
    }

    static constexpr uint32_t radixMask(uint32_t radixBits = kDefaultRadixBits)
    {
        const uint32_t bins = radixBinCount(radixBits);
        return bins == 0 ? 0u : bins - 1u;
    }

    static constexpr std::size_t blockCount(
        std::size_t itemCount,
        std::size_t threadgroupSize = kDefaultSortThreadgroupSize)
    {
        return threadgroupSize == 0 || itemCount == 0 ? 0 : (1 + ((itemCount - 1) / threadgroupSize));
    }

    static constexpr bool isValidConfig()
    {
        return isConfigValid(defaultConfig());
    }

    static constexpr bool isValidConfig(const Config& config)
    {
        return isConfigValid(config);
    }

    static constexpr ThreadgroupPlan threadgroupPlan()
    {
        return threadgroupPlan(defaultConfig());
    }

    static constexpr ThreadgroupPlan threadgroupPlan(const Config& config)
    {
        ThreadgroupPlan plan;
        plan.sort = config.sortThreadgroupSize;
        plan.radixBinCount = radixBinCount(config.radixBits);
        plan.radixPassCount = radixPassCount(config.keyBits, config.radixBits);
        plan.prefix = plan.radixBinCount;
        return plan;
    }

    static constexpr PingPongPass pingPongPass(uint32_t passIndex)
    {
        return pingPongPass(passIndex, defaultConfig());
    }

    static constexpr PingPongPass pingPongPass(
        uint32_t passIndex,
        const Config& config)
    {
        PingPongPass pass;
        pass.passIndex = passIndex;
        pass.radixShift = passIndex * config.radixBits;
        if ((passIndex & 1u) == 0u) {
            pass.sourceKeyRole = BufferRole::Primary;
            pass.sourceIndexRole = BufferRole::Primary;
            pass.destinationKeyRole = BufferRole::Scratch;
            pass.destinationIndexRole = BufferRole::Scratch;
            return pass;
        }

        pass.sourceKeyRole = BufferRole::Scratch;
        pass.sourceIndexRole = BufferRole::Scratch;
        pass.destinationKeyRole = BufferRole::Primary;
        pass.destinationIndexRole = BufferRole::Primary;
        return pass;
    }

    static constexpr PingPongPlan pingPongPlan(uint32_t passCount)
    {
        PingPongPlan plan;
        plan.passCount = passCount;
        const bool finalIsPrimary = (passCount & 1u) == 0u;
        plan.finalKeyRole = finalIsPrimary ? BufferRole::Primary : BufferRole::Scratch;
        plan.finalIndexRole = finalIsPrimary ? BufferRole::Primary : BufferRole::Scratch;
        plan.finalIsPrimary = finalIsPrimary;
        plan.needsCopyToPrimary = !finalIsPrimary;
        return plan;
    }

    static constexpr ByteEstimate estimateBytes(std::size_t capacity)
    {
        return estimateBytes(capacity, defaultConfig());
    }

    static constexpr ByteEstimate estimateBytes(std::size_t capacity, const Config& config)
    {
        ByteEstimate estimate;
        const uint32_t bins = radixBinCount(config.radixBits);
        const std::size_t blocks = blockCount(capacity, config.sortThreadgroupSize);

        if (!isConfigValid(config) || capacity == 0 || bins == 0 || blocks == 0) {
            return estimate;
        }

        std::size_t blockCounterCount = 0;
        if (!checkedMultiply(capacity, kKeyBytes, estimate.keyBytes) ||
            !checkedMultiply(capacity, kIndexBytes, estimate.indexBytes) ||
            !checkedMultiply(capacity, kKeyBytes, estimate.scratchKeyBytes) ||
            !checkedMultiply(capacity, kIndexBytes, estimate.scratchIndexBytes) ||
            !checkedMultiply(blocks, static_cast<std::size_t>(bins), blockCounterCount) ||
            !checkedMultiply(blockCounterCount, kCounterBytes, estimate.blockCountBytes) ||
            !checkedMultiply(static_cast<std::size_t>(bins), kCounterBytes, estimate.globalOffsetBytes) ||
            !checkedAddMany(
                estimate.keyBytes,
                estimate.indexBytes,
                estimate.scratchKeyBytes,
                estimate.scratchIndexBytes,
                estimate.blockCountBytes,
                estimate.globalOffsetBytes,
                estimate.totalBytes)) {
            estimate.overflowed = true;
        }

        return estimate;
    }

    static constexpr CapacityValidation validateCapacity(std::size_t capacity)
    {
        return validateCapacity(capacity, defaultConfig());
    }

    static constexpr CapacityValidation validateCapacity(std::size_t capacity, const Config& config)
    {
        return validateCapacityForItemCount(capacity, capacity, config);
    }

    static constexpr CapacityValidation validateCapacityForItemCount(
        std::size_t capacity,
        std::size_t itemCount)
    {
        return validateCapacityForItemCount(capacity, itemCount, defaultConfig());
    }

    static constexpr CapacityValidation validateCapacityForItemCount(
        std::size_t capacity,
        std::size_t itemCount,
        const Config& config)
    {
        CapacityValidation validation;
        validation.capacity = capacity;
        validation.itemCount = itemCount;

        if (!isConfigValid(config)) {
            validation.status = ValidationStatus::InvalidConfig;
            return validation;
        }

        validation.activeBlockCount = blockCount(itemCount, config.sortThreadgroupSize);
        validation.capacityBlockCount = blockCount(capacity, config.sortThreadgroupSize);
        validation.blockCount = validation.capacityBlockCount;

        if (capacity == 0) {
            validation.status = itemCount == 0 ?
                ValidationStatus::Valid :
                ValidationStatus::EmptyCapacity;
            validation.bytes = estimateBytes(capacity, config);
            return validation;
        }

        if (itemCount > capacity) {
            validation.status = ValidationStatus::ItemCountExceedsCapacity;
            return validation;
        }

        if (capacity > maxUInt32AsSize()) {
            validation.status = ValidationStatus::CapacityExceedsUInt32;
            return validation;
        }

        if (validation.blockCount == 0 || validation.blockCount > maxUInt32AsSize()) {
            validation.status = ValidationStatus::BlockCountExceedsUInt32;
            return validation;
        }

        validation.bytes = estimateBytes(capacity, config);
        if (!validation.bytes.isValid()) {
            validation.status = ValidationStatus::ByteCountOverflow;
            return validation;
        }

        validation.status = ValidationStatus::Valid;
        return validation;
    }

    static constexpr Plan makePlan(
        std::size_t itemCount,
        std::size_t capacity,
        const Config& config)
    {
        Plan plan;
        plan.config = config;
        plan.itemCount = itemCount;
        plan.capacity = capacity;
        plan.activeBlockCount = blockCount(itemCount, config.sortThreadgroupSize);
        plan.capacityBlockCount = blockCount(capacity, config.sortThreadgroupSize);
        plan.radixBinCount = radixBinCount(config.radixBits);
        plan.radixPassCount = MetalSortPlanner::radixPassCount(config.keyBits, config.radixBits);
        plan.threadgroups = threadgroupPlan(config);
        plan.bytes = estimateBytes(capacity, config);
        plan.pingPong = pingPongPlan(plan.radixPassCount);
        plan.validation = validateCapacityForItemCount(capacity, itemCount, config);
        return plan;
    }

    static constexpr Plan makePlan(std::size_t itemCount, std::size_t capacity)
    {
        return makePlan(itemCount, capacity, defaultConfig());
    }

    static constexpr Plan makePlan(std::size_t itemCount, const Config& config = Config())
    {
        return makePlan(itemCount, itemCount, config);
    }

    static constexpr const char* bufferRoleName(BufferRole role)
    {
        switch (role) {
        case BufferRole::Primary:
            return "primary";
        case BufferRole::Scratch:
            return "scratch";
        }

        return "unknown";
    }

    static constexpr const char* validationStatusName(ValidationStatus status)
    {
        switch (status) {
        case ValidationStatus::Valid:
            return "valid";
        case ValidationStatus::InvalidConfig:
            return "invalid-config";
        case ValidationStatus::EmptyCapacity:
            return "empty-capacity";
        case ValidationStatus::ItemCountExceedsCapacity:
            return "item-count-exceeds-capacity";
        case ValidationStatus::CapacityExceedsUInt32:
            return "capacity-exceeds-uint32";
        case ValidationStatus::BlockCountExceedsUInt32:
            return "block-count-exceeds-uint32";
        case ValidationStatus::ByteCountOverflow:
            return "byte-count-overflow";
        }

        return "unknown";
    }

private:
    static constexpr bool isConfigValid(const Config& config)
    {
        return config.keyBits > 0 &&
            config.keyBits <= 32 &&
            config.radixBits > 0 &&
            config.radixBits < 32 &&
            config.sortThreadgroupSize > 0 &&
            radixBinCount(config.radixBits) > 0;
    }

    static constexpr std::size_t maxUInt32AsSize()
    {
        return static_cast<std::size_t>(std::numeric_limits<uint32_t>::max());
    }

    static constexpr bool checkedAdd(
        std::size_t lhs,
        std::size_t rhs,
        std::size_t& result)
    {
        if (rhs > std::numeric_limits<std::size_t>::max() - lhs) {
            result = std::numeric_limits<std::size_t>::max();
            return false;
        }

        result = lhs + rhs;
        return true;
    }

    static constexpr bool checkedMultiply(
        std::size_t lhs,
        std::size_t rhs,
        std::size_t& result)
    {
        if (lhs != 0 && rhs > std::numeric_limits<std::size_t>::max() / lhs) {
            result = std::numeric_limits<std::size_t>::max();
            return false;
        }

        result = lhs * rhs;
        return true;
    }

    static constexpr bool checkedAddMany(
        std::size_t first,
        std::size_t second,
        std::size_t third,
        std::size_t fourth,
        std::size_t fifth,
        std::size_t sixth,
        std::size_t& result)
    {
        std::size_t total = 0;
        return checkedAdd(total, first, total) &&
            checkedAdd(total, second, total) &&
            checkedAdd(total, third, total) &&
            checkedAdd(total, fourth, total) &&
            checkedAdd(total, fifth, total) &&
            checkedAdd(total, sixth, total) &&
            checkedAdd(0, total, result);
    }
};

} // namespace mesh2splat::metal
