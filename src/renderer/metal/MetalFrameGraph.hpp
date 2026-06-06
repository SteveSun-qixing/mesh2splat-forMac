#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace mesh2splat::metal {

class MetalFrameGraph {
public:
    using PassId = uint32_t;
    using ResourceId = std::string;

    static constexpr PassId kInvalidPassId = std::numeric_limits<PassId>::max();

    enum class PassType : uint8_t {
        Generic,
        Mesh,
        Conversion,
        Sort,
        Gaussian,
        Compute,
        Render,
        Transfer,
    };

    enum class DependencyType : uint8_t {
        Explicit,
        ResourceReadAfterWrite,
        ResourceWriteAfterRead,
        ResourceWriteAfterWrite,
    };

    struct PassDescriptor {
        PassId id = kInvalidPassId;
        std::string name;
        PassType type = PassType::Generic;
        std::vector<ResourceId> reads;
        std::vector<ResourceId> writes;
        std::vector<PassId> dependencies;

        bool isValid() const { return id != kInvalidPassId && !name.empty(); }
    };

    struct DependencyEdge {
        PassId passId = kInvalidPassId;
        PassId dependencyId = kInvalidPassId;
        ResourceId resource;
        DependencyType type = DependencyType::Explicit;

        bool isValid() const
        {
            return passId != kInvalidPassId &&
                dependencyId != kInvalidPassId &&
                passId != dependencyId;
        }

        bool operator==(const DependencyEdge& other) const
        {
            return passId == other.passId &&
                dependencyId == other.dependencyId &&
                resource == other.resource &&
                type == other.type;
        }
    };

    struct ResourceUsage {
        ResourceId resource;
        std::vector<PassId> readers;
        std::vector<PassId> writers;

        bool isValid() const { return !resource.empty(); }
        bool hasReaders() const { return !readers.empty(); }
        bool hasWriters() const { return !writers.empty(); }
    };

    struct ValidationResult {
        bool valid = false;
        std::string diagnostic;
        std::vector<PassId> executionOrder;
        std::vector<PassId> cyclePath;
        std::vector<DependencyEdge> dependencyEdges;
        std::vector<ResourceUsage> resourceUsages;

        bool hasCycle() const { return !cyclePath.empty(); }
    };

    MetalFrameGraph() = default;

    void clear()
    {
        m_passes.clear();
        m_passIndex.clear();
        m_executionOrder.clear();
        m_dependencyEdges.clear();
        m_resourceUsages.clear();
        m_lastValidation = ValidationResult();
        m_nextPassId = 0;
    }

    PassId addPass(const char* name, PassType type = PassType::Generic)
    {
        const PassId id = nextAvailablePassId();
        return addPass(id, name, type) ? id : kInvalidPassId;
    }

    bool addPass(PassId id, const char* name, PassType type = PassType::Generic, std::string* errorMessage = nullptr)
    {
        if (id == kInvalidPassId) {
            setError(errorMessage, "Frame graph pass id is invalid.");
            return false;
        }
        if (containsPass(id)) {
            setError(errorMessage, "Frame graph pass id is already registered.");
            return false;
        }
        if (name == nullptr || name[0] == '\0') {
            setError(errorMessage, "Frame graph pass name is empty.");
            return false;
        }

        PassDescriptor pass;
        pass.id = id;
        pass.name = name;
        pass.type = type;

        m_passIndex[id] = m_passes.size();
        m_passes.push_back(std::move(pass));
        if (id >= m_nextPassId) {
            m_nextPassId = id + 1;
        }
        invalidateExecutionOrder();
        return true;
    }

    bool addRead(PassId passId, const ResourceId& resource, std::string* errorMessage = nullptr)
    {
        PassDescriptor* descriptor = mutablePass(passId);
        if (descriptor == nullptr) {
            setError(errorMessage, "Frame graph read references an unknown pass.");
            return false;
        }
        if (resource.empty()) {
            setError(errorMessage, "Frame graph read resource is empty.");
            return false;
        }

        appendUnique(descriptor->reads, resource);
        invalidateExecutionOrder();
        return true;
    }

    bool addWrite(PassId passId, const ResourceId& resource, std::string* errorMessage = nullptr)
    {
        PassDescriptor* descriptor = mutablePass(passId);
        if (descriptor == nullptr) {
            setError(errorMessage, "Frame graph write references an unknown pass.");
            return false;
        }
        if (resource.empty()) {
            setError(errorMessage, "Frame graph write resource is empty.");
            return false;
        }

        appendUnique(descriptor->writes, resource);
        invalidateExecutionOrder();
        return true;
    }

    bool addReads(PassId passId, const std::vector<ResourceId>& resources, std::string* errorMessage = nullptr)
    {
        PassDescriptor* descriptor = mutablePass(passId);
        if (descriptor == nullptr) {
            setError(errorMessage, "Frame graph reads reference an unknown pass.");
            return false;
        }
        for (const ResourceId& resource : resources) {
            if (resource.empty()) {
                setError(errorMessage, "Frame graph read resource is empty.");
                return false;
            }
        }

        for (const ResourceId& resource : resources) {
            appendUnique(descriptor->reads, resource);
        }
        invalidateExecutionOrder();
        return true;
    }

    bool addWrites(PassId passId, const std::vector<ResourceId>& resources, std::string* errorMessage = nullptr)
    {
        PassDescriptor* descriptor = mutablePass(passId);
        if (descriptor == nullptr) {
            setError(errorMessage, "Frame graph writes reference an unknown pass.");
            return false;
        }
        for (const ResourceId& resource : resources) {
            if (resource.empty()) {
                setError(errorMessage, "Frame graph write resource is empty.");
                return false;
            }
        }

        for (const ResourceId& resource : resources) {
            appendUnique(descriptor->writes, resource);
        }
        invalidateExecutionOrder();
        return true;
    }

    bool addReadWrite(PassId passId, const ResourceId& resource, std::string* errorMessage = nullptr)
    {
        PassDescriptor* descriptor = mutablePass(passId);
        if (descriptor == nullptr) {
            setError(errorMessage, "Frame graph read/write references an unknown pass.");
            return false;
        }
        if (resource.empty()) {
            setError(errorMessage, "Frame graph read/write resource is empty.");
            return false;
        }

        appendUnique(descriptor->reads, resource);
        appendUnique(descriptor->writes, resource);
        invalidateExecutionOrder();
        return true;
    }

    bool addDependency(PassId passId, PassId dependencyId, std::string* errorMessage = nullptr)
    {
        PassDescriptor* descriptor = mutablePass(passId);
        if (descriptor == nullptr) {
            setError(errorMessage, "Frame graph dependency references an unknown pass.");
            return false;
        }
        if (dependencyId == kInvalidPassId) {
            setError(errorMessage, "Frame graph dependency id is invalid.");
            return false;
        }
        if (passId == dependencyId) {
            setError(errorMessage, "Frame graph pass cannot depend on itself.");
            return false;
        }

        appendUnique(descriptor->dependencies, dependencyId);
        invalidateExecutionOrder();
        return true;
    }

    ValidationResult validate()
    {
        ValidationResult result;
        std::vector<std::vector<PassId>> dependencies;
        if (!collectDependencies(dependencies, result.dependencyEdges, result.resourceUsages, result)) {
            m_executionOrder.clear();
            m_dependencyEdges.clear();
            m_resourceUsages.clear();
            m_lastValidation = result;
            return result;
        }

        result.valid = topologicalSort(dependencies, result.executionOrder, result.cyclePath);
        if (!result.valid) {
            result.diagnostic = "Frame graph contains a dependency cycle.";
            m_executionOrder.clear();
        } else {
            result.diagnostic.clear();
            m_executionOrder = result.executionOrder;
        }

        m_dependencyEdges = result.dependencyEdges;
        m_resourceUsages = result.resourceUsages;
        m_lastValidation = result;
        return result;
    }

    bool validate(std::string* errorMessage)
    {
        const ValidationResult result = validate();
        if (!result.valid) {
            setError(errorMessage, result.diagnostic);
        }
        return result.valid;
    }

    bool containsPass(PassId id) const { return m_passIndex.find(id) != m_passIndex.end(); }
    bool empty() const { return m_passes.empty(); }
    std::size_t passCount() const { return m_passes.size(); }

    const PassDescriptor* pass(PassId id) const
    {
        const auto found = m_passIndex.find(id);
        if (found == m_passIndex.end()) {
            return nullptr;
        }
        return &m_passes[found->second];
    }

    const std::vector<PassDescriptor>& passes() const { return m_passes; }
    const std::vector<PassId>& executionOrder() const { return m_executionOrder; }
    const std::vector<DependencyEdge>& dependencyEdges() const { return m_dependencyEdges; }
    const std::vector<ResourceUsage>& resourceUsages() const { return m_resourceUsages; }
    const ValidationResult& lastValidation() const { return m_lastValidation; }

    std::vector<ResourceId> resources() const
    {
        std::vector<ResourceId> result;
        for (const PassDescriptor& descriptor : m_passes) {
            for (const ResourceId& resource : descriptor.reads) {
                appendUnique(result, resource);
            }
            for (const ResourceId& resource : descriptor.writes) {
                appendUnique(result, resource);
            }
        }
        return result;
    }

    std::vector<PassId> dependenciesFor(PassId passId) const
    {
        std::vector<std::vector<PassId>> dependencies;
        std::vector<DependencyEdge> dependencyEdges;
        std::vector<ResourceUsage> resourceUsages;
        ValidationResult result;
        if (!containsPass(passId) || !collectDependencies(dependencies, dependencyEdges, resourceUsages, result)) {
            return std::vector<PassId>();
        }

        return dependencies[m_passIndex.at(passId)];
    }

    static const char* passTypeName(PassType type)
    {
        switch (type) {
        case PassType::Generic:
            return "Generic";
        case PassType::Mesh:
            return "Mesh";
        case PassType::Conversion:
            return "Conversion";
        case PassType::Sort:
            return "Sort";
        case PassType::Gaussian:
            return "Gaussian";
        case PassType::Compute:
            return "Compute";
        case PassType::Render:
            return "Render";
        case PassType::Transfer:
            return "Transfer";
        }
        return "Unknown";
    }

    static const char* dependencyTypeName(DependencyType type)
    {
        switch (type) {
        case DependencyType::Explicit:
            return "Explicit";
        case DependencyType::ResourceReadAfterWrite:
            return "ResourceReadAfterWrite";
        case DependencyType::ResourceWriteAfterRead:
            return "ResourceWriteAfterRead";
        case DependencyType::ResourceWriteAfterWrite:
            return "ResourceWriteAfterWrite";
        }
        return "Unknown";
    }

private:
    enum class VisitState : uint8_t {
        Unvisited,
        Visiting,
        Visited,
    };

    struct ResourceState {
        PassId lastWriter = kInvalidPassId;
        std::vector<PassId> readers;
    };

    PassDescriptor* mutablePass(PassId id)
    {
        const auto found = m_passIndex.find(id);
        if (found == m_passIndex.end()) {
            return nullptr;
        }
        return &m_passes[found->second];
    }

    PassId nextAvailablePassId() const
    {
        PassId id = m_nextPassId;
        while (id != kInvalidPassId && containsPass(id)) {
            ++id;
        }
        return id;
    }

    void invalidateExecutionOrder()
    {
        m_executionOrder.clear();
        m_dependencyEdges.clear();
        m_resourceUsages.clear();
        m_lastValidation = ValidationResult();
    }

    bool collectDependencies(
        std::vector<std::vector<PassId>>& dependencies,
        std::vector<DependencyEdge>& dependencyEdges,
        std::vector<ResourceUsage>& resourceUsages,
        ValidationResult& result) const
    {
        dependencies.assign(m_passes.size(), std::vector<PassId>());
        dependencyEdges.clear();
        resourceUsages.clear();

        for (const PassDescriptor& pass : m_passes) {
            if (!pass.isValid()) {
                result.diagnostic = "Frame graph contains a pass with an invalid id or empty name.";
                return false;
            }

            const std::size_t passIndex = m_passIndex.at(pass.id);
            for (PassId dependencyId : pass.dependencies) {
                if (!containsPass(dependencyId)) {
                    result.diagnostic = "Frame graph contains a dependency on an unknown pass.";
                    return false;
                }
                if (dependencyId == pass.id) {
                    result.diagnostic = "Frame graph contains a self dependency.";
                    return false;
                }
                appendDependency(
                    dependencies[passIndex],
                    dependencyEdges,
                    pass.id,
                    dependencyId,
                    ResourceId(),
                    DependencyType::Explicit);
            }
        }

        std::unordered_map<ResourceId, ResourceState> resourceStates;
        std::unordered_map<ResourceId, std::size_t> resourceUsageIndex;
        for (const PassDescriptor& pass : m_passes) {
            const std::size_t passIndex = m_passIndex.at(pass.id);

            for (const ResourceId& resource : pass.reads) {
                if (resource.empty()) {
                    result.diagnostic = "Frame graph contains an empty read resource.";
                    return false;
                }

                ResourceUsage& usage = ensureResourceUsage(resourceUsages, resourceUsageIndex, resource);
                appendUnique(usage.readers, pass.id);
                ResourceState& resourceState = resourceStates[resource];
                if (resourceState.lastWriter != kInvalidPassId && resourceState.lastWriter != pass.id) {
                    appendDependency(
                        dependencies[passIndex],
                        dependencyEdges,
                        pass.id,
                        resourceState.lastWriter,
                        resource,
                        DependencyType::ResourceReadAfterWrite);
                }
                appendUnique(resourceState.readers, pass.id);
            }

            for (const ResourceId& resource : pass.writes) {
                if (resource.empty()) {
                    result.diagnostic = "Frame graph contains an empty write resource.";
                    return false;
                }

                ResourceUsage& usage = ensureResourceUsage(resourceUsages, resourceUsageIndex, resource);
                appendUnique(usage.writers, pass.id);
                ResourceState& resourceState = resourceStates[resource];
                if (resourceState.lastWriter != kInvalidPassId && resourceState.lastWriter != pass.id) {
                    appendDependency(
                        dependencies[passIndex],
                        dependencyEdges,
                        pass.id,
                        resourceState.lastWriter,
                        resource,
                        DependencyType::ResourceWriteAfterWrite);
                }
                for (PassId readerId : resourceState.readers) {
                    if (readerId != pass.id) {
                        appendDependency(
                            dependencies[passIndex],
                            dependencyEdges,
                            pass.id,
                            readerId,
                            resource,
                            DependencyType::ResourceWriteAfterRead);
                    }
                }
                resourceState.readers.clear();
                resourceState.lastWriter = pass.id;
            }
        }

        return true;
    }

    bool topologicalSort(
        const std::vector<std::vector<PassId>>& dependencies,
        std::vector<PassId>& executionOrder,
        std::vector<PassId>& cyclePath) const
    {
        std::vector<VisitState> states(m_passes.size(), VisitState::Unvisited);
        std::vector<PassId> stack;
        executionOrder.clear();
        cyclePath.clear();

        for (const PassDescriptor& pass : m_passes) {
            const std::size_t passIndex = m_passIndex.at(pass.id);
            if (states[passIndex] == VisitState::Unvisited
                && !visit(pass.id, dependencies, states, stack, executionOrder, cyclePath)) {
                return false;
            }
        }

        return true;
    }

    bool visit(
        PassId passId,
        const std::vector<std::vector<PassId>>& dependencies,
        std::vector<VisitState>& states,
        std::vector<PassId>& stack,
        std::vector<PassId>& executionOrder,
        std::vector<PassId>& cyclePath) const
    {
        const std::size_t passIndex = m_passIndex.at(passId);
        if (states[passIndex] == VisitState::Visited) {
            return true;
        }
        if (states[passIndex] == VisitState::Visiting) {
            const auto cycleStart = std::find(stack.begin(), stack.end(), passId);
            if (cycleStart != stack.end()) {
                cyclePath.assign(cycleStart, stack.end());
            }
            cyclePath.push_back(passId);
            return false;
        }

        states[passIndex] = VisitState::Visiting;
        stack.push_back(passId);

        for (PassId dependencyId : dependencies[passIndex]) {
            if (!visit(dependencyId, dependencies, states, stack, executionOrder, cyclePath)) {
                return false;
            }
        }

        stack.pop_back();
        states[passIndex] = VisitState::Visited;
        appendUnique(executionOrder, passId);
        return true;
    }

    template <typename Value>
    static void appendUnique(std::vector<Value>& values, const Value& value)
    {
        if (std::find(values.begin(), values.end(), value) == values.end()) {
            values.push_back(value);
        }
    }

    static void appendDependency(
        std::vector<PassId>& dependencies,
        std::vector<DependencyEdge>& dependencyEdges,
        PassId passId,
        PassId dependencyId,
        const ResourceId& resource,
        DependencyType type)
    {
        if (passId == dependencyId) {
            return;
        }

        appendUnique(dependencies, dependencyId);

        DependencyEdge edge;
        edge.passId = passId;
        edge.dependencyId = dependencyId;
        edge.resource = resource;
        edge.type = type;
        appendUnique(dependencyEdges, edge);
    }

    static ResourceUsage& ensureResourceUsage(
        std::vector<ResourceUsage>& resourceUsages,
        std::unordered_map<ResourceId, std::size_t>& resourceUsageIndex,
        const ResourceId& resource)
    {
        const auto found = resourceUsageIndex.find(resource);
        if (found != resourceUsageIndex.end()) {
            return resourceUsages[found->second];
        }

        ResourceUsage usage;
        usage.resource = resource;
        resourceUsageIndex[resource] = resourceUsages.size();
        resourceUsages.push_back(std::move(usage));
        return resourceUsages.back();
    }

    static void setError(std::string* errorMessage, const std::string& message)
    {
        if (errorMessage != nullptr) {
            *errorMessage = message;
        }
    }

    std::vector<PassDescriptor> m_passes;
    std::unordered_map<PassId, std::size_t> m_passIndex;
    std::vector<PassId> m_executionOrder;
    std::vector<DependencyEdge> m_dependencyEdges;
    std::vector<ResourceUsage> m_resourceUsages;
    ValidationResult m_lastValidation;
    PassId m_nextPassId = 0;
};

} // namespace mesh2splat::metal
