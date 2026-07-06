import SwiftUI

@MainActor
struct ResourceTelemetryPanel: View {
    @ObservedObject private var appState: Mesh2SplatAppState
    private let snapshotOverride: ResourceTelemetrySnapshot?
    private let bridgeResources: [ResourceTelemetryBridgeResource]

    init(appState: Mesh2SplatAppState, bridgeResources: [ResourceTelemetryBridgeResource] = []) {
        self._appState = ObservedObject(wrappedValue: appState)
        self.snapshotOverride = nil
        self.bridgeResources = bridgeResources
    }

    init(appState: Mesh2SplatAppState, snapshot: ResourceTelemetrySnapshot) {
        self._appState = ObservedObject(wrappedValue: appState)
        self.snapshotOverride = snapshot
        self.bridgeResources = snapshot.bridgeResources
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            GroupBox("Resource Summary") {
                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 8) {
                    ForEach(summaryMetrics) { metric in
                        ResourceTelemetryMetricCard(metric: metric)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Runtime") {
                VStack(alignment: .leading, spacing: 10) {
                    ResourceTelemetryStatusRow(
                        title: "State",
                        value: snapshot.runtimeStatus,
                        systemImage: runtimeSymbolName,
                        tint: runtimeTint
                    )
                    ResourceTelemetryStatusRow(
                        title: "Drawable",
                        value: snapshot.drawableStatus,
                        systemImage: "rectangle.inset.filled",
                        tint: drawableTint
                    )
                    ResourceTelemetryStatusRow(
                        title: "Frames",
                        value: snapshot.frameCounterText,
                        systemImage: "rectangle.stack",
                        tint: frameTint
                    )
                    ResourceTelemetryStatusRow(
                        title: "Frame Failures",
                        value: snapshot.frameFailureText,
                        systemImage: "exclamationmark.triangle",
                        tint: frameFailureTint,
                        detail: "Failed command buffers"
                    )
                    ResourceTelemetryStatusRow(
                        title: "Timing",
                        value: snapshot.frameTimingText,
                        systemImage: "timer",
                        tint: timingTint
                    )
                }
                .padding(.vertical, 4)
            }

            GroupBox("Conversion") {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: snapshot.conversionProgress) {
                        HStack {
                            Text("Progress")
                            Spacer()
                            Text(snapshot.conversionProgressText)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }

                    ResourceTelemetryStatusRow(
                        title: "Submissions",
                        value: snapshot.conversionCounterText,
                        systemImage: "number",
                        tint: conversionTint,
                        detail: "Completed / submitted"
                    )
                    ResourceTelemetryStatusRow(
                        title: "Sampling",
                        value: snapshot.conversionSamplesText,
                        systemImage: "circle.grid.3x3",
                        tint: .purple,
                        detail: "Per-triangle density"
                    )
                    ResourceTelemetryStatusRow(
                        title: "Timing",
                        value: snapshot.conversionTimingText,
                        systemImage: "timer",
                        tint: timingTint,
                        detail: "CPU submit / GPU"
                    )
                    ResourceTelemetryStatusRow(
                        title: "Pending Memory",
                        value: snapshot.pendingConversionBytesText,
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: pendingConversionTint,
                        detail: "In-flight conversion buffers"
                    )
                }
                .padding(.vertical, 4)
            }

            if !snapshot.bridgeResources.isEmpty {
                GroupBox("Bridge Resources") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.bridgeResources) { resource in
                            ResourceTelemetryStatusRow(
                                title: resource.title,
                                value: resource.value,
                                systemImage: resource.systemImage,
                                tint: resource.tint,
                                detail: resource.detail
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
    }

    private var snapshot: ResourceTelemetrySnapshot {
        snapshotOverride ?? ResourceTelemetrySnapshot(appState: appState, bridgeResources: bridgeResources)
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 112), spacing: 8),
            GridItem(.flexible(minimum: 112), spacing: 8)
        ]
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Resource Telemetry")
                .font(.headline)

            Spacer(minLength: 12)

            Label(snapshot.runtimeStatus, systemImage: runtimeSymbolName)
                .font(.caption)
                .foregroundStyle(runtimeTint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var summaryMetrics: [ResourceTelemetryMetric] {
        [
            ResourceTelemetryMetric(
                title: "Tracked Total",
                value: snapshot.trackedBytesText,
                detail: "Renderer-owned resources",
                systemImage: "memorychip",
                tint: trackedTint
            ),
            ResourceTelemetryMetric(
                title: "Scene",
                value: snapshot.sceneBytesText,
                detail: sceneInventoryDetail,
                systemImage: "cube",
                tint: sceneTint
            ),
            ResourceTelemetryMetric(
                title: "Gaussian Buffers",
                value: snapshot.gaussianBytesText,
                detail: "\(snapshot.gaussianCountText) splats",
                systemImage: "circle.grid.cross",
                tint: gaussianTint
            ),
            ResourceTelemetryMetric(
                title: "Sort Workspace",
                value: snapshot.gaussianSortBytesText,
                detail: "Depth ordering buffers",
                systemImage: "arrow.up.arrow.down",
                tint: sortTint
            ),
            ResourceTelemetryMetric(
                title: "Pending",
                value: snapshot.pendingConversionBytesText,
                detail: snapshot.conversionProgressText,
                systemImage: "arrow.triangle.2.circlepath",
                tint: pendingConversionTint
            )
        ]
    }

    private var runtimeSymbolName: String {
        switch snapshot.runtimeStatus.lowercased() {
        case "failed":
            return "xmark.circle.fill"
        case "loading", "converting", "exporting":
            return "arrow.triangle.2.circlepath.circle.fill"
        case "rendering", "ready":
            return "checkmark.circle.fill"
        default:
            return "circle.fill"
        }
    }

    private var runtimeTint: Color {
        switch snapshot.runtimeStatus.lowercased() {
        case "failed":
            return .red
        case "loading", "converting", "exporting":
            return .orange
        case "rendering", "ready":
            return .green
        default:
            return .secondary
        }
    }

    private var drawableTint: Color {
        hasDrawable ? .blue : .secondary
    }

    private var trackedTint: Color {
        hasTrackedResources ? .teal : .secondary
    }

    private var sceneTint: Color {
        hasSceneResources ? .green : .secondary
    }

    private var gaussianTint: Color {
        gaussianCount > 0 ? .purple : .secondary
    }

    private var sortTint: Color {
        hasSortResources ? .orange : .secondary
    }

    private var pendingConversionTint: Color {
        hasPendingConversionResources ? .accentColor : .secondary
    }

    private var conversionTint: Color {
        snapshot.conversionProgress > 0 && snapshot.conversionProgress < 1 ? .accentColor : .secondary
    }

    private var frameTint: Color {
        hasSubmittedFrames ? .green : .secondary
    }

    private var frameFailureTint: Color {
        hasFrameFailures ? .red : .green
    }

    private var timingTint: Color {
        hasSubmittedFrames ? .teal : .secondary
    }

    private var sceneInventoryDetail: String {
        "\(snapshot.meshCountText) meshes, \(snapshot.materialCountText) materials, \(snapshot.textureCountText) textures"
    }

    private var hasDrawable: Bool {
        !snapshot.drawableStatus.hasPrefix("0x0")
    }

    private var gaussianCount: Int {
        Int(snapshot.gaussianCountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var hasSubmittedFrames: Bool {
        let parts = snapshot.frameCounterText
            .split(separator: "/")
            .map { integerValue(String($0)) }
        guard parts.count == 2 else { return false }
        return parts[0] > 0 || parts[1] > 0
    }

    private var hasTrackedResources: Bool {
        !snapshot.trackedBytesText.hasPrefix("0 B")
    }

    private var hasSceneResources: Bool {
        !snapshot.sceneBytesText.hasPrefix("0 B") ||
            snapshot.meshCountText != "0" ||
            snapshot.materialCountText != "0" ||
            snapshot.textureCountText != "0"
    }

    private var hasSortResources: Bool {
        !snapshot.gaussianSortBytesText.hasPrefix("0 B")
    }

    private var hasPendingConversionResources: Bool {
        !snapshot.pendingConversionBytesText.hasPrefix("0 B")
    }

    private var hasFrameFailures: Bool {
        !snapshot.frameFailureText.hasPrefix("0 ")
    }

    private func integerValue(_ text: String) -> Int {
        let numericPrefix = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { character in
                character.isNumber || character == ","
            }
            .replacingOccurrences(of: ",", with: "")

        return Int(numericPrefix) ?? 0
    }
}

@MainActor
struct ResourceTelemetrySnapshot {
    let runtimeStatus: String
    let drawableStatus: String
    let gaussianCountText: String
    let frameCounterText: String
    let frameTimingText: String
    let frameFailureText: String
    let conversionProgress: Double
    let conversionProgressText: String
    let conversionCounterText: String
    let conversionTimingText: String
    let conversionSamplesText: String
    let sceneBytesText: String
    let gaussianBytesText: String
    let gaussianSortBytesText: String
    let pendingConversionBytesText: String
    let trackedBytesText: String
    let meshCountText: String
    let materialCountText: String
    let textureCountText: String
    let bridgeResources: [ResourceTelemetryBridgeResource]

    init(
        runtimeStatus: String,
        drawableStatus: String,
        gaussianCountText: String,
        frameCounterText: String,
        frameTimingText: String,
        bridgeResources: [ResourceTelemetryBridgeResource] = [],
        frameFailureText: String = "0 failed",
        conversionProgress: Double = 0,
        conversionProgressText: String = "0%",
        conversionCounterText: String = "0 / 0",
        conversionTimingText: String = "Submit 0.0 ms / GPU 0.0 ms",
        conversionSamplesText: String = "0 samples",
        sceneBytesText: String = "0 B",
        gaussianBytesText: String = "0 B",
        gaussianSortBytesText: String = "0 B",
        pendingConversionBytesText: String = "0 B",
        trackedBytesText: String = "0 B",
        meshCountText: String = "0",
        materialCountText: String = "0",
        textureCountText: String = "0"
    ) {
        self.runtimeStatus = runtimeStatus
        self.drawableStatus = drawableStatus
        self.gaussianCountText = gaussianCountText
        self.frameCounterText = frameCounterText
        self.frameTimingText = frameTimingText
        self.frameFailureText = frameFailureText
        self.conversionProgress = conversionProgress
        self.conversionProgressText = conversionProgressText
        self.conversionCounterText = conversionCounterText
        self.conversionTimingText = conversionTimingText
        self.conversionSamplesText = conversionSamplesText
        self.sceneBytesText = sceneBytesText
        self.gaussianBytesText = gaussianBytesText
        self.gaussianSortBytesText = gaussianSortBytesText
        self.pendingConversionBytesText = pendingConversionBytesText
        self.trackedBytesText = trackedBytesText
        self.meshCountText = meshCountText
        self.materialCountText = materialCountText
        self.textureCountText = textureCountText
        self.bridgeResources = bridgeResources
    }

    init(appState: Mesh2SplatAppState, bridgeResources: [ResourceTelemetryBridgeResource] = []) {
        self.init(
            runtimeStatus: appState.rendererRuntimeStatus,
            drawableStatus: appState.drawableStatus,
            gaussianCountText: appState.gaussianCountText,
            frameCounterText: appState.frameCounterText,
            frameTimingText: appState.frameTimingText,
            bridgeResources: bridgeResources,
            frameFailureText: appState.frameFailureText,
            conversionProgress: appState.conversionProgress,
            conversionProgressText: appState.conversionProgressText,
            conversionCounterText: appState.conversionCounterText,
            conversionTimingText: appState.conversionTimingText,
            conversionSamplesText: appState.conversionSamplesText,
            sceneBytesText: appState.sceneBytesText,
            gaussianBytesText: appState.gaussianBytesText,
            gaussianSortBytesText: appState.gaussianSortBytesText,
            pendingConversionBytesText: appState.pendingConversionBytesText,
            trackedBytesText: appState.trackedBytesText,
            meshCountText: appState.meshCountText,
            materialCountText: appState.materialCountText,
            textureCountText: appState.textureCountText
        )
    }
}

struct ResourceTelemetryBridgeResource: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    init(
        id: String? = nil,
        title: String,
        value: String,
        detail: String,
        systemImage: String = "memorychip",
        tint: Color = .secondary
    ) {
        self.id = id ?? title
        self.title = title
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
    }
}

private struct ResourceTelemetryMetric: Identifiable {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var id: String { title }
}

private struct ResourceTelemetryMetricCard: View {
    let metric: ResourceTelemetryMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: metric.systemImage)
                    .foregroundStyle(metric.tint)
                    .font(.caption)
                    .frame(width: 14)

                Text(metric.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(metric.value)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(metric.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct ResourceTelemetryStatusRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.caption)
                .frame(width: 14)

            Text(title)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}
