import SwiftUI
import AppKit

// MARK: - Claude Theme Colors

@MainActor
public enum ClaudeTheme {
    // MARK: - Accent
    public static var accent: Color        { ThemeStore.shared.colors.accent }
    public static var accentSubtle: Color  { ThemeStore.shared.colors.accentSubtle }

    // MARK: - Backgrounds
    public static var background: Color        { ThemeStore.shared.colors.background }
    public static var surfacePrimary: Color    { ThemeStore.shared.colors.surfacePrimary }
    public static var surfaceSecondary: Color  { ThemeStore.shared.colors.surfaceSecondary }
    public static var surfaceTertiary: Color   { ThemeStore.shared.colors.surfaceTertiary }
    public static var surfaceElevated: Color   { ThemeStore.shared.colors.surfaceElevated }

    // MARK: - Sidebar
    public static var sidebarBackground: Color   { ThemeStore.shared.colors.sidebarBackground }
    public static var sidebarItemHover: Color    { ThemeStore.shared.colors.sidebarItemHover }
    public static var sidebarItemSelected: Color { ThemeStore.shared.colors.sidebarItemSelected }

    // MARK: - Text
    public static var textPrimary: Color   { ThemeStore.shared.colors.textPrimary }
    public static var textSecondary: Color { ThemeStore.shared.colors.textSecondary }
    public static var textTertiary: Color  { ThemeStore.shared.colors.textTertiary }
    public static var textOnAccent: Color  { ThemeStore.shared.colors.textOnAccent }

    // MARK: - Borders
    public static var border: Color       { ThemeStore.shared.colors.border }
    public static var borderSubtle: Color { ThemeStore.shared.colors.borderSubtle }

    // MARK: - Code Blocks
    public static var codeBackground: Color       { ThemeStore.shared.colors.codeBackground }
    public static var codeHeaderBackground: Color { ThemeStore.shared.colors.codeHeaderBackground }

    // MARK: - User Bubble
    public static var userBubble: Color     { ThemeStore.shared.colors.userBubble }
    public static var userBubbleText: Color { ThemeStore.shared.colors.userBubbleText }

    // MARK: - Assistant Bubble
    public static var assistantBubble: Color { ThemeStore.shared.colors.assistantBubble }

    // MARK: - Status Colors
    public static var statusSuccess: Color { ThemeStore.shared.colors.statusSuccess }
    public static var statusError: Color   { ThemeStore.shared.colors.statusError }
    public static var statusWarning: Color { ThemeStore.shared.colors.statusWarning }
    public static var statusRunning: Color { ThemeStore.shared.colors.statusRunning }

    // MARK: - Input
    public static var inputBackground: Color  { ThemeStore.shared.colors.inputBackground }
    public static var inputBorder: Color      { ThemeStore.shared.colors.inputBorder }
    public static var inputPlaceholder: Color { ThemeStore.shared.colors.inputPlaceholder }

    // MARK: - Font Size
    public static func size(_ base: CGFloat) -> CGFloat {
        base + CGFloat(ThemeStore.shared.fontSizeAdjustment)
    }

    public static func messageSize(_ base: CGFloat) -> CGFloat {
        base + CGFloat(ThemeStore.shared.messageFontSizeAdjustment)
    }

    // MARK: - Dimensions
    public static let cornerRadiusSmall: CGFloat = 8
    public static let cornerRadiusMedium: CGFloat = 12
    public static let cornerRadiusLarge: CGFloat = 16
    public static let cornerRadiusPill: CGFloat = 20

    // MARK: - Shadows
    public static let shadowColor = Color.black.opacity(0.08)
    public static let shadowRadius: CGFloat = 8
}

// MARK: - Color Helpers

extension Color {
    public init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
    }
}

extension Color {
    public static func hex(_ hex: UInt, opacity: Double = 1.0) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    public init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(hex: UInt(rgb))
    }

    public var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#0000FF" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Theme View Modifiers

extension View {
    public func pointerCursorOnHover() -> some View {
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    public func claudeCard() -> some View {
        self
            .background(ClaudeTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusMedium)
                    .strokeBorder(ClaudeTheme.border, lineWidth: 0.5)
            )
    }

    public func claudeInputField() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(ClaudeTheme.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusPill))
            .overlay(
                RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusPill)
                    .strokeBorder(ClaudeTheme.inputBorder, lineWidth: 1)
            )
    }
}

// MARK: - Claude Button Styles

public struct ClaudeAccentButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                configuration.isPressed
                    ? ClaudeTheme.accent.opacity(0.8)
                    : ClaudeTheme.accent
            )
            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
    }
}

public struct ClaudeSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ClaudeTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                configuration.isPressed
                    ? ClaudeTheme.surfaceTertiary
                    : ClaudeTheme.surfaceSecondary
            )
            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
    }
}

// MARK: - Claude Send Button

public struct ClaudeSendButton: View {
    public let isEnabled: Bool
    public let action: () -> Void

    public init(isEnabled: Bool, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: ClaudeTheme.size(14), weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(isEnabled ? ClaudeTheme.accent : ClaudeTheme.textTertiary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Claude Theme Divider

public struct ClaudeThemeDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(ClaudeTheme.border)
            .frame(height: 1)
    }
}
