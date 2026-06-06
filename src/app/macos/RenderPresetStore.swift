import Foundation

struct RenderPreset: Codable, Equatable {
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
        quality: .balanced,
        toggles: .defaults
    )

    private static let currentVersion = 1

    private var version: Int
    private var renderModeRawValue: Int
    var splatSize: Double
    var exposure: Double
    var gamma: Double
    var backgroundBrightness: Double
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
        quality: ConversionQuality,
        toggles: Toggles
    ) {
        self.version = Self.currentVersion
        self.renderModeRawValue = renderMode.rawValue
        self.splatSize = splatSize.clamped(to: 0.1...8.0)
        self.exposure = exposure.clamped(to: 0.0...16.0)
        self.gamma = gamma.clamped(to: 0.1...4.0)
        self.backgroundBrightness = backgroundBrightness.clamped(to: 0.0...1.0)
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
