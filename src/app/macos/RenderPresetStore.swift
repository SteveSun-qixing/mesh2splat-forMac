import Foundation

struct RenderPreset: Codable, Equatable {
    struct Lighting: Codable, Equatable {
        var enabled: Bool
        var positionX: Double
        var positionY: Double
        var positionZ: Double
        var intensity: Double
        var colorRed: Double
        var colorGreen: Double
        var colorBlue: Double

        static let defaults = Lighting(
            enabled: true,
            positionX: 3.0,
            positionY: 4.0,
            positionZ: 2.5,
            intensity: 1.0,
            colorRed: 1.0,
            colorGreen: 0.95,
            colorBlue: 0.85
        )

        var normalized: Lighting {
            Lighting(
                enabled: enabled,
                positionX: positionX.clamped(to: -100.0...100.0),
                positionY: positionY.clamped(to: -100.0...100.0),
                positionZ: positionZ.clamped(to: -100.0...100.0),
                intensity: intensity.clamped(to: 0.0...16.0),
                colorRed: colorRed.clamped(to: 0.0...4.0),
                colorGreen: colorGreen.clamped(to: 0.0...4.0),
                colorBlue: colorBlue.clamped(to: 0.0...4.0)
            )
        }
    }

    struct Toggles: Codable, Equatable {
        var sortingEnabled: Bool
        var meshRenderingEnabled: Bool
        var gaussianRenderingEnabled: Bool
        var conversionEnabled: Bool

        static let defaults = Toggles(
            sortingEnabled: true,
            meshRenderingEnabled: true,
            gaussianRenderingEnabled: true,
            conversionEnabled: true
        )
    }

    static let defaults = RenderPreset(
        renderMode: .final,
        splatSize: 1.0,
        exposure: 1.0,
        gamma: 2.2,
        backgroundBrightness: 0.04,
        lighting: .defaults,
        quality: .balanced,
        toggles: .defaults
    )

    private static let currentVersion = 2

    private var version: Int
    private var renderModeRawValue: Int
    var splatSize: Double
    var exposure: Double
    var gamma: Double
    var backgroundBrightness: Double
    var lighting: Lighting
    private var qualityRawValue: Int
    var toggles: Toggles

    var renderMode: RenderMode {
        get { RenderMode(rawValue: renderModeRawValue) ?? Self.defaults.renderMode }
        set { renderModeRawValue = newValue.rawValue }
    }

    var quality: ConversionQuality {
        get { ConversionQuality(rawValue: qualityRawValue) ?? Self.defaults.quality }
        set { qualityRawValue = newValue.rawValue }
    }

    init(
        renderMode: RenderMode,
        splatSize: Double,
        exposure: Double,
        gamma: Double,
        backgroundBrightness: Double,
        lighting: Lighting,
        quality: ConversionQuality,
        toggles: Toggles
    ) {
        self.version = Self.currentVersion
        self.renderModeRawValue = renderMode.rawValue
        self.splatSize = splatSize.clamped(to: 0.1...8.0)
        self.exposure = exposure.clamped(to: 0.0...16.0)
        self.gamma = gamma.clamped(to: 0.1...4.0)
        self.backgroundBrightness = backgroundBrightness.clamped(to: 0.0...1.0)
        self.lighting = lighting.normalized
        self.qualityRawValue = quality.rawValue
        self.toggles = toggles
    }

    var normalized: RenderPreset {
        RenderPreset(
            renderMode: renderMode,
            splatSize: splatSize,
            exposure: exposure,
            gamma: gamma,
            backgroundBrightness: backgroundBrightness,
            lighting: lighting,
            quality: quality,
            toggles: toggles
        )
    }
}

struct RenderPresetStore {
    static let defaultKey = "mesh2splat.renderPreset.v1"

    var defaults: UserDefaults
    var key: String

    init(defaults: UserDefaults = .standard, key: String = RenderPresetStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() throws -> RenderPreset? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try JSONDecoder().decode(RenderPreset.self, from: data).normalized
    }

    func loadOrDefault() -> RenderPreset {
        (try? load()) ?? .defaults
    }

    func save(_ preset: RenderPreset) throws {
        let data = try JSONEncoder().encode(preset.normalized)
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    var hasSavedPreset: Bool {
        defaults.object(forKey: key) != nil
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
