import SwiftUI

struct MetricTone {
    let color: Color
    let symbolName: String?

    init(color: Color, symbolName: String? = nil) {
        self.color = color
        self.symbolName = symbolName
    }

    init(status: String) {
        let normalizedStatus = status.lowercased()

        if normalizedStatus.contains("failed") ||
            normalizedStatus.contains("error") {
            color = .red
            symbolName = "xmark.circle.fill"
        } else if normalizedStatus.contains("warning") {
            color = .orange
            symbolName = "exclamationmark.triangle.fill"
        } else if normalizedStatus.contains("choosing") ||
            normalizedStatus.contains("converting") ||
            normalizedStatus.contains("exporting") ||
            normalizedStatus.contains("loading") ||
            normalizedStatus.contains("running") ||
            normalizedStatus.contains("writing") ||
            normalizedStatus.contains("%") {
            color = .blue
            symbolName = "arrow.triangle.2.circlepath.circle.fill"
        } else if normalizedStatus.contains("ready") ||
            normalizedStatus.contains("loaded") ||
            normalizedStatus.contains("rendering") ||
            normalizedStatus.contains("saved") ||
            normalizedStatus.contains("info") ||
            normalizedStatus.contains("ok") {
            color = .green
            symbolName = "checkmark.circle.fill"
        } else {
            color = .secondary
            symbolName = "circle.fill"
        }
    }

    static let neutral = MetricTone(color: .secondary, symbolName: "circle.fill")
    static let accent = MetricTone(color: .accentColor, symbolName: "circle.fill")
    static let success = MetricTone(color: .green, symbolName: "checkmark.circle.fill")
    static let warning = MetricTone(color: .orange, symbolName: "exclamationmark.triangle.fill")
    static let danger = MetricTone(color: .red, symbolName: "xmark.circle.fill")
}

struct MetricRow: View {
    let title: String
    let value: String
    let detail: String?
    let tone: MetricTone?
    let monospacedValue: Bool
    let valueLineLimit: Int

    init(
        _ title: String,
        value: String,
        detail: String? = nil,
        tone: MetricTone? = nil,
        monospacedValue: Bool = true,
        valueLineLimit: Int = 1
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tone = tone
        self.monospacedValue = monospacedValue
        self.valueLineLimit = valueLineLimit
    }

    init(
        _ title: String,
        value: String,
        detail: String? = nil,
        systemImage: String?,
        tint: Color = .secondary,
        monospacedValue: Bool = true,
        valueLineLimit: Int = 1
    ) {
        self.init(
            title,
            value: value,
            detail: detail,
            tone: MetricTone(color: tint, symbolName: systemImage),
            monospacedValue: monospacedValue,
            valueLineLimit: valueLineLimit
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let tone {
                MetricSymbol(tone: tone)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            MetricValueText(
                value: value,
                monospaced: monospacedValue,
                lineLimit: valueLineLimit,
                alignment: .trailing
            )
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct MetricGrid<Content: View>: View {
    private let columns: [GridItem]
    private let spacing: CGFloat
    private let content: Content

    init(
        columnCount: Int = 2,
        minimumColumnWidth: CGFloat = 104,
        spacing: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        let column = GridItem(
            .flexible(minimum: minimumColumnWidth),
            spacing: spacing,
            alignment: .topLeading
        )

        self.columns = Array(repeating: column, count: Swift.max(columnCount, 1))
        self.spacing = spacing
        self.content = content()
    }

    init(
        columns: [GridItem],
        spacing: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.columns = columns
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            content
        }
    }
}

struct MetricBadge: View {
    let title: String
    let value: String
    let detail: String?
    let tone: MetricTone
    let monospacedValue: Bool

    init(
        _ title: String,
        value: String,
        detail: String? = nil,
        tone: MetricTone = .neutral,
        monospacedValue: Bool = false
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tone = tone
        self.monospacedValue = monospacedValue
    }

    init(
        _ title: String,
        value: String,
        detail: String? = nil,
        systemImage: String?,
        tint: Color = .secondary,
        monospacedValue: Bool = false
    ) {
        self.init(
            title,
            value: value,
            detail: detail,
            tone: MetricTone(color: tint, symbolName: systemImage),
            monospacedValue: monospacedValue
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            MetricSymbol(tone: tone)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                MetricValueText(
                    value: value,
                    monospaced: monospacedValue,
                    lineLimit: 1,
                    alignment: .leading
                )

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(tone.color.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MetricSymbol: View {
    let tone: MetricTone

    var body: some View {
        Group {
            if let symbolName = tone.symbolName {
                Image(systemName: symbolName)
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
            } else {
                Circle()
                    .frame(width: 8, height: 8)
            }
        }
        .foregroundStyle(tone.color)
        .frame(width: 14, height: 14)
    }
}

private struct MetricValueText: View {
    let value: String
    let monospaced: Bool
    let lineLimit: Int
    let alignment: TextAlignment

    var body: some View {
        Text(value)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.75)
            .truncationMode(.middle)
            .multilineTextAlignment(alignment)
            .metricMonospacedDigit(monospaced)
    }
}

private extension View {
    @ViewBuilder
    func metricMonospacedDigit(_ enabled: Bool) -> some View {
        if enabled {
            monospacedDigit()
        } else {
            self
        }
    }
}
