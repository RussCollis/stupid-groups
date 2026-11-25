import SwiftUI
import AppKit

// Russell Collis app theme: Jamf Pro-style layout in Patch Gap branding, from Version Report.
// Every colour has a dark-appearance variant. Copy this file into a macOS SwiftUI app as-is.
enum Theme {
    static let sidebar = Color(light: 0x0E1E4D, dark: 0x0A1533)
    static let sidebarHeading = Color(light: 0xAEBBDD, dark: 0x8F9CC0)
    static let sidebarSelected = Color(light: 0x2B4AA8, dark: 0x2E4FB5)
    static let sidebarText = Color.white
    static let sidebarDimText = Color.white.opacity(0.55)

    static let content = Color(light: 0xF2F4F7, dark: 0x17191D)
    static let panel = Color(light: 0xFFFFFF, dark: 0x23262B)
    static let panelBar = Color(light: 0xF7F8FA, dark: 0x2A2D33)
    static let border = Color(light: 0xDDE1E8, dark: 0x3A3E46)
    static let rowHighlight = Color(light: 0xEAF0FD, dark: 0x263A66)

    static let primary = Color(light: 0x2F67E0, dark: 0x3F78EE)
    static let link = Color(light: 0x2F67E0, dark: 0x7FA6F8)
    /// Link blue that turns white on a selected, highlighted table row, so it stays readable.
    static let rowLink = RowLinkStyle()
    static let navy = Color(light: 0x1A3F9E, dark: 0x9DB4F2)
    static let updateOrange = Color(light: 0xFFA41B, dark: 0xFFB547)

    // Text colours for statuses and chips. Always paired with an icon, never colour alone.
    static let green = Color(light: 0x1E7B34, dark: 0x5BC774)
    static let orange = Color(light: 0xA65A00, dark: 0xFFB45C)
    static let red = Color(light: 0xBE2A1F, dark: 0xFF7A70)
    static let blue = Color(light: 0x2F57C8, dark: 0x8AAAF5)
    static let purple = Color(light: 0x4B3FB0, dark: 0xAEA5F5)
    static let teal = Color(light: 0x0E6E6A, dark: 0x5FD0C8)
    static let grey = Color(light: 0x5B6270, dark: 0xA4ABB8)
}

extension Color {
    /// A colour that switches between two hex values with the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Panels

/// White panel with a 1 px border, 8 px radius, and an optional header and footer bar.
struct Panel<Content: View, Accessory: View>: View {
    var title: String?
    var detail: String?
    var footer: String?
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil,
         detail: String? = nil,
         footer: String? = nil,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.detail = detail
        self.footer = footer
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    if let detail {
                        Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    accessory()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 42)
                .background(Theme.panelBar)
                Divider().overlay(Theme.border)
            }

            content()

            if let footer {
                Divider().overlay(Theme.border)
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panelBar)
            }
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// Label/value rows inside a panel, as on a Jamf Pro record page.
struct FieldRows: View {
    let rows: [(String, String)]
    var valueColor: [String: Color] = [:]
    var monospaced: Set<String> = []

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 9) {
            ForEach(rows, id: \.0) { label, value in
                GridRow {
                    Text(label)
                        .foregroundStyle(.secondary)
                        .frame(width: 150, alignment: .leading)
                    Text(value)
                        .font(monospaced.contains(label) ? .system(size: 13, design: .monospaced) : .system(size: 13))
                        .foregroundStyle(valueColor[label] ?? .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 13))
        .padding(16)
    }
}

// MARK: - Page header and chips

struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 22, weight: .semibold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) { actions() }
        }
    }
}

/// Summary chip: SF Symbol, count and label, tinted text on the same colour at 14 %.
struct StatChip: View {
    let symbol: String
    let count: Int
    let label: String
    let tint: Color
    var isSelected = false
    var action: (() -> Void)? = nil

    var body: some View {
        let chip = HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text("\(count)").font(.system(size: 14, weight: .bold))
            Text(label).font(.system(size: 13))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tint.opacity(isSelected ? 0.26 : 0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint, lineWidth: isSelected ? 1.5 : 0))
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if let action {
            Button(action: action) { chip }.buttonStyle(.plain)
        } else {
            chip
        }
    }
}

/// Wrapping row of chips.
struct ChipRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        FlowLayout(spacing: 8) { content() }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap: CGFloat = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += size.width + gap
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

// MARK: - Buttons

/// White bordered secondary button, or the single blue primary button on a page.
struct PanelButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? Color.white : (destructive ? Theme.red : Color.primary))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(prominent ? Theme.primary : Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(prominent ? Color.clear : Theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.45))
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PanelButtonStyle {
    static var panel: PanelButtonStyle { PanelButtonStyle() }
    static var panelPrimary: PanelButtonStyle { PanelButtonStyle(prominent: true) }
    static var panelDestructive: PanelButtonStyle { PanelButtonStyle(destructive: true) }
}

// MARK: - Status labels

/// Icon plus text status label.
struct StatusLabel: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).symbolRenderingMode(.hierarchical)
        }
        .font(.system(size: 13))
        .foregroundStyle(color)
        .lineLimit(1)
    }
}

/// `Theme.link`, except on an increased-prominence background (a selected row in a focused table), where it's white.
struct RowLinkStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.backgroundProminence == .increased ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.link)
    }
}
