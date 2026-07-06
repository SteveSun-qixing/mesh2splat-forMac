import SwiftUI

struct RenderControlsPanel: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            RenderControlSection("Display") {
                Picker("Mode", selection: $appState.renderMode) {
                    ForEach(RenderMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 14) {
                    Toggle("Mesh", isOn: $appState.meshRenderingEnabled)
                    Toggle("Gaussians", isOn: $appState.gaussianRenderingEnabled)
                }

                Toggle("Sort gaussians", isOn: $appState.sortingEnabled)
                Toggle("Depth test", isOn: $appState.depthTestEnabled)
                Toggle("Split view", isOn: $appState.splitScreenEnabled)
                if appState.splitScreenEnabled {
                    RenderControlSlider(
                        title: "Split",
                        value: $appState.splitScreenPosition,
                        range: 0.0...1.0,
                        format: "%.2f"
                    )
                }
                Toggle("Wireframe", isOn: $appState.showMeshWireframe)
                Toggle("Centers", isOn: $appState.showGaussianCenters)
                Toggle("Sort order", isOn: $appState.showSortOrder)

                RenderControlSlider(
                    title: "Splat size",
                    value: $appState.splatSize,
                    range: 0.1...8.0,
                    format: "%.2fx"
                )
            }

            Divider()

            RenderControlSection("Image") {
                RenderControlSlider(
                    title: "Exposure",
                    value: $appState.exposure,
                    range: 0.0...16.0,
                    format: "%.2f"
                )
                RenderControlSlider(
                    title: "Gamma",
                    value: $appState.gamma,
                    range: 0.1...4.0,
                    format: "%.2f"
                )
                RenderControlSlider(
                    title: "Background",
                    value: $appState.backgroundBrightness,
                    range: 0.0...1.0,
                    format: "%.2f"
                )
            }

            Divider()

            RenderControlSection("Lighting") {
                Toggle("Enabled", isOn: $appState.lightingEnabled)
                Toggle("Shadows", isOn: $appState.shadowsEnabled)
                    .disabled(!appState.lightingEnabled)

                Group {
                    RenderControlSlider(
                        title: "Light X",
                        value: $appState.lightPositionX,
                        range: -10.0...10.0,
                        format: "%.1f"
                    )
                    RenderControlSlider(
                        title: "Light Y",
                        value: $appState.lightPositionY,
                        range: -10.0...10.0,
                        format: "%.1f"
                    )
                    RenderControlSlider(
                        title: "Light Z",
                        value: $appState.lightPositionZ,
                        range: -10.0...10.0,
                        format: "%.1f"
                    )
                    RenderControlSlider(
                        title: "Intensity",
                        value: $appState.lightIntensity,
                        range: 0.0...1000.0,
                        format: "%.0f"
                    )

                    HStack {
                        Text("Color")
                        Spacer(minLength: 12)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(
                                red: appState.lightColorRed.clamped(to: 0.0...1.0),
                                green: appState.lightColorGreen.clamped(to: 0.0...1.0),
                                blue: appState.lightColorBlue.clamped(to: 0.0...1.0)
                            ))
                            .frame(width: 28, height: 16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(.secondary.opacity(0.35), lineWidth: 1)
                            )
                    }

                    RenderControlSlider(
                        title: "Red",
                        value: $appState.lightColorRed,
                        range: 0.0...2.0,
                        format: "%.2f"
                    )
                    RenderControlSlider(
                        title: "Green",
                        value: $appState.lightColorGreen,
                        range: 0.0...2.0,
                        format: "%.2f"
                    )
                    RenderControlSlider(
                        title: "Blue",
                        value: $appState.lightColorBlue,
                        range: 0.0...2.0,
                        format: "%.2f"
                    )
                }
                .disabled(!appState.lightingEnabled)
            }

            Divider()

            RenderControlSection("Conversion") {
                Picker("Quality", selection: $appState.conversionQuality) {
                    ForEach(ConversionQuality.allCases) { quality in
                        Text("\(quality.title) (\(quality.rawValue)x)").tag(quality)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Render Controls")
                .font(.headline)

            Spacer(minLength: 12)

            Button {
                appState.resetRenderSettings()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct RenderControlSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
    }
}

private struct RenderControlSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Text(String(format: format, value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
