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
                        title: "Timing",
                        value: snapshot.frameTimingText,
                        systemImage: "timer",
                        tint: timingTint
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
                title: "Drawable",
                value: snapshot.drawableStatus,
                detail: drawableDetail,
                systemImage: "rectangle.inset.filled",
                tint: drawableTint
            ),
            ResourceTelemetryMetric(
                title: "Gaussians",
                value: snapshot.gaussianCountText,
                detail: gaussianDetail,
                systemImage: "circle.grid.cross",
                tint: gaussianTint
            ),
            ResourceTelemetryMetric(
                title: "Frames",
                value: snapshot.frameCounterText,
                detail: frameDetail,
                systemImage: "rectangle.stack",
                tint: frameTint
            ),
            ResourceTelemetryMetric(
                title: "Timing",
                value: snapshot.frameTimingText,
                detail: "CPU / GPU",
                systemImage: "timer",
                tint: timingTint
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

    private var gaussianTint: Color {
        gaussianCount > 0 ? .purple : .secondary
    }

    private var frameTint: Color {
        hasSubmittedFrames ? .green : .secondary
    }

    private var timingTint: Color {
        hasSubmittedFrames ? .teal : .secondary
    }

    private var drawableDetail: String {
        hasDrawable ? "Active surface" : "No drawable"
    }

    private var gaussianDetail: String {
        gaussianCount > 0 ? "Converted splats" : "No splats"
    }

    private var frameDetail: String {
        hasSubmittedFrames ? "Completed / submitted" : "No frames"
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
            .map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        guard parts.count == 2 else { return false }
        return parts[0] > 0 || parts[1] > 0
    }
}

@MainActor
struct ResourceTelemetrySnapshot {
    let runtimeStatus: String
    let drawableStatus: String
    let gaussianCountText: String
    let frameCounterText: String
    let frameTimingText: String
    let bridgeResources: [ResourceTelemetryBridgeResource]

    init(
        runtimeStatus: String,
        drawableStatus: String,
        gaussianCountText: String,
        frameCounterText: String,
        frameTimingText: String,
        bridgeResources: [ResourceTelemetryBridgeResource] = []
    ) {
        self.runtimeStatus = runtimeStatus
        self.drawableStatus = drawableStatus
        self.gaussianCountText = gaussianCountText
        self.frameCounterText = frameCounterText
        self.frameTimingText = frameTimingText
        self.bridgeResources = bridgeResources
    }

    init(appState: Mesh2SplatAppState, bridgeResources: [ResourceTelemetryBridgeResource] = []) {
        self.init(
            runtimeStatus: appState.rendererRuntimeStatus,
            drawableStatus: appState.drawableStatus,
            gaussianCountText: appState.gaussianCountText,
            frameCounterText: appState.frameCounterText,
            frameTimingText: appState.frameTimingText,
            bridgeResources: bridgeResources
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
