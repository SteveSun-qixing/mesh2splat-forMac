import SwiftUI

struct InspectorPanel: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inspector")
                .font(.headline)

            GroupBox("Render") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Mode", selection: $appState.renderMode) {
                        ForEach(RenderMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Mesh", isOn: $appState.meshRenderingEnabled)
                    Toggle("Gaussians", isOn: $appState.gaussianRenderingEnabled)
                    Toggle("Sort gaussians", isOn: $appState.sortingEnabled)
                    Toggle("Centers", isOn: $appState.showGaussianCenters)
                    Toggle("Sort order", isOn: $appState.showSortOrder)

                    LabeledSlider(
                        title: "Splat size",
                        value: $appState.splatSize,
                        range: 0.1...8.0,
                        format: "%.2fx"
                    )
                }
                .padding(.vertical, 4)
            }

            GroupBox("Image") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledSlider(
                        title: "Exposure",
                        value: $appState.exposure,
                        range: 0.0...16.0,
                        format: "%.2f"
                    )
                    LabeledSlider(
                        title: "Gamma",
                        value: $appState.gamma,
                        range: 0.1...4.0,
                        format: "%.2f"
                    )
                    ColorPicker(
                        "Background",
                        selection: Binding(
                            get: { appState.backgroundColor },
                            set: { appState.setBackgroundColor($0) }
                        ),
                        supportsOpacity: false
                    )
                }
                .padding(.vertical, 4)
            }

            GroupBox("Conversion") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Quality", selection: $appState.conversionQuality) {
                        ForEach(ConversionQuality.allCases) { quality in
                            Text("\(quality.title) (\(quality.rawValue)x)").tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Mesh to splats", isOn: $appState.conversionEnabled)

                    ProgressView(value: appState.conversionProgress) {
                        Text("Progress")
                    } currentValueLabel: {
                        Text(appState.conversionProgressText)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Telemetry") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Runtime", value: appState.rendererRuntimeStatus)
                    LabeledContent("Diagnostic", value: appState.diagnosticStatus)
                    LabeledContent("Drawable", value: appState.drawableStatus)
                    LabeledContent("Frames", value: appState.frameCounterText)
                    LabeledContent("Timing", value: appState.frameTimingText)
                    LabeledContent("Gaussians", value: appState.gaussianCountText)
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)

            Button("Reset") {
                appState.resetRenderSettings()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}
