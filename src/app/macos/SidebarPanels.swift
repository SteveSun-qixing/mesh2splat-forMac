import SwiftUI

struct SidebarPanel<HeaderAccessory: View, Content: View>: View {
    let title: String
    let systemImage: String?
    let spacing: CGFloat
    let minWidth: CGFloat
    let idealWidth: CGFloat
    let maxWidth: CGFloat

    private let headerAccessory: HeaderAccessory
    private let content: Content

    init(
        _ title: String,
        systemImage: String? = nil,
        spacing: CGFloat = 14,
        minWidth: CGFloat = 260,
        idealWidth: CGFloat = 300,
        maxWidth: CGFloat = 360,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.spacing = spacing
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            PanelHeader(title, systemImage: systemImage) {
                headerAccessory
            }

            content

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(
            minWidth: minWidth,
            idealWidth: idealWidth,
            maxWidth: maxWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }
}

extension SidebarPanel where HeaderAccessory == EmptyView {
    init(
        _ title: String,
        systemImage: String? = nil,
        spacing: CGFloat = 14,
        minWidth: CGFloat = 260,
        idealWidth: CGFloat = 300,
        maxWidth: CGFloat = 360,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title,
            systemImage: systemImage,
            spacing: spacing,
            minWidth: minWidth,
            idealWidth: idealWidth,
            maxWidth: maxWidth,
            headerAccessory: EmptyView.init,
            content: content
        )
    }
}

struct PanelHeader<Accessory: View>: View {
    let title: String
    let systemImage: String?

    private let accessory: Accessory

    init(
        _ title: String,
        systemImage: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.headline)
            } else {
                Text(title)
                    .font(.headline)
            }

            Spacer(minLength: 12)

            accessory
                .controlSize(.small)
        }
    }
}

extension PanelHeader where Accessory == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title, systemImage: systemImage, accessory: EmptyView.init)
    }
}

struct PanelSection<Content: View>: View {
    let title: String
    let spacing: CGFloat
    let content: Content

    init(
        _ title: String,
        spacing: CGFloat = 10,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: spacing + 2) {
                content
            }
        }
    }
}

struct PanelDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 2)
    }
}
