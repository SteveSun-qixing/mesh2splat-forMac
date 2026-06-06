#pragma once

#include "core/PathUtils.hpp"

#include <cstdint>
#include <string>
#include <utility>

namespace mesh2splat::renderer {

enum class RendererAssetExportState : std::uint32_t {
    NotExported = 0,
    Pending = 1,
    Exporting = 2,
    Exported = 3,
    Failed = 4,
};

enum class RendererSceneOwner : std::uint32_t {
    None = 0,
    Renderer = 1,
    External = 2,
    Shared = 3,
};

enum class RendererAssetImportState : std::uint32_t {
    Empty = 0,
    Importing = 1,
    Imported = 2,
    Failed = 3,
};

enum class RendererAssetConversionState : std::uint32_t {
    Idle = 0,
    Submitted = 1,
    Running = 2,
    Completed = 3,
    Failed = 4,
    Cancelled = 5,
};

struct RendererSceneOwnershipMetadata {
    RendererSceneOwner owner = RendererSceneOwner::None;
    std::string sceneId;
    std::string ownerName;
    std::uint64_t sceneSerial = 0;
    bool ownsSceneResources = false;

    bool hasOwner() const
    {
        return owner != RendererSceneOwner::None ||
            !sceneId.empty() ||
            !ownerName.empty() ||
            sceneSerial != 0 ||
            ownsSceneResources;
    }
};

struct RendererAssetSessionSnapshot {
    std::string sourcePath;
    std::string displayName;
    std::string exportPath;
    std::string statusText;
    std::string errorMessage;
    RendererAssetImportState importState = RendererAssetImportState::Empty;
    RendererAssetConversionState conversionState = RendererAssetConversionState::Idle;
    RendererAssetExportState exportState = RendererAssetExportState::NotExported;
    std::uint64_t loadSerial = 0;
    std::uint64_t conversionSerial = 0;
    std::uint64_t lastExportedConversionSerial = 0;
    bool hasScene = false;
    bool hasGaussians = false;
    bool dirty = false;
    bool exportMatchesCurrentConversion = false;
};

class RendererAssetSession {
public:
    RendererAssetSession() = default;

    explicit RendererAssetSession(std::string sourcePath)
        : sourcePath_(std::move(sourcePath))
        , displayName_(deriveDisplayName(sourcePath_))
        , displayNameIsDerived_(true)
    {
    }

    RendererAssetSession(std::string sourcePath, std::string displayName)
        : sourcePath_(std::move(sourcePath))
        , displayName_(std::move(displayName))
    {
        if (displayName_.empty()) {
            displayName_ = deriveDisplayName(sourcePath_);
            displayNameIsDerived_ = true;
        } else {
            displayNameIsDerived_ = false;
        }
    }

    static RendererAssetSession fromSourcePath(std::string sourcePath)
    {
        return RendererAssetSession(std::move(sourcePath));
    }

    const std::string& sourcePath() const
    {
        return sourcePath_;
    }

    bool hasSourcePath() const
    {
        return !sourcePath_.empty();
    }

    bool hasLikelySourcePath() const
    {
        return core::isLikelyFilePath(sourcePath_);
    }

    bool hasScene() const
    {
        return hasScene_;
    }

    bool hasGaussians() const
    {
        return hasGaussians_;
    }

    void setSourcePath(std::string sourcePath)
    {
        const bool shouldDeriveDisplayName = displayName_.empty() || displayNameIsDerived_;
        sourcePath_ = std::move(sourcePath);
        if (shouldDeriveDisplayName) {
            displayName_ = deriveDisplayName(sourcePath_);
            displayNameIsDerived_ = true;
        }
    }

    void setSourcePath(std::string sourcePath, std::string displayName)
    {
        sourcePath_ = std::move(sourcePath);
        displayName_ = std::move(displayName);
        if (displayName_.empty()) {
            displayName_ = deriveDisplayName(sourcePath_);
            displayNameIsDerived_ = true;
        } else {
            displayNameIsDerived_ = false;
        }
    }

    const std::string& displayName() const
    {
        return displayName_;
    }

    bool hasDisplayName() const
    {
        return !displayName_.empty();
    }

    void setDisplayName(std::string displayName)
    {
        displayName_ = std::move(displayName);
        displayNameIsDerived_ = false;
    }

    void clearDisplayName()
    {
        displayName_.clear();
        displayNameIsDerived_ = false;
    }

    void deriveDisplayNameFromSourcePath()
    {
        displayName_ = deriveDisplayName(sourcePath_);
        displayNameIsDerived_ = true;
    }

    bool displayNameIsDerived() const
    {
        return displayNameIsDerived_;
    }

    bool isDirty() const
    {
        return dirty_;
    }

    void setDirty(bool dirty)
    {
        dirty_ = dirty;
    }

    void markDirty()
    {
        dirty_ = true;
    }

    void markClean()
    {
        dirty_ = false;
    }

    RendererAssetImportState importState() const
    {
        return importState_;
    }

    RendererAssetConversionState conversionState() const
    {
        return conversionState_;
    }

    RendererAssetExportState exportState() const
    {
        return exportState_;
    }

    bool hasExported() const
    {
        return exportState_ == RendererAssetExportState::Exported;
    }

    bool needsExport() const
    {
        return dirty_ || exportState_ == RendererAssetExportState::NotExported ||
            exportState_ == RendererAssetExportState::Failed;
    }

    bool exportInProgress() const
    {
        return exportState_ == RendererAssetExportState::Pending ||
            exportState_ == RendererAssetExportState::Exporting;
    }

    const std::string& exportPath() const
    {
        return exportPath_;
    }

    bool hasExportPath() const
    {
        return !exportPath_.empty();
    }

    bool hasLikelyExportPath() const
    {
        return core::isLikelyFilePath(exportPath_);
    }

    void setExportState(RendererAssetExportState state)
    {
        exportState_ = state;
    }

    void setExportPath(std::string exportPath)
    {
        exportPath_ = std::move(exportPath);
    }

    void clearExportPath()
    {
        exportPath_.clear();
    }

    void markExportPending()
    {
        exportState_ = RendererAssetExportState::Pending;
        statusText_ = "Export pending";
    }

    void markExporting()
    {
        exportState_ = RendererAssetExportState::Exporting;
        statusText_ = "Exporting";
    }

    void markExported(std::string exportPath = std::string())
    {
        if (!exportPath.empty()) {
            exportPath_ = std::move(exportPath);
        }
        exportState_ = RendererAssetExportState::Exported;
        dirty_ = false;
        lastExportedConversionSerial_ = conversionSerial_;
        statusText_ = "Exported";
        errorMessage_.clear();
    }

    void markExportFailed(std::string errorMessage = std::string())
    {
        exportState_ = RendererAssetExportState::Failed;
        statusText_ = "Export failed";
        errorMessage_ = std::move(errorMessage);
    }

    void clearExportState()
    {
        exportState_ = RendererAssetExportState::NotExported;
        lastExportedConversionSerial_ = 0;
        if (!hasScene_) {
            statusText_.clear();
        }
    }

    std::uint64_t loadSerial() const
    {
        return loadSerial_;
    }

    void setLoadSerial(std::uint64_t serial)
    {
        loadSerial_ = serial;
    }

    std::uint64_t advanceLoadSerial()
    {
        return ++loadSerial_;
    }

    std::uint64_t conversionSerial() const
    {
        return conversionSerial_;
    }

    void setConversionSerial(std::uint64_t serial)
    {
        conversionSerial_ = serial;
    }

    std::uint64_t advanceConversionSerial()
    {
        dirty_ = true;
        return ++conversionSerial_;
    }

    std::uint64_t lastExportedConversionSerial() const
    {
        return lastExportedConversionSerial_;
    }

    bool exportMatchesCurrentConversion() const
    {
        return hasExported() && hasGaussians_ && lastExportedConversionSerial_ == conversionSerial_;
    }

    void importStarted(std::string sourcePath, std::string displayName = std::string())
    {
        setSourcePath(std::move(sourcePath), std::move(displayName));
        importState_ = RendererAssetImportState::Importing;
        conversionState_ = RendererAssetConversionState::Idle;
        exportState_ = RendererAssetExportState::NotExported;
        hasScene_ = false;
        hasGaussians_ = false;
        dirty_ = false;
        errorMessage_.clear();
        statusText_ = "Importing";
        advanceLoadSerial();
    }

    void importSucceeded(std::string sourcePath = std::string(), std::string displayName = std::string())
    {
        if (!sourcePath.empty() || !displayName.empty()) {
            setSourcePath(std::move(sourcePath), std::move(displayName));
        }
        importState_ = RendererAssetImportState::Imported;
        conversionState_ = RendererAssetConversionState::Idle;
        hasScene_ = true;
        hasGaussians_ = false;
        dirty_ = true;
        errorMessage_.clear();
        statusText_ = "Imported";
    }

    void importFailed(std::string errorMessage = std::string())
    {
        importState_ = RendererAssetImportState::Failed;
        hasScene_ = false;
        hasGaussians_ = false;
        dirty_ = false;
        errorMessage_ = std::move(errorMessage);
        statusText_ = "Import failed";
    }

    void conversionSubmitted()
    {
        conversionState_ = RendererAssetConversionState::Submitted;
        hasGaussians_ = false;
        dirty_ = true;
        errorMessage_.clear();
        statusText_ = "Conversion submitted";
        advanceConversionSerial();
    }

    void conversionRunning()
    {
        conversionState_ = RendererAssetConversionState::Running;
        statusText_ = "Converting";
    }

    void conversionCompleted(bool producedGaussians = true)
    {
        conversionState_ = RendererAssetConversionState::Completed;
        hasGaussians_ = producedGaussians;
        dirty_ = producedGaussians;
        errorMessage_.clear();
        statusText_ = producedGaussians ? "Conversion completed" : "Conversion completed without gaussians";
    }

    void conversionFailed(std::string errorMessage = std::string())
    {
        conversionState_ = RendererAssetConversionState::Failed;
        hasGaussians_ = false;
        dirty_ = true;
        errorMessage_ = std::move(errorMessage);
        statusText_ = "Conversion failed";
    }

    void conversionCancelled()
    {
        conversionState_ = RendererAssetConversionState::Cancelled;
        statusText_ = "Conversion cancelled";
    }

    void exportStarted(std::string exportPath = std::string())
    {
        if (!exportPath.empty()) {
            exportPath_ = std::move(exportPath);
        }
        markExporting();
        errorMessage_.clear();
    }

    void exportSucceeded(std::string exportPath = std::string())
    {
        markExported(std::move(exportPath));
    }

    void exportFailed(std::string errorMessage = std::string())
    {
        markExportFailed(std::move(errorMessage));
    }

    const std::string& statusText() const
    {
        return statusText_;
    }

    const std::string& errorMessage() const
    {
        return errorMessage_;
    }

    RendererAssetSessionSnapshot snapshot() const
    {
        RendererAssetSessionSnapshot result;
        result.sourcePath = sourcePath_;
        result.displayName = displayName_;
        result.exportPath = exportPath_;
        result.statusText = statusText_;
        result.errorMessage = errorMessage_;
        result.importState = importState_;
        result.conversionState = conversionState_;
        result.exportState = exportState_;
        result.loadSerial = loadSerial_;
        result.conversionSerial = conversionSerial_;
        result.lastExportedConversionSerial = lastExportedConversionSerial_;
        result.hasScene = hasScene_;
        result.hasGaussians = hasGaussians_;
        result.dirty = dirty_;
        result.exportMatchesCurrentConversion = exportMatchesCurrentConversion();
        return result;
    }

    const RendererSceneOwnershipMetadata& sceneOwnership() const
    {
        return sceneOwnership_;
    }

    bool hasSceneOwnership() const
    {
        return sceneOwnership_.hasOwner();
    }

    void setSceneOwnership(RendererSceneOwnershipMetadata metadata)
    {
        sceneOwnership_ = std::move(metadata);
    }

    void clearSceneOwnership()
    {
        sceneOwnership_ = RendererSceneOwnershipMetadata {};
    }

    void reset()
    {
        sourcePath_.clear();
        displayName_.clear();
        displayNameIsDerived_ = false;
        dirty_ = false;
        exportState_ = RendererAssetExportState::NotExported;
        exportPath_.clear();
        importState_ = RendererAssetImportState::Empty;
        conversionState_ = RendererAssetConversionState::Idle;
        hasScene_ = false;
        hasGaussians_ = false;
        statusText_.clear();
        errorMessage_.clear();
        loadSerial_ = 0;
        conversionSerial_ = 0;
        lastExportedConversionSerial_ = 0;
        clearSceneOwnership();
    }

private:
    static std::string deriveDisplayName(const std::string& sourcePath)
    {
        return core::pathDisplayBasename(sourcePath, "");
    }

    std::string sourcePath_;
    std::string displayName_;
    bool displayNameIsDerived_ = false;
    bool dirty_ = false;
    bool hasScene_ = false;
    bool hasGaussians_ = false;
    RendererAssetImportState importState_ = RendererAssetImportState::Empty;
    RendererAssetConversionState conversionState_ = RendererAssetConversionState::Idle;
    RendererAssetExportState exportState_ = RendererAssetExportState::NotExported;
    std::string exportPath_;
    std::string statusText_;
    std::string errorMessage_;
    std::uint64_t loadSerial_ = 0;
    std::uint64_t conversionSerial_ = 0;
    std::uint64_t lastExportedConversionSerial_ = 0;
    RendererSceneOwnershipMetadata sceneOwnership_;
};

} // namespace mesh2splat::renderer
