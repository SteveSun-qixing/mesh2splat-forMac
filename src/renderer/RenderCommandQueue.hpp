#pragma once

#include "core/MeshData.hpp"
#include "core/RenderSettings.hpp"
#include "renderer/RendererInterface.hpp"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <limits>
#include <mutex>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::renderer {

using RenderCommandId = uint64_t;
inline constexpr RenderCommandId kInvalidRenderCommandId = 0;

enum class RenderCommandType : uint32_t {
    Unknown = 0,
    LoadScene = 1,
    ExportPly = 2,
    ResetCamera = 3,
    FocusBounds = 4,
    UpdateSettings = 5,
    StartConversion = 6,
    CancelConversion = 7,
    RefreshStatus = 8,
};

struct RenderCommand {
    struct Settings {
        std::optional<RenderViewMode> viewMode;
        std::optional<GaussianVisualizationMode> gaussianVisualizationMode;
        std::optional<float> gaussianScale;
        std::optional<uint32_t> conversionSamplesPerTriangle;
        std::optional<core::RenderSettingsSnapshot> renderSettings;
    };

    RenderCommandType type = RenderCommandType::Unknown;
    RenderCommandId commandId = kInvalidRenderCommandId;
    uint64_t sequenceId = 0;
    uint64_t enqueuedNanoseconds = 0;
    RendererSceneLoadRequest sceneLoadRequest;
    std::string outputFilePath;
    uint32_t exportFormat = 0;
    core::MeshBounds bounds;
    Settings settings;
    std::string label;

    bool valid() const
    {
        return type != RenderCommandType::Unknown;
    }

    bool coalescible() const
    {
        return type == RenderCommandType::UpdateSettings ||
            type == RenderCommandType::RefreshStatus;
    }

    static RenderCommand loadScene(RendererSceneLoadRequest request)
    {
        RenderCommand command;
        command.type = RenderCommandType::LoadScene;
        command.sceneLoadRequest = std::move(request);
        return command;
    }

    static RenderCommand loadScene(
        std::string filePath,
        RendererSceneKind kind = RendererSceneKind::Auto,
        bool replaceCurrentScene = true)
    {
        RendererSceneLoadRequest request;
        request.filePath = std::move(filePath);
        request.kind = kind;
        request.replaceCurrentScene = replaceCurrentScene;
        return loadScene(std::move(request));
    }

    static RenderCommand exportPly(std::string filePath, uint32_t format = 0)
    {
        RenderCommand command;
        command.type = RenderCommandType::ExportPly;
        command.outputFilePath = std::move(filePath);
        command.exportFormat = format;
        return command;
    }

    static RenderCommand resetCamera()
    {
        RenderCommand command;
        command.type = RenderCommandType::ResetCamera;
        return command;
    }

    static RenderCommand focusBounds(const core::MeshBounds& bounds)
    {
        RenderCommand command;
        command.type = RenderCommandType::FocusBounds;
        command.bounds = bounds;
        return command;
    }

    static RenderCommand updateSettings(Settings settings)
    {
        RenderCommand command;
        command.type = RenderCommandType::UpdateSettings;
        command.settings = std::move(settings);
        return command;
    }

    static RenderCommand startConversion()
    {
        RenderCommand command;
        command.type = RenderCommandType::StartConversion;
        return command;
    }

    static RenderCommand startConversion(uint32_t samplesPerTriangle)
    {
        RenderCommand command = startConversion();
        command.settings.conversionSamplesPerTriangle = samplesPerTriangle;
        return command;
    }

    static RenderCommand cancelConversion()
    {
        RenderCommand command;
        command.type = RenderCommandType::CancelConversion;
        return command;
    }

    static RenderCommand refreshStatus()
    {
        RenderCommand command;
        command.type = RenderCommandType::RefreshStatus;
        return command;
    }
};

struct RenderCommandQueueOptions {
    std::size_t capacity = 256;
    bool dropOldestWhenFull = true;
    bool coalesceSettingsUpdates = true;
    bool coalesceStatusRefreshes = true;
};

struct RenderCommandQueueSnapshot {
    std::size_t size = 0;
    std::size_t capacity = 0;
    uint64_t nextCommandId = 1;
    uint64_t nextSequenceId = 1;
    uint64_t droppedCommandCount = 0;
    uint64_t coalescedCommandCount = 0;
};

class RenderCommandQueue {
public:
    RenderCommandQueue() = default;

    explicit RenderCommandQueue(RenderCommandQueueOptions options)
        : m_options(normalizeOptions(options))
    {
    }

    RenderCommandQueue(const RenderCommandQueue&) = delete;
    RenderCommandQueue& operator=(const RenderCommandQueue&) = delete;

    uint64_t enqueue(RenderCommand command)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        return enqueueLocked(std::move(command));
    }

    uint64_t loadScene(RendererSceneLoadRequest request)
    {
        return enqueue(RenderCommand::loadScene(std::move(request)));
    }

    uint64_t loadScene(
        std::string filePath,
        RendererSceneKind kind = RendererSceneKind::Auto,
        bool replaceCurrentScene = true)
    {
        return enqueue(RenderCommand::loadScene(std::move(filePath), kind, replaceCurrentScene));
    }

    uint64_t exportPly(std::string filePath, uint32_t format = 0)
    {
        return enqueue(RenderCommand::exportPly(std::move(filePath), format));
    }

    uint64_t resetCamera()
    {
        return enqueue(RenderCommand::resetCamera());
    }

    uint64_t focusBounds(const core::MeshBounds& bounds)
    {
        return enqueue(RenderCommand::focusBounds(bounds));
    }

    uint64_t updateSettings(RenderCommand::Settings settings)
    {
        return enqueue(RenderCommand::updateSettings(std::move(settings)));
    }

    uint64_t updateRenderSettings(core::RenderSettingsSnapshot settings)
    {
        RenderCommand::Settings commandSettings;
        commandSettings.renderSettings = settings;
        commandSettings.viewMode = renderViewModeFromCore(settings.mode);
        commandSettings.gaussianScale = settings.gaussianScale;
        commandSettings.conversionSamplesPerTriangle = settings.conversionSamplesPerTriangle;
        return updateSettings(std::move(commandSettings));
    }

    uint64_t startConversion()
    {
        return enqueue(RenderCommand::startConversion());
    }

    uint64_t startConversion(uint32_t samplesPerTriangle)
    {
        return enqueue(RenderCommand::startConversion(samplesPerTriangle));
    }

    uint64_t cancelConversion()
    {
        return enqueue(RenderCommand::cancelConversion());
    }

    uint64_t refreshStatus()
    {
        return enqueue(RenderCommand::refreshStatus());
    }

    bool peek(RenderCommand& command) const
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_commands.empty()) {
            return false;
        }

        command = m_commands.front();
        return true;
    }

    bool tryDequeue(RenderCommand& command)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_commands.empty()) {
            return false;
        }

        command = std::move(m_commands.front());
        m_commands.pop_front();
        return true;
    }

    std::vector<RenderCommand> drain()
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        return drainLocked(0);
    }

    std::vector<RenderCommand> drain(std::size_t maxCommandCount)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        return drainLocked(maxCommandCount);
    }

    void setOptions(RenderCommandQueueOptions options)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_options = normalizeOptions(options);
        trimToCapacityLocked();
    }

    RenderCommandQueueOptions options() const
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        return m_options;
    }

    void setCapacity(std::size_t capacity)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_options.capacity = capacity;
        trimToCapacityLocked();
    }

    std::size_t capacity() const
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        return m_options.capacity;
    }

    uint64_t droppedCommandCount() const
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        return m_droppedCommandCount;
    }

    uint64_t coalescedCommandCount() const
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        return m_coalescedCommandCount;
    }

    RenderCommandQueueSnapshot snapshot() const
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        RenderCommandQueueSnapshot snapshot;
        snapshot.size = m_commands.size();
        snapshot.capacity = m_options.capacity;
        snapshot.nextCommandId = m_nextCommandId;
        snapshot.nextSequenceId = m_nextSequenceId;
        snapshot.droppedCommandCount = m_droppedCommandCount;
        snapshot.coalescedCommandCount = m_coalescedCommandCount;
        return snapshot;
    }

    void resetDiagnostics()
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_droppedCommandCount = 0;
        m_coalescedCommandCount = 0;
    }

    void clear()
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_commands.clear();
    }

    bool empty() const
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        return m_commands.empty();
    }

    std::size_t size() const
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        return m_commands.size();
    }

private:
    static RenderCommandQueueOptions normalizeOptions(RenderCommandQueueOptions options)
    {
        options.capacity = std::min<std::size_t>(
            options.capacity,
            static_cast<std::size_t>(std::numeric_limits<uint32_t>::max()));
        return options;
    }

    static uint64_t nowNanoseconds()
    {
        return static_cast<uint64_t>(
            std::chrono::duration_cast<std::chrono::nanoseconds>(
                std::chrono::steady_clock::now().time_since_epoch())
                .count());
    }

    static RenderViewMode renderViewModeFromCore(core::RenderMode mode)
    {
        switch (mode) {
        case core::RenderMode::MeshOnly:
            return RenderViewMode::MeshOnly;
        case core::RenderMode::GaussianOnly:
            return RenderViewMode::GaussianOnly;
        default:
            return RenderViewMode::Combined;
        }
    }

    bool shouldCoalesce(const RenderCommand& command) const
    {
        switch (command.type) {
        case RenderCommandType::UpdateSettings:
            return m_options.coalesceSettingsUpdates;
        case RenderCommandType::RefreshStatus:
            return m_options.coalesceStatusRefreshes;
        default:
            return false;
        }
    }

    uint64_t enqueueLocked(RenderCommand command)
    {
        if (!command.valid() || m_options.capacity == 0) {
            ++m_droppedCommandCount;
            return kInvalidRenderCommandId;
        }

        command.commandId = m_nextCommandId++;
        command.sequenceId = m_nextSequenceId++;
        command.enqueuedNanoseconds = nowNanoseconds();

        if (shouldCoalesce(command)) {
            auto existing = std::find_if(
                m_commands.rbegin(),
                m_commands.rend(),
                [&](const RenderCommand& queued) {
                    return queued.type == command.type;
                });

            if (existing != m_commands.rend()) {
                *existing = std::move(command);
                ++m_coalescedCommandCount;
                return existing->commandId;
            }
        }

        if (m_commands.size() >= m_options.capacity) {
            if (!m_options.dropOldestWhenFull) {
                ++m_droppedCommandCount;
                return kInvalidRenderCommandId;
            }

            m_commands.pop_front();
            ++m_droppedCommandCount;
        }

        m_commands.push_back(std::move(command));
        return m_commands.back().commandId;
    }

    std::vector<RenderCommand> drainLocked(std::size_t maxCommandCount)
    {
        std::vector<RenderCommand> commands;
        const std::size_t count = maxCommandCount == 0
            ? m_commands.size()
            : std::min(maxCommandCount, m_commands.size());
        commands.reserve(count);

        while (!m_commands.empty() && (maxCommandCount == 0 || commands.size() < maxCommandCount)) {
            commands.push_back(std::move(m_commands.front()));
            m_commands.pop_front();
        }

        return commands;
    }

    void trimToCapacityLocked()
    {
        while (m_commands.size() > m_options.capacity) {
            m_commands.pop_front();
            ++m_droppedCommandCount;
        }
    }

    mutable std::mutex m_mutex;
    std::deque<RenderCommand> m_commands;
    RenderCommandQueueOptions m_options;
    uint64_t m_nextCommandId = 1;
    uint64_t m_nextSequenceId = 1;
    uint64_t m_droppedCommandCount = 0;
    uint64_t m_coalescedCommandCount = 0;
};

} // namespace mesh2splat::renderer
