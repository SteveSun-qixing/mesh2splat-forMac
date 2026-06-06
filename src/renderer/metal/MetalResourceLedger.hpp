#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <sstream>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

namespace mesh2splat::metal {

enum class MetalResourceKind : uint8_t {
    Unknown,
    Buffer,
    Texture,
    RenderTarget,
    DepthStencil,
    Heap,
    Transient,
};

enum class MetalResourceStorageMode : uint8_t {
    Unknown,
    Shared,
    SharedWriteCombined,
    Private,
    Managed,
    Memoryless,
};

inline constexpr std::size_t kMetalResourceKindCount = static_cast<std::size_t>(MetalResourceKind::Transient) + 1;
inline constexpr std::size_t kMetalResourceStorageModeCount =
    static_cast<std::size_t>(MetalResourceStorageMode::Memoryless) + 1;

enum class MetalResourceBudgetState : uint8_t {
    Unbounded,
    WithinBudget,
    AtBudget,
    OverBudget,
};

inline const char* metalResourceKindName(MetalResourceKind kind)
{
    switch (kind) {
    case MetalResourceKind::Buffer:
        return "Buffer";
    case MetalResourceKind::Texture:
        return "Texture";
    case MetalResourceKind::RenderTarget:
        return "RenderTarget";
    case MetalResourceKind::DepthStencil:
        return "DepthStencil";
    case MetalResourceKind::Heap:
        return "Heap";
    case MetalResourceKind::Transient:
        return "Transient";
    case MetalResourceKind::Unknown:
    default:
        return "Unknown";
    }
}

inline const char* metalResourceStorageModeName(MetalResourceStorageMode storageMode)
{
    switch (storageMode) {
    case MetalResourceStorageMode::Shared:
        return "Shared";
    case MetalResourceStorageMode::SharedWriteCombined:
        return "SharedWriteCombined";
    case MetalResourceStorageMode::Private:
        return "Private";
    case MetalResourceStorageMode::Managed:
        return "Managed";
    case MetalResourceStorageMode::Memoryless:
        return "Memoryless";
    case MetalResourceStorageMode::Unknown:
    default:
        return "Unknown";
    }
}

inline const char* metalResourceBudgetStateName(MetalResourceBudgetState state)
{
    switch (state) {
    case MetalResourceBudgetState::Unbounded:
        return "unbounded";
    case MetalResourceBudgetState::WithinBudget:
        return "within-budget";
    case MetalResourceBudgetState::AtBudget:
        return "at-budget";
    case MetalResourceBudgetState::OverBudget:
        return "over-budget";
    }

    return "unknown";
}

namespace detail {

inline std::size_t metalResourceAddSaturating(std::size_t lhs, std::size_t rhs)
{
    const std::size_t maxValue = (std::numeric_limits<std::size_t>::max)();
    return lhs > maxValue - rhs ? maxValue : lhs + rhs;
}

inline void metalResourceSubtractSaturating(std::size_t& value, std::size_t amount)
{
    value -= std::min(value, amount);
}

inline bool metalResourceIsLabelSeparator(char value)
{
    const auto byte = static_cast<unsigned char>(value);
    return byte <= 0x20u || byte == 0x7fu;
}

inline std::string metalResourceCleanLabel(std::string_view value, std::string_view fallback = {})
{
    auto clean = [](std::string_view source) {
        std::string result;
        result.reserve(source.size());

        bool pendingSpace = false;
        for (char character : source) {
            if (metalResourceIsLabelSeparator(character)) {
                pendingSpace = !result.empty();
                continue;
            }

            if (pendingSpace) {
                result.push_back(' ');
                pendingSpace = false;
            }
            result.push_back(character);
        }

        return result;
    };

    std::string result = clean(value);
    if (result.empty() && !fallback.empty()) {
        result = clean(fallback);
    }
    return result;
}

} // namespace detail

struct MetalResourceRecord {
    MetalResourceKind kind = MetalResourceKind::Unknown;
    MetalResourceStorageMode storageMode = MetalResourceStorageMode::Unknown;
    std::size_t byteSize = 0;
    std::string label;
    std::string ownerPass;
    uint64_t creationSerial = 0;

    bool isValid() const { return creationSerial != 0; }

    bool hasLabel() const { return !label.empty(); }

    bool hasOwnerPass() const { return !ownerPass.empty(); }

    std::string diagnosticLabel() const
    {
        std::string result = detail::metalResourceCleanLabel(label);
        if (result.empty()) {
            result = std::string("Metal ") + metalResourceKindName(kind);
        }

        result += " [serial=" + std::to_string(creationSerial) + "]";
        result += " [kind=" + std::string(metalResourceKindName(kind)) + "]";
        result += " [storage=" + std::string(metalResourceStorageModeName(storageMode)) + "]";
        result += " [bytes=" + std::to_string(byteSize) + "]";

        const std::string cleanOwner = detail::metalResourceCleanLabel(ownerPass);
        if (!cleanOwner.empty()) {
            result += " [owner=" + cleanOwner + "]";
        }

        return result;
    }
};

struct MetalResourceAddDesc {
    MetalResourceKind kind = MetalResourceKind::Unknown;
    MetalResourceStorageMode storageMode = MetalResourceStorageMode::Unknown;
    std::size_t byteSize = 0;
    std::string label;
    std::string ownerPass;
};

struct MetalResourceTotals {
    std::size_t resourceCount = 0;
    std::size_t totalBytes = 0;
    std::size_t sharedBytes = 0;
    std::size_t sharedWriteCombinedBytes = 0;
    std::size_t privateBytes = 0;
    std::size_t managedBytes = 0;
    std::size_t memorylessBytes = 0;
    std::size_t unknownStorageBytes = 0;
    std::size_t largestResourceBytes = 0;
    uint64_t latestCreationSerial = 0;

    bool empty() const { return resourceCount == 0; }
};

struct MetalResourceBucketTotals {
    std::size_t resourceCount = 0;
    std::size_t totalBytes = 0;

    bool empty() const { return resourceCount == 0; }

    std::size_t averageBytes() const
    {
        return resourceCount == 0 ? 0 : totalBytes / resourceCount;
    }
};

struct MetalResourceSummary {
    MetalResourceTotals totals;
    std::array<MetalResourceBucketTotals, kMetalResourceKindCount> byKind = {};
    std::array<MetalResourceBucketTotals, kMetalResourceStorageModeCount> byStorageMode = {};
    std::size_t budgetBytes = 0;
    std::size_t remainingBudgetBytes = 0;
    std::size_t budgetOverageBytes = 0;
    bool hasBudget = false;
    bool overBudget = false;
    MetalResourceBudgetState budgetState = MetalResourceBudgetState::Unbounded;

    double budgetUsageRatio() const
    {
        return hasBudget && budgetBytes != 0 ?
            static_cast<double>(totals.totalBytes) / static_cast<double>(budgetBytes) :
            0.0;
    }
};

class MetalResourceLedger {
public:
    using Serial = uint64_t;

    static constexpr std::size_t kResourceKindCount = kMetalResourceKindCount;
    static constexpr std::size_t kStorageModeCount = kMetalResourceStorageModeCount;

    Serial add(const MetalResourceAddDesc& desc)
    {
        MetalResourceRecord record;
        record.kind = desc.kind;
        record.storageMode = desc.storageMode;
        record.byteSize = desc.byteSize;
        record.label = desc.label;
        record.ownerPass = desc.ownerPass;
        record.creationSerial = nextCreationSerial();

        const Serial serial = record.creationSerial;
        addTotals(record);
        m_records.emplace(serial, std::move(record));
        return serial;
    }

    Serial add(
        MetalResourceKind kind,
        MetalResourceStorageMode storageMode,
        std::size_t byteSize,
        const char* label = nullptr,
        const char* ownerPass = nullptr)
    {
        MetalResourceAddDesc desc;
        desc.kind = kind;
        desc.storageMode = storageMode;
        desc.byteSize = byteSize;
        desc.label = label ? label : "";
        desc.ownerPass = ownerPass ? ownerPass : "";
        return add(desc);
    }

    bool remove(Serial creationSerial)
    {
        const auto iter = m_records.find(creationSerial);
        if (iter == m_records.end()) {
            return false;
        }

        subtractTotals(iter->second);
        m_records.erase(iter);
        refreshExtrema();
        return true;
    }

    bool update(Serial creationSerial, const MetalResourceAddDesc& desc)
    {
        const auto iter = m_records.find(creationSerial);
        if (iter == m_records.end()) {
            return false;
        }

        subtractTotals(iter->second);
        iter->second.kind = desc.kind;
        iter->second.storageMode = desc.storageMode;
        iter->second.byteSize = desc.byteSize;
        iter->second.label = desc.label;
        iter->second.ownerPass = desc.ownerPass;
        addTotals(iter->second);
        refreshExtrema();
        return true;
    }

    bool updateByteSize(Serial creationSerial, std::size_t byteSize)
    {
        const auto iter = m_records.find(creationSerial);
        if (iter == m_records.end()) {
            return false;
        }

        subtractTotals(iter->second);
        iter->second.byteSize = byteSize;
        addTotals(iter->second);
        refreshExtrema();
        return true;
    }

    bool updateStorageMode(Serial creationSerial, MetalResourceStorageMode storageMode)
    {
        const auto iter = m_records.find(creationSerial);
        if (iter == m_records.end()) {
            return false;
        }

        subtractTotals(iter->second);
        iter->second.storageMode = storageMode;
        addTotals(iter->second);
        return true;
    }

    bool updateOwnerPass(Serial creationSerial, const char* ownerPass)
    {
        const auto iter = m_records.find(creationSerial);
        if (iter == m_records.end()) {
            return false;
        }

        iter->second.ownerPass = ownerPass ? ownerPass : "";
        return true;
    }

    bool updateLabel(Serial creationSerial, const char* label)
    {
        const auto iter = m_records.find(creationSerial);
        if (iter == m_records.end()) {
            return false;
        }

        iter->second.label = label ? label : "";
        return true;
    }

    void clear()
    {
        m_records.clear();
        m_totals = {};
        m_byKind = {};
        m_byStorageMode = {};
    }

    const MetalResourceRecord* find(Serial creationSerial) const
    {
        const auto iter = m_records.find(creationSerial);
        return iter == m_records.end() ? nullptr : &iter->second;
    }

    bool contains(Serial creationSerial) const { return find(creationSerial) != nullptr; }

    std::vector<MetalResourceRecord> records() const
    {
        std::vector<MetalResourceRecord> result;
        result.reserve(m_records.size());
        for (const auto& entry : m_records) {
            result.push_back(entry.second);
        }
        std::sort(result.begin(), result.end(), [](const MetalResourceRecord& lhs, const MetalResourceRecord& rhs) {
            return lhs.creationSerial < rhs.creationSerial;
        });
        return result;
    }

    MetalResourceSummary summary() const
    {
        MetalResourceSummary result;
        result.totals = m_totals;
        result.byKind = m_byKind;
        result.byStorageMode = m_byStorageMode;
        result.budgetBytes = m_budgetBytes;
        result.hasBudget = m_budgetBytes > 0;
        result.overBudget = result.hasBudget && m_totals.totalBytes > m_budgetBytes;
        result.remainingBudgetBytes = remainingBudgetBytes();
        result.budgetOverageBytes = budgetOverageBytes();
        result.budgetState = budgetState();
        return result;
    }

    const MetalResourceTotals& totals() const { return m_totals; }
    const std::array<MetalResourceBucketTotals, kResourceKindCount>& totalsByKind() const { return m_byKind; }
    const std::array<MetalResourceBucketTotals, kStorageModeCount>& totalsByStorageMode() const
    {
        return m_byStorageMode;
    }

    MetalResourceBucketTotals totalsForKind(MetalResourceKind kind) const { return m_byKind[kindIndex(kind)]; }
    MetalResourceBucketTotals totalsForStorageMode(MetalResourceStorageMode storageMode) const
    {
        return m_byStorageMode[storageModeIndex(storageMode)];
    }

    std::size_t totalBytes() const { return m_totals.totalBytes; }
    std::size_t resourceCount() const { return m_totals.resourceCount; }
    bool empty() const { return m_records.empty(); }

    void setBudgetBytes(std::size_t budgetBytes) { m_budgetBytes = budgetBytes; }
    std::size_t budgetBytes() const { return m_budgetBytes; }
    bool hasBudget() const { return m_budgetBytes > 0; }
    bool isOverBudget() const { return hasBudget() && m_totals.totalBytes > m_budgetBytes; }
    std::size_t remainingBudgetBytes() const
    {
        if (!hasBudget() || isOverBudget()) {
            return 0;
        }

        return m_budgetBytes - m_totals.totalBytes;
    }

    std::size_t budgetOverageBytes() const
    {
        if (!hasBudget() || !isOverBudget()) {
            return 0;
        }

        return m_totals.totalBytes - m_budgetBytes;
    }

    MetalResourceBudgetState budgetState() const
    {
        if (!hasBudget()) {
            return MetalResourceBudgetState::Unbounded;
        }
        if (m_totals.totalBytes > m_budgetBytes) {
            return MetalResourceBudgetState::OverBudget;
        }
        if (m_totals.totalBytes == m_budgetBytes) {
            return MetalResourceBudgetState::AtBudget;
        }
        return MetalResourceBudgetState::WithinBudget;
    }

    std::string describeSummary() const
    {
        const MetalResourceSummary currentSummary = summary();
        std::ostringstream stream;
        stream << "MetalResourceLedger resources=" << currentSummary.totals.resourceCount
               << " bytes=" << currentSummary.totals.totalBytes
               << " shared=" << currentSummary.totals.sharedBytes
               << " sharedWriteCombined=" << currentSummary.totals.sharedWriteCombinedBytes
               << " private=" << currentSummary.totals.privateBytes
               << " managed=" << currentSummary.totals.managedBytes
               << " memoryless=" << currentSummary.totals.memorylessBytes
               << " unknownStorage=" << currentSummary.totals.unknownStorageBytes;

        if (currentSummary.hasBudget) {
            stream << " budget=" << currentSummary.budgetBytes
                   << " remaining=" << currentSummary.remainingBudgetBytes
                   << " overage=" << currentSummary.budgetOverageBytes
                   << " budgetState=" << metalResourceBudgetStateName(currentSummary.budgetState);
        }

        return stream.str();
    }

    std::string diagnosticLabel(Serial creationSerial) const
    {
        const MetalResourceRecord* record = find(creationSerial);
        return record ? record->diagnosticLabel() : std::string();
    }

    std::string describeResource(Serial creationSerial) const
    {
        const MetalResourceRecord* record = find(creationSerial);
        if (!record) {
            return {};
        }

        std::ostringstream stream;
        stream << "serial=" << record->creationSerial
               << " kind=" << resourceKindName(record->kind)
               << " storage=" << storageModeName(record->storageMode)
               << " bytes=" << record->byteSize;

        if (!record->label.empty()) {
            stream << " label=" << record->label;
        }
        if (!record->ownerPass.empty()) {
            stream << " ownerPass=" << record->ownerPass;
        }

        return stream.str();
    }

    static const char* resourceKindName(MetalResourceKind kind)
    {
        return metalResourceKindName(kind);
    }

    static const char* storageModeName(MetalResourceStorageMode storageMode)
    {
        return metalResourceStorageModeName(storageMode);
    }

private:
    static std::size_t kindIndex(MetalResourceKind kind)
    {
        const std::size_t index = static_cast<std::size_t>(kind);
        return index < kResourceKindCount ? index : 0;
    }

    static std::size_t storageModeIndex(MetalResourceStorageMode storageMode)
    {
        const std::size_t index = static_cast<std::size_t>(storageMode);
        return index < kStorageModeCount ? index : 0;
    }

    Serial nextCreationSerial()
    {
        ++m_nextCreationSerial;
        if (m_nextCreationSerial == 0) {
            ++m_nextCreationSerial;
        }
        return m_nextCreationSerial;
    }

    void addTotals(const MetalResourceRecord& record)
    {
        m_totals.resourceCount = detail::metalResourceAddSaturating(m_totals.resourceCount, 1);
        m_totals.totalBytes = detail::metalResourceAddSaturating(m_totals.totalBytes, record.byteSize);
        m_totals.latestCreationSerial = std::max(m_totals.latestCreationSerial, record.creationSerial);
        m_totals.largestResourceBytes = std::max(m_totals.largestResourceBytes, record.byteSize);

        auto& kindTotals = m_byKind[kindIndex(record.kind)];
        kindTotals.resourceCount = detail::metalResourceAddSaturating(kindTotals.resourceCount, 1);
        kindTotals.totalBytes = detail::metalResourceAddSaturating(kindTotals.totalBytes, record.byteSize);

        auto& storageTotals = m_byStorageMode[storageModeIndex(record.storageMode)];
        storageTotals.resourceCount = detail::metalResourceAddSaturating(storageTotals.resourceCount, 1);
        storageTotals.totalBytes = detail::metalResourceAddSaturating(storageTotals.totalBytes, record.byteSize);

        switch (record.storageMode) {
        case MetalResourceStorageMode::Shared:
            m_totals.sharedBytes = detail::metalResourceAddSaturating(m_totals.sharedBytes, record.byteSize);
            break;
        case MetalResourceStorageMode::SharedWriteCombined:
            m_totals.sharedBytes = detail::metalResourceAddSaturating(m_totals.sharedBytes, record.byteSize);
            m_totals.sharedWriteCombinedBytes =
                detail::metalResourceAddSaturating(m_totals.sharedWriteCombinedBytes, record.byteSize);
            break;
        case MetalResourceStorageMode::Private:
            m_totals.privateBytes = detail::metalResourceAddSaturating(m_totals.privateBytes, record.byteSize);
            break;
        case MetalResourceStorageMode::Managed:
            m_totals.managedBytes = detail::metalResourceAddSaturating(m_totals.managedBytes, record.byteSize);
            break;
        case MetalResourceStorageMode::Memoryless:
            m_totals.memorylessBytes = detail::metalResourceAddSaturating(m_totals.memorylessBytes, record.byteSize);
            break;
        case MetalResourceStorageMode::Unknown:
        default:
            m_totals.unknownStorageBytes =
                detail::metalResourceAddSaturating(m_totals.unknownStorageBytes, record.byteSize);
            break;
        }
    }

    void subtractTotals(const MetalResourceRecord& record)
    {
        if (m_totals.resourceCount > 0) {
            --m_totals.resourceCount;
        }
        detail::metalResourceSubtractSaturating(m_totals.totalBytes, record.byteSize);

        auto& kindTotals = m_byKind[kindIndex(record.kind)];
        if (kindTotals.resourceCount > 0) {
            --kindTotals.resourceCount;
        }
        detail::metalResourceSubtractSaturating(kindTotals.totalBytes, record.byteSize);

        auto& storageTotals = m_byStorageMode[storageModeIndex(record.storageMode)];
        if (storageTotals.resourceCount > 0) {
            --storageTotals.resourceCount;
        }
        detail::metalResourceSubtractSaturating(storageTotals.totalBytes, record.byteSize);

        switch (record.storageMode) {
        case MetalResourceStorageMode::Shared:
            detail::metalResourceSubtractSaturating(m_totals.sharedBytes, record.byteSize);
            break;
        case MetalResourceStorageMode::SharedWriteCombined:
            detail::metalResourceSubtractSaturating(m_totals.sharedBytes, record.byteSize);
            detail::metalResourceSubtractSaturating(m_totals.sharedWriteCombinedBytes, record.byteSize);
            break;
        case MetalResourceStorageMode::Private:
            detail::metalResourceSubtractSaturating(m_totals.privateBytes, record.byteSize);
            break;
        case MetalResourceStorageMode::Managed:
            detail::metalResourceSubtractSaturating(m_totals.managedBytes, record.byteSize);
            break;
        case MetalResourceStorageMode::Memoryless:
            detail::metalResourceSubtractSaturating(m_totals.memorylessBytes, record.byteSize);
            break;
        case MetalResourceStorageMode::Unknown:
        default:
            detail::metalResourceSubtractSaturating(m_totals.unknownStorageBytes, record.byteSize);
            break;
        }
    }

    void refreshExtrema()
    {
        m_totals.largestResourceBytes = 0;
        m_totals.latestCreationSerial = 0;
        for (const auto& entry : m_records) {
            m_totals.largestResourceBytes = std::max(m_totals.largestResourceBytes, entry.second.byteSize);
            m_totals.latestCreationSerial = std::max(m_totals.latestCreationSerial, entry.second.creationSerial);
        }
    }

    std::unordered_map<Serial, MetalResourceRecord> m_records;
    MetalResourceTotals m_totals;
    std::array<MetalResourceBucketTotals, kResourceKindCount> m_byKind = {};
    std::array<MetalResourceBucketTotals, kStorageModeCount> m_byStorageMode = {};
    Serial m_nextCreationSerial = 0;
    std::size_t m_budgetBytes = 0;
};

} // namespace mesh2splat::metal
