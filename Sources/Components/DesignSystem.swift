import SwiftUI
import AppKit

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    static let storageKey = "appearance.preference"

    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: .dark
        case .light: .light
        }
    }
}

enum AppTheme {
    static let panelRadius: CGFloat = 14
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8

    static let backgroundTop = adaptive(light: rgb(246, 247, 249), dark: rgb(6, 7, 9))
    static let backgroundBottom = adaptive(light: rgb(229, 233, 238), dark: rgb(14, 15, 18))
    static let sidebar = adaptive(light: rgb(238, 241, 245), dark: rgb(9, 10, 12))
    static let panel = adaptive(light: rgb(255, 255, 255, alpha: 0.88), dark: rgb(24, 25, 28, alpha: 0.90))
    static let panelElevated = adaptive(light: rgb(255, 255, 255, alpha: 0.96), dark: rgb(31, 32, 36, alpha: 0.96))
    static let controlBackground = adaptive(light: rgb(244, 246, 249), dark: rgb(37, 38, 42))
    static let row = adaptive(light: rgb(248, 249, 251), dark: rgb(31, 32, 36))
    static let rowSelected = adaptive(light: rgb(232, 240, 255), dark: rgb(41, 43, 49))
    static let sidebarSelection = adaptive(light: rgb(224, 234, 252), dark: rgb(38, 40, 46))
    static let stroke = adaptive(light: rgb(25, 28, 34, alpha: 0.10), dark: rgb(255, 255, 255, alpha: 0.10))
    static let hairline = adaptive(light: rgb(25, 28, 34, alpha: 0.07), dark: rgb(255, 255, 255, alpha: 0.07))
    static let text = adaptive(light: rgb(18, 22, 28), dark: rgb(244, 246, 248))
    static let muted = adaptive(light: rgb(83, 91, 102), dark: rgb(165, 171, 181))
    static let secondaryText = adaptive(light: rgb(111, 119, 131), dark: rgb(126, 132, 143))
    static let gold = adaptive(light: rgb(161, 111, 0), dark: rgb(255, 202, 76))
    static let blue = adaptive(light: rgb(0, 102, 204), dark: rgb(88, 166, 255))
    static let rose = adaptive(light: rgb(190, 52, 67), dark: rgb(255, 99, 111))
    static let teal = adaptive(light: rgb(0, 128, 117), dark: rgb(82, 216, 196))
    static let green = adaptive(light: rgb(36, 138, 61), dark: rgb(94, 205, 117))

    static var appBackground: some ShapeStyle {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDarkAppearance ? dark : light
        })
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }
}

struct FrostedPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func frostedPanel() -> some View {
        modifier(FrostedPanel())
    }
}

struct StatCardView: View {
    let stat: DashboardStat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 30, height: 30)
                    .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(stat.title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .tracking(1.1)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(stat.value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.text)
                    .monospacedDigit()

                Text(stat.note)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }

            Capsule()
                .fill(accentColor.opacity(0.75))
                .frame(width: 36, height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.panelElevated, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    private var accentColor: Color {
        switch stat.accent {
        case "amber": AppTheme.gold
        case "blue", "indigo": AppTheme.blue
        case "teal": AppTheme.teal
        case "rose": AppTheme.rose
        default: AppTheme.green
        }
    }

    private var symbol: String {
        switch stat.title {
        case "Cataloged Items": "shippingbox.fill"
        case "Budget Overview": "chart.bar.doc.horizontal.fill"
        case "Inventory Value": "dollarsign.circle.fill"
        case "Total Deployed": "arrowshape.turn.up.right.fill"
        case "Low Stock Alerts": "exclamationmark.triangle.fill"
        case "Stockrooms": "building.2.fill"
        case "Database": "externaldrive.fill"
        default: "gauge.with.dots.needle.50percent"
        }
    }
}

struct SectionShell<Content: View>: View {
    let title: String
    let eyebrow: String
    let subtitle: String?
    let systemImage: String?
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            let contentPadding: CGFloat = proxy.size.width < 760 ? 18 : 28

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    content
                }
                .padding(contentPadding)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.appBackground)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if let systemImage {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppTheme.blue.opacity(0.13))
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.blue)
                }
                .frame(width: 42, height: 42)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(AppTheme.blue.opacity(0.18), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.blue)
                    .tracking(1.7)

                Text(title)
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)

                if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }
}

struct ItemTypeIconView: View {
    let itemType: String
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                .fill(tintColor.opacity(0.13))
            Image(systemName: ItemTypeIconCatalog.symbol(for: itemType))
                .symbolRenderingMode(.monochrome)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tintColor)
        }
        .frame(width: size + 18, height: size + 18)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                .stroke(tintColor.opacity(0.18), lineWidth: 1)
        )
        .accessibilityLabel("\(itemType) icon")
    }

    private var tintColor: Color {
        ItemTypeIconCatalog.tint(for: itemType)
    }

    private var backgroundColor: Color {
        tintColor.opacity(0.10)
    }
}

private extension NSAppearance {
    var isDarkAppearance: Bool {
        let darkAppearances: [NSAppearance.Name] = [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]
        return bestMatch(from: darkAppearances + [.aqua, .vibrantLight, .accessibilityHighContrastAqua, .accessibilityHighContrastVibrantLight]).map {
            darkAppearances.contains($0)
        } ?? false
    }
}

enum ItemTypeIconCatalog {
    private static let symbols: [String: String] = [
        "peripheral": "computermouse.fill",
        "warranty": "checkmark.shield.fill",
        "laptop": "laptopcomputer",
        "accessory": "shippingbox.fill",
        "cables": "cable.connector.horizontal",
        "monitor": "display.2",
        "desktop": "desktopcomputer",
        "phone": "iphone",
        "tools": "wrench.and.screwdriver.fill",
        "tablet": "ipad",
        "printer": "printer.fill",
        "services": "briefcase.fill",
        "av": "video.badge.waveform"
    ]

    private static let tintMap: [String: Color] = [
        "peripheral": AppTheme.blue,
        "warranty": AppTheme.teal,
        "laptop": AppTheme.blue,
        "accessory": AppTheme.gold,
        "cables": AppTheme.rose,
        "monitor": Color(red: 0.31, green: 0.44, blue: 0.78),
        "desktop": Color(red: 0.21, green: 0.35, blue: 0.55),
        "phone": Color(red: 0.18, green: 0.62, blue: 0.58),
        "tools": Color(red: 0.61, green: 0.39, blue: 0.15),
        "tablet": Color(red: 0.30, green: 0.49, blue: 0.84),
        "printer": Color(red: 0.44, green: 0.45, blue: 0.56),
        "services": Color(red: 0.48, green: 0.42, blue: 0.74),
        "av": Color(red: 0.69, green: 0.31, blue: 0.39)
    ]

    static func tint(for itemType: String) -> Color {
        tintMap[normalized(itemType)] ?? AppTheme.muted
    }

    static func symbol(for itemType: String) -> String {
        symbols[normalized(itemType)] ?? "shippingbox.fill"
    }

    private static func normalized(_ itemType: String) -> String {
        itemType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
