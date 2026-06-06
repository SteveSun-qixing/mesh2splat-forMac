import SwiftUI

struct StatusBarView: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        HStack(spacing: 12) {
            Text(appState.statusText)
                .lineLimit(1)
                .truncationMode(.middle)

            if let error = appState.lastError, !error.isEmpty {
                Divider()
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            statusLabel(appState.importStatus)
            Divider()
            statusLabel(appState.conversionStatus)
            Divider()
            statusLabel(appState.exportStatus)
            Divider()
            statusLabel(appState.frameTimingText)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
    }

    private func statusLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.middle)
    }
}
