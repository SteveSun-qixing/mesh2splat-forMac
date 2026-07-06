import SwiftUI

struct StatusBarView: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        HStack(spacing: 10) {
            statusBadge(
                appState.rendererRuntimeStatus,
                systemImage: runtimeSymbolName,
                tint: runtimeTint
            )

            Divider()
                .frame(height: 16)

            Text(appState.statusText)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            if let error = appState.lastError, !error.isEmpty {
                Divider()
                    .frame(height: 16)
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            statusMetric("Scene", value: sceneStatus, systemImage: "cube")
            statusDivider
            statusMetric("Convert", value: conversionStatus, systemImage: "arrow.triangle.2.circlepath")
            statusDivider
            statusMetric("Export", value: exportStatus, systemImage: "square.and.arrow.up")
            statusDivider
            statusMetric("GPU", value: appState.frameTimingText, systemImage: "timer")
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
    }

    private var statusDivider: some View {
        Divider()
            .frame(height: 16)
    }

    private var sceneStatus: String {
        if let importedFileName = appState.importedFileName, !importedFileName.isEmpty {
            return importedFileName
        }

        return compactStatus(appState.importStatus, removingPrefix: "Import:")
    }

    private var conversionStatus: String {
        if appState.rendererRuntimeStatus == "Converting" {
            return "\(appState.conversionProgressText) · \(appState.conversionSamplesText)"
        }

        if appState.gaussianCount > 0 {
            return "\(appState.gaussianCountText) splats"
        }

        return compactStatus(appState.conversionStatus, removingPrefix: "Conversion:")
    }

    private var exportStatus: String {
        if appState.rendererRuntimeStatus == "Exporting" {
            return compactStatus(appState.exportStatus, removingPrefix: "Export:")
        }

        if let exportedFileName = appState.exportedFileName, !exportedFileName.isEmpty {
            return exportedFileName
        }

        return compactStatus(appState.exportStatus, removingPrefix: "Export:")
    }

    private var runtimeSymbolName: String {
        switch appState.rendererRuntimeStatus.lowercased() {
        case "failed":
            return "xmark.circle.fill"
        case "loading", "converting", "exporting":
            return "arrow.triangle.2.circlepath.circle.fill"
        case "ready", "rendering":
            return "checkmark.circle.fill"
        default:
            return "circle.fill"
        }
    }

    private var runtimeTint: Color {
        switch appState.rendererRuntimeStatus.lowercased() {
        case "failed":
            return .red
        case "loading", "converting", "exporting":
            return .orange
        case "ready", "rendering":
            return .green
        default:
            return .secondary
        }
    }

    private func statusBadge(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .help("Renderer runtime state")
    }

    private func statusMetric(_ title: String, value: String, systemImage: String) -> some View {
        Label {
            HStack(spacing: 3) {
                Text(title)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.middle)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tertiary)
        }
        .lineLimit(1)
        .help("\(title): \(value)")
    }

    private func compactStatus(_ text: String, removingPrefix prefix: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedText.localizedCaseInsensitiveContains(prefix) else {
            return trimmedText
        }

        return trimmedText
            .replacingOccurrences(of: prefix, with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
