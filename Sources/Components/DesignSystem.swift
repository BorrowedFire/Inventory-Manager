import SwiftUI
import AppKit

enum AppTheme {
    static let backgroundTop = Color(red: 0.95, green: 0.93, blue: 0.89)
    static let backgroundBottom = Color(red: 0.86, green: 0.90, blue: 0.95)
    static let panel = Color.white.opacity(0.84)
    static let stroke = Color.black.opacity(0.08)
    static let text = Color(red: 0.11, green: 0.14, blue: 0.19)
    static let muted = Color(red: 0.35, green: 0.41, blue: 0.47)
    static let gold = Color(red: 0.78, green: 0.56, blue: 0.16)
    static let blue = Color(red: 0.17, green: 0.36, blue: 0.73)
    static let rose = Color(red: 0.73, green: 0.29, blue: 0.31)
    static let teal = Color(red: 0.16, green: 0.54, blue: 0.52)
}

struct FrostedPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            )
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
        VStack(alignment: .leading, spacing: 10) {
            Text(stat.title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.muted)
                .tracking(1.4)

            Text(stat.value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.text)

            Text(stat.note)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(accentGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
    }

    private var accentGradient: LinearGradient {
        switch stat.accent {
        case "amber":
            LinearGradient(colors: [Color(red: 0.98, green: 0.90, blue: 0.72), Color.white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "blue":
            LinearGradient(colors: [Color(red: 0.82, green: 0.89, blue: 0.98), Color.white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "teal":
            LinearGradient(colors: [Color(red: 0.80, green: 0.94, blue: 0.92), Color.white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "rose":
            LinearGradient(colors: [Color(red: 0.98, green: 0.84, blue: 0.84), Color.white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "indigo":
            LinearGradient(colors: [Color(red: 0.87, green: 0.86, blue: 0.98), Color.white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            LinearGradient(colors: [Color(red: 0.85, green: 0.97, blue: 0.92), Color.white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct SectionShell<Content: View>: View {
    let title: String
    let eyebrow: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.blue)
                        .tracking(1.6)
                    Text(title)
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.text)
                    if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(subtitle)
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                content
            }
            .padding(28)
        }
        .background(
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct ItemTypeIconView: View {
    let itemType: String
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.84))
            Image(systemName: ItemTypeIconCatalog.symbol(for: itemType))
                .symbolRenderingMode(.monochrome)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tintColor)
        }
        .frame(width: size + 18, height: size + 18)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
