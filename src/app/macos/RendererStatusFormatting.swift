import Foundation

enum RendererStatusFormatting {
    static func integer(_ value: UInt64) -> String {
        let rawValue = String(value)
        var groupedValue = ""

        for (index, character) in rawValue.reversed().enumerated() {
            if index > 0 && index % 3 == 0 {
                groupedValue.append(",")
            }

            groupedValue.append(character)
        }

        return String(groupedValue.reversed())
    }

    static func bytes(_ byteCount: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]

        guard byteCount >= 1024 else {
            return "\(byteCount) B"
        }

        var value = Double(byteCount)
        var unitIndex = 0
        while value >= 1024.0 && unitIndex < units.count - 1 {
            value /= 1024.0
            unitIndex += 1
        }

        let fractionDigits = value < 10.0 ? 1 : 0
        return "\(fixedDecimal(value, fractionDigits: fractionDigits)) \(units[unitIndex])"
    }

    static func bytes(_ byteCount: Int64) -> String {
        guard byteCount < 0 else {
            return bytes(UInt64(byteCount))
        }

        return "-\(bytes(UInt64(byteCount.magnitude)))"
    }

    static func milliseconds(_ milliseconds: Double) -> String {
        "\(fixedDecimal(nonNegativeFinite(milliseconds), fractionDigits: 1)) ms"
    }

    static func frameTiming(cpuMs: Double, gpuMs: Double) -> String {
        "CPU \(milliseconds(cpuMs)) / GPU \(milliseconds(gpuMs))"
    }

    static func conversionTiming(cpuSubmitMs: Double, gpuMs: Double) -> String {
        "Submit \(milliseconds(cpuSubmitMs)) / GPU \(milliseconds(gpuMs))"
    }

    static func normalizedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else {
            return 0.0
        }

        return min(max(progress, 0.0), 1.0)
    }

    static func normalizedProgress(_ progress: Float) -> Double {
        normalizedProgress(Double(progress))
    }

    static func progressPercent(_ progress: Double) -> String {
        "\(Int((normalizedProgress(progress) * 100.0).rounded()))%"
    }

    static func progressPercent(_ progress: Float) -> String {
        progressPercent(Double(progress))
    }

    static func frameCounter(completed: UInt64, submitted: UInt64) -> String {
        "\(integer(completed)) / \(integer(submitted))"
    }

    static func frameCounter(completed: UInt64, submitted: UInt64, failed: UInt64) -> String {
        let baseCounter = frameCounter(completed: completed, submitted: submitted)

        guard failed > 0 else {
            return baseCounter
        }

        return "\(baseCounter) (\(failed) failed)"
    }

    static func gaussianCount(_ count: UInt64) -> String {
        integer(count)
    }

    static func drawableStatus(width: UInt32, height: UInt32, backingScale: Float) -> String {
        let scale = fixedDecimal(nonNegativeFinite(Double(backingScale)), fractionDigits: 1)
        return "\(width)x\(height) @\(scale)x"
    }

    static func conversionStatus(isConverting: Bool, progress: Double, gaussianCountValue: UInt64) -> String {
        if isConverting {
            return "Conversion: \(progressPercent(progress))"
        }

        return "Conversion: \(gaussianCount(gaussianCountValue)) gaussians"
    }

    static func rendererStatusText(_ statusText: String, runtimeState: M2SRendererRuntimeState) -> String {
        rendererStatusText(statusText, fallbackRuntimeTitle: runtimeStateTitle(runtimeState))
    }

    static func rendererStatusText(_ statusText: String, fallbackRuntimeTitle: String) -> String {
        let trimmedStatus = statusText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedStatus.isEmpty {
            return fallbackRuntimeTitle
        }

        return statusText
    }

    static func runtimeStateTitle(_ state: M2SRendererRuntimeState) -> String {
        runtimeStateTitle(rawValue: state.rawValue)
    }

    static func runtimeStateTitle(rawValue: UInt) -> String {
        switch rawValue {
        case M2SRendererRuntimeState.ready.rawValue:
            return "Ready"
        case M2SRendererRuntimeState.loading.rawValue:
            return "Loading"
        case M2SRendererRuntimeState.converting.rawValue:
            return "Converting"
        case M2SRendererRuntimeState.rendering.rawValue:
            return "Rendering"
        case M2SRendererRuntimeState.failed.rawValue:
            return "Failed"
        case M2SRendererRuntimeState.exporting.rawValue:
            return "Exporting"
        default:
            return "Unknown"
        }
    }

    static func runtimeStateTitle(rawValue: Int) -> String {
        guard let rawValue = UInt(exactly: rawValue) else {
            return "Unknown"
        }

        return runtimeStateTitle(rawValue: rawValue)
    }

    static func diagnosticSeverityTitle(_ severity: M2SRendererDiagnosticSeverity) -> String {
        diagnosticSeverityTitle(rawValue: severity.rawValue)
    }

    static func diagnosticSeverityTitle(rawValue: UInt) -> String {
        switch rawValue {
        case M2SRendererDiagnosticSeverity.warning.rawValue:
            return "Warning"
        case M2SRendererDiagnosticSeverity.error.rawValue:
            return "Error"
        default:
            return "Info"
        }
    }

    static func diagnosticSeverityTitle(rawValue: Int) -> String {
        guard let rawValue = UInt(exactly: rawValue) else {
            return "Info"
        }

        return diagnosticSeverityTitle(rawValue: rawValue)
    }

    static func diagnosticStatusText(severity: M2SRendererDiagnosticSeverity, errorMessage: String) -> String {
        diagnosticStatusText(severityTitle: diagnosticSeverityTitle(severity), errorMessage: errorMessage)
    }

    static func diagnosticStatusText(severityTitle: String, errorMessage: String) -> String {
        let trimmedMessage = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedMessage.isEmpty else {
            return severityTitle
        }

        return "\(severityTitle): \(trimmedMessage)"
    }

    private static func nonNegativeFinite(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0.0
        }

        return max(value, 0.0)
    }

    private static func fixedDecimal(_ value: Double, fractionDigits: Int) -> String {
        let fractionDigits = max(fractionDigits, 0)
        return String(format: "%.\(fractionDigits)f", value)
    }
}
