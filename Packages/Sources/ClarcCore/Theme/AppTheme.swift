import SwiftUI

// MARK: - Theme Colors Definition

public struct ThemeColors: @unchecked Sendable {
    public let accent: Color
    public let accentSubtle: Color
    public let background: Color
    public let surfacePrimary: Color
    public let surfaceSecondary: Color
    public let surfaceTertiary: Color
    public let surfaceElevated: Color
    public let sidebarBackground: Color
    public let sidebarItemHover: Color
    public let sidebarItemSelected: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let border: Color
    public let borderSubtle: Color
    public let codeBackground: Color
    public let codeHeaderBackground: Color
    public let userBubble: Color
    public let userBubbleText: Color
    public let assistantBubble: Color
    public let statusSuccess: Color
    public let statusError: Color
    public let statusWarning: Color
    public let inputBackground: Color
    public let inputBorder: Color

    public init(
        accent: Color, accentSubtle: Color,
        background: Color, surfacePrimary: Color, surfaceSecondary: Color,
        surfaceTertiary: Color, surfaceElevated: Color,
        sidebarBackground: Color, sidebarItemHover: Color, sidebarItemSelected: Color,
        textPrimary: Color, textSecondary: Color, textTertiary: Color,
        border: Color, borderSubtle: Color,
        codeBackground: Color, codeHeaderBackground: Color,
        userBubble: Color, userBubbleText: Color, assistantBubble: Color,
        statusSuccess: Color, statusError: Color, statusWarning: Color,
        inputBackground: Color, inputBorder: Color
    ) {
        self.accent = accent
        self.accentSubtle = accentSubtle
        self.background = background
        self.surfacePrimary = surfacePrimary
        self.surfaceSecondary = surfaceSecondary
        self.surfaceTertiary = surfaceTertiary
        self.surfaceElevated = surfaceElevated
        self.sidebarBackground = sidebarBackground
        self.sidebarItemHover = sidebarItemHover
        self.sidebarItemSelected = sidebarItemSelected
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.border = border
        self.borderSubtle = borderSubtle
        self.codeBackground = codeBackground
        self.codeHeaderBackground = codeHeaderBackground
        self.userBubble = userBubble
        self.userBubbleText = userBubbleText
        self.assistantBubble = assistantBubble
        self.statusSuccess = statusSuccess
        self.statusError = statusError
        self.statusWarning = statusWarning
        self.inputBackground = inputBackground
        self.inputBorder = inputBorder
    }

    // Computed shorthands
    public var textOnAccent: Color { .white }
    public var inputPlaceholder: Color { textTertiary }
    public var statusRunning: Color { accent }
}

// MARK: - Claude Theme (warm terracotta)

extension ThemeColors {
    public static let claude: ThemeColors = {
        let accent: Color = Color(light: .hex(0xD97757), dark: .hex(0xD97757))
        return ThemeColors(
            accent:               accent,
            accentSubtle:         Color(light: .hex(0xD97757).opacity(0.12), dark: .hex(0xD97757).opacity(0.15)),
            background:           Color(light: .hex(0xF5F4EF), dark: .hex(0x21211E)),
            surfacePrimary:       Color(light: .hex(0xEDEAE0), dark: .hex(0x2A2A27)),
            surfaceSecondary:     Color(light: .hex(0xE5E2D9), dark: .hex(0x353530)),
            surfaceTertiary:      Color(light: .hex(0xDDDAD2), dark: .hex(0x42423D)),
            surfaceElevated:      Color(light: .hex(0xFAF9F6), dark: .hex(0x2F2F2B)),
            sidebarBackground:    Color(light: .hex(0xEDEAE2), dark: .hex(0x1C1C1A)),
            sidebarItemHover:     Color(light: .hex(0xE0DDD4), dark: .hex(0x2A2A27)),
            sidebarItemSelected:  Color(light: .hex(0xD97757).opacity(0.12), dark: .hex(0xD97757).opacity(0.15)),
            textPrimary:          Color(light: .hex(0x3C3929), dark: .hex(0xCCC9C0)),
            textSecondary:        Color(light: .hex(0x6B6960), dark: .hex(0x9A978E)),
            textTertiary:         Color(light: .hex(0x9A978E), dark: .hex(0x76766E)),
            border:               Color(light: .hex(0xD5D2C8), dark: .hex(0x3B3B36)),
            borderSubtle:         Color(light: .hex(0xE0DDD4), dark: .hex(0x2F2F2B)),
            codeBackground:       Color(light: .hex(0xE8E5DC), dark: .hex(0x1A1A18)),
            codeHeaderBackground: Color(light: .hex(0xDDD9CF), dark: .hex(0x252523)),
            userBubble:           Color(light: .hex(0x3C3929), dark: .hex(0x42423D)),
            userBubbleText:       Color(light: .hex(0xF5F4EF), dark: .hex(0xE8E5DC)),
            assistantBubble:      Color(light: .hex(0xE8E5DC), dark: .hex(0x2A2A27)),
            statusSuccess:        Color(light: .hex(0x5A9A6E), dark: .hex(0x7AAC8C)),
            statusError:          Color(light: .hex(0xB85C50), dark: .hex(0xC47060)),
            statusWarning:        Color(light: .hex(0xC78A40), dark: .hex(0xD9A757)),
            inputBackground:      Color(light: .hex(0xFAF9F6), dark: .hex(0x2A2A27)),
            inputBorder:          Color(light: .hex(0xD5D2C8), dark: .hex(0x3B3B36))
        )
    }()
}

extension ThemeColors {
    public static let ocean: ThemeColors = {
        let accent: Color = Color(light: .hex(0x2E8BC0), dark: .hex(0x4CA8D4))
        return ThemeColors(
            accent:               accent,
            accentSubtle:         Color(light: .hex(0x2E8BC0).opacity(0.12), dark: .hex(0x4CA8D4).opacity(0.15)),
            background:           Color(light: .hex(0xF0F4F8), dark: .hex(0x111C27)),
            surfacePrimary:       Color(light: .hex(0xE7EEF5), dark: .hex(0x182433)),
            surfaceSecondary:     Color(light: .hex(0xDBE5EF), dark: .hex(0x1F2F41)),
            surfaceTertiary:      Color(light: .hex(0xCEDCE9), dark: .hex(0x273B50)),
            surfaceElevated:      Color(light: .hex(0xF6F9FC), dark: .hex(0x1A2D3E)),
            sidebarBackground:    Color(light: .hex(0xE3ECF4), dark: .hex(0x0D1820)),
            sidebarItemHover:     Color(light: .hex(0xD5E2EE), dark: .hex(0x182433)),
            sidebarItemSelected:  Color(light: .hex(0x2E8BC0).opacity(0.12), dark: .hex(0x4CA8D4).opacity(0.15)),
            textPrimary:          Color(light: .hex(0x192B3C), dark: .hex(0xC5D5E5)),
            textSecondary:        Color(light: .hex(0x476480), dark: .hex(0x7898B5)),
            textTertiary:         Color(light: .hex(0x7896AF), dark: .hex(0x527090)),
            border:               Color(light: .hex(0xC4D4E2), dark: .hex(0x2A3D52)),
            borderSubtle:         Color(light: .hex(0xD5E2EE), dark: .hex(0x1F2F41)),
            codeBackground:       Color(light: .hex(0xE0EBF3), dark: .hex(0x0C1722)),
            codeHeaderBackground: Color(light: .hex(0xD2E4EF), dark: .hex(0x132030)),
            userBubble:           Color(light: .hex(0x192B3C), dark: .hex(0x273B50)),
            userBubbleText:       Color(light: .hex(0xF0F4F8), dark: .hex(0xC5D5E5)),
            assistantBubble:      Color(light: .hex(0xE0EBF3), dark: .hex(0x182433)),
            statusSuccess:        Color(light: .hex(0x3A8A5E), dark: .hex(0x5A9E7A)),
            statusError:          Color(light: .hex(0xC0504A), dark: .hex(0xC46D64)),
            statusWarning:        Color(light: .hex(0xBF8530), dark: .hex(0xD4A050)),
            inputBackground:      Color(light: .hex(0xF6F9FC), dark: .hex(0x182433)),
            inputBorder:          Color(light: .hex(0xC4D4E2), dark: .hex(0x2A3D52))
        )
    }()
}

extension ThemeColors {
    public static let forest: ThemeColors = {
        let accent: Color = Color(light: .hex(0x2E7D52), dark: .hex(0x4DAA73))
        return ThemeColors(
            accent:               accent,
            accentSubtle:         Color(light: .hex(0x2E7D52).opacity(0.12), dark: .hex(0x4DAA73).opacity(0.15)),
            background:           Color(light: .hex(0xF0F5F1), dark: .hex(0x0F1E16)),
            surfacePrimary:       Color(light: .hex(0xE6EEE8), dark: .hex(0x162518)),
            surfaceSecondary:     Color(light: .hex(0xDAE5DC), dark: .hex(0x1E3022)),
            surfaceTertiary:      Color(light: .hex(0xCEDDD1), dark: .hex(0x253D2A)),
            surfaceElevated:      Color(light: .hex(0xF7FAF8), dark: .hex(0x1A2F1E)),
            sidebarBackground:    Color(light: .hex(0xE3EDE5), dark: .hex(0x0C1912)),
            sidebarItemHover:     Color(light: .hex(0xD6E5D9), dark: .hex(0x162518)),
            sidebarItemSelected:  Color(light: .hex(0x2E7D52).opacity(0.12), dark: .hex(0x4DAA73).opacity(0.15)),
            textPrimary:          Color(light: .hex(0x1A3328), dark: .hex(0xB8D4C2)),
            textSecondary:        Color(light: .hex(0x456B55), dark: .hex(0x7AA88A)),
            textTertiary:         Color(light: .hex(0x6B9078), dark: .hex(0x5A7D68)),
            border:               Color(light: .hex(0xC0D4C6), dark: .hex(0x2A3D30)),
            borderSubtle:         Color(light: .hex(0xD6E5D9), dark: .hex(0x1E3022)),
            codeBackground:       Color(light: .hex(0xDCE9DF), dark: .hex(0x0A160D)),
            codeHeaderBackground: Color(light: .hex(0xCEDDD1), dark: .hex(0x102015)),
            userBubble:           Color(light: .hex(0x1A3328), dark: .hex(0x253D2A)),
            userBubbleText:       Color(light: .hex(0xF0F5F1), dark: .hex(0xB8D4C2)),
            assistantBubble:      Color(light: .hex(0xDCE9DF), dark: .hex(0x162518)),
            statusSuccess:        Color(light: .hex(0x2E7D52), dark: .hex(0x4DAA73)),
            statusError:          Color(light: .hex(0xB85C50), dark: .hex(0xC47060)),
            statusWarning:        Color(light: .hex(0xC78A40), dark: .hex(0xD9A757)),
            inputBackground:      Color(light: .hex(0xF7FAF8), dark: .hex(0x162518)),
            inputBorder:          Color(light: .hex(0xC0D4C6), dark: .hex(0x2A3D30))
        )
    }()
}

extension ThemeColors {
    public static let lavender: ThemeColors = {
        let accent: Color = Color(light: .hex(0x7B5EA7), dark: .hex(0x9B7EC8))
        return ThemeColors(
            accent:               accent,
            accentSubtle:         Color(light: .hex(0x7B5EA7).opacity(0.12), dark: .hex(0x9B7EC8).opacity(0.15)),
            background:           Color(light: .hex(0xF4F2F8), dark: .hex(0x16111E)),
            surfacePrimary:       Color(light: .hex(0xEBE8F5), dark: .hex(0x1E1828)),
            surfaceSecondary:     Color(light: .hex(0xE0DBF0), dark: .hex(0x271F33)),
            surfaceTertiary:      Color(light: .hex(0xD4CEEA), dark: .hex(0x31273F)),
            surfaceElevated:      Color(light: .hex(0xF9F8FC), dark: .hex(0x211B2E)),
            sidebarBackground:    Color(light: .hex(0xE8E5F3), dark: .hex(0x110E18)),
            sidebarItemHover:     Color(light: .hex(0xDDD9EE), dark: .hex(0x1E1828)),
            sidebarItemSelected:  Color(light: .hex(0x7B5EA7).opacity(0.12), dark: .hex(0x9B7EC8).opacity(0.15)),
            textPrimary:          Color(light: .hex(0x2C2040), dark: .hex(0xC8BDE0)),
            textSecondary:        Color(light: .hex(0x5E4D80), dark: .hex(0x8878B0)),
            textTertiary:         Color(light: .hex(0x8B7AAC), dark: .hex(0x614F88)),
            border:               Color(light: .hex(0xC8C0E0), dark: .hex(0x352A48)),
            borderSubtle:         Color(light: .hex(0xDDD9EE), dark: .hex(0x271F33)),
            codeBackground:       Color(light: .hex(0xE2DDEF), dark: .hex(0x100C18)),
            codeHeaderBackground: Color(light: .hex(0xD6D0EA), dark: .hex(0x171121)),
            userBubble:           Color(light: .hex(0x2C2040), dark: .hex(0x31273F)),
            userBubbleText:       Color(light: .hex(0xF4F2F8), dark: .hex(0xC8BDE0)),
            assistantBubble:      Color(light: .hex(0xE2DDEF), dark: .hex(0x1E1828)),
            statusSuccess:        Color(light: .hex(0x4A8A6A), dark: .hex(0x6AAC88)),
            statusError:          Color(light: .hex(0xB85C50), dark: .hex(0xC47060)),
            statusWarning:        Color(light: .hex(0xC78A40), dark: .hex(0xD9A757)),
            inputBackground:      Color(light: .hex(0xF9F8FC), dark: .hex(0x1E1828)),
            inputBorder:          Color(light: .hex(0xC8C0E0), dark: .hex(0x352A48))
        )
    }()
}

extension ThemeColors {
    public static let amber: ThemeColors = {
        let accent: Color = Color(light: .hex(0xBF8A10), dark: .hex(0xE0AC30))
        return ThemeColors(
            accent:               accent,
            accentSubtle:         Color(light: .hex(0xBF8A10).opacity(0.12), dark: .hex(0xE0AC30).opacity(0.15)),
            background:           Color(light: .hex(0xF8F5EC), dark: .hex(0x1C1800)),
            surfacePrimary:       Color(light: .hex(0xF0EAD8), dark: .hex(0x261E04)),
            surfaceSecondary:     Color(light: .hex(0xE6E0C8), dark: .hex(0x30280A)),
            surfaceTertiary:      Color(light: .hex(0xDAD4B8), dark: .hex(0x3C3310)),
            surfaceElevated:      Color(light: .hex(0xFCFAF4), dark: .hex(0x2A2208)),
            sidebarBackground:    Color(light: .hex(0xEDE7D2), dark: .hex(0x151200)),
            sidebarItemHover:     Color(light: .hex(0xE2DBC6), dark: .hex(0x261E04)),
            sidebarItemSelected:  Color(light: .hex(0xBF8A10).opacity(0.12), dark: .hex(0xE0AC30).opacity(0.15)),
            textPrimary:          Color(light: .hex(0x3A2C06), dark: .hex(0xD4C47A)),
            textSecondary:        Color(light: .hex(0x7A6028), dark: .hex(0xA08840)),
            textTertiary:         Color(light: .hex(0xA89050), dark: .hex(0x756430)),
            border:               Color(light: .hex(0xD4CBA0), dark: .hex(0x3A2E10)),
            borderSubtle:         Color(light: .hex(0xE2DBC6), dark: .hex(0x30280A)),
            codeBackground:       Color(light: .hex(0xEAE3CC), dark: .hex(0x110E00)),
            codeHeaderBackground: Color(light: .hex(0xDED7C0), dark: .hex(0x1C1800)),
            userBubble:           Color(light: .hex(0x3A2C06), dark: .hex(0x3C3310)),
            userBubbleText:       Color(light: .hex(0xF8F5EC), dark: .hex(0xD4C47A)),
            assistantBubble:      Color(light: .hex(0xEAE3CC), dark: .hex(0x261E04)),
            statusSuccess:        Color(light: .hex(0x4A8A5E), dark: .hex(0x6AAC7C)),
            statusError:          Color(light: .hex(0xB85C50), dark: .hex(0xC47060)),
            statusWarning:        Color(light: .hex(0xBF8A10), dark: .hex(0xE0AC30)),
            inputBackground:      Color(light: .hex(0xFCFAF4), dark: .hex(0x261E04)),
            inputBorder:          Color(light: .hex(0xD4CBA0), dark: .hex(0x3A2E10))
        )
    }()
}

extension ThemeColors {
    public static let midnight: ThemeColors = {
        let accent: Color = Color(light: .hex(0x4A5CC7), dark: .hex(0x6B7FD4))
        return ThemeColors(
            accent:               accent,
            accentSubtle:         Color(light: .hex(0x4A5CC7).opacity(0.12), dark: .hex(0x6B7FD4).opacity(0.15)),
            background:           Color(light: .hex(0xF0F1F8), dark: .hex(0x0E0F1C)),
            surfacePrimary:       Color(light: .hex(0xE7E9F5), dark: .hex(0x151827)),
            surfaceSecondary:     Color(light: .hex(0xDCDFF0), dark: .hex(0x1C2033)),
            surfaceTertiary:      Color(light: .hex(0xD0D4EA), dark: .hex(0x232740)),
            surfaceElevated:      Color(light: .hex(0xF6F7FB), dark: .hex(0x191C30)),
            sidebarBackground:    Color(light: .hex(0xE3E5F2), dark: .hex(0x0A0B16)),
            sidebarItemHover:     Color(light: .hex(0xD8DBEE), dark: .hex(0x151827)),
            sidebarItemSelected:  Color(light: .hex(0x4A5CC7).opacity(0.12), dark: .hex(0x6B7FD4).opacity(0.15)),
            textPrimary:          Color(light: .hex(0x1A1E40), dark: .hex(0xBBC4E8)),
            textSecondary:        Color(light: .hex(0x4A5080), dark: .hex(0x6872A8)),
            textTertiary:         Color(light: .hex(0x7078A8), dark: .hex(0x4A5080)),
            border:               Color(light: .hex(0xC0C6E0), dark: .hex(0x272D48)),
            borderSubtle:         Color(light: .hex(0xD8DBEE), dark: .hex(0x1C2033)),
            codeBackground:       Color(light: .hex(0xDBDEF0), dark: .hex(0x09091A)),
            codeHeaderBackground: Color(light: .hex(0xCDD1EC), dark: .hex(0x0F1024)),
            userBubble:           Color(light: .hex(0x1A1E40), dark: .hex(0x232740)),
            userBubbleText:       Color(light: .hex(0xF0F1F8), dark: .hex(0xBBC4E8)),
            assistantBubble:      Color(light: .hex(0xDBDEF0), dark: .hex(0x151827)),
            statusSuccess:        Color(light: .hex(0x3A8A5E), dark: .hex(0x5AAC7A)),
            statusError:          Color(light: .hex(0xB85C50), dark: .hex(0xC47060)),
            statusWarning:        Color(light: .hex(0xC78A40), dark: .hex(0xD9A757)),
            inputBackground:      Color(light: .hex(0xF6F7FB), dark: .hex(0x151827)),
            inputBorder:          Color(light: .hex(0xC0C6E0), dark: .hex(0x272D48))
        )
    }()
}

// MARK: - Dark Themes (always dark regardless of system appearance)

extension ThemeColors {
    public static let dracula: ThemeColors = {
        let accent: Color = .hex(0xBD93F9)
        return ThemeColors(
            accent:               accent,
            accentSubtle:         .hex(0xBD93F9).opacity(0.18),
            background:           .hex(0x282A36),
            surfacePrimary:       .hex(0x2F3142),
            surfaceSecondary:     .hex(0x363848),
            surfaceTertiary:      .hex(0x44475A),
            surfaceElevated:      .hex(0x30323E),
            sidebarBackground:    .hex(0x21222C),
            sidebarItemHover:     .hex(0x2F3142),
            sidebarItemSelected:  .hex(0xBD93F9).opacity(0.18),
            textPrimary:          .hex(0xF8F8F2),
            textSecondary:        .hex(0xA0A0B8),
            textTertiary:         .hex(0x6272A4),
            border:               .hex(0x44475A),
            borderSubtle:         .hex(0x383A4A),
            codeBackground:       .hex(0x1E1F29),
            codeHeaderBackground: .hex(0x252631),
            userBubble:           .hex(0x44475A),
            userBubbleText:       .hex(0xF8F8F2),
            assistantBubble:      .hex(0x2F3142),
            statusSuccess:        .hex(0x50FA7B),
            statusError:          .hex(0xFF5555),
            statusWarning:        .hex(0xFFB86C),
            inputBackground:      .hex(0x21222C),
            inputBorder:          .hex(0x44475A)
        )
    }()
}

extension ThemeColors {
    public static let nord: ThemeColors = {
        let accent: Color = .hex(0x88C0D0)
        return ThemeColors(
            accent:               accent,
            accentSubtle:         .hex(0x88C0D0).opacity(0.18),
            background:           .hex(0x2E3440),
            surfacePrimary:       .hex(0x3B4252),
            surfaceSecondary:     .hex(0x434C5E),
            surfaceTertiary:      .hex(0x4C566A),
            surfaceElevated:      .hex(0x353B48),
            sidebarBackground:    .hex(0x252B37),
            sidebarItemHover:     .hex(0x3B4252),
            sidebarItemSelected:  .hex(0x88C0D0).opacity(0.18),
            textPrimary:          .hex(0xECEFF4),
            textSecondary:        .hex(0xC0C8DA),
            textTertiary:         .hex(0x8C99B3),
            border:               .hex(0x4C566A),
            borderSubtle:         .hex(0x434C5E),
            codeBackground:       .hex(0x232830),
            codeHeaderBackground: .hex(0x2B313E),
            userBubble:           .hex(0x4C566A),
            userBubbleText:       .hex(0xECEFF4),
            assistantBubble:      .hex(0x3B4252),
            statusSuccess:        .hex(0xA3BE8C),
            statusError:          .hex(0xBF616A),
            statusWarning:        .hex(0xEBCB8B),
            inputBackground:      .hex(0x252B37),
            inputBorder:          .hex(0x4C566A)
        )
    }()
}

extension ThemeColors {
    public static let monokai: ThemeColors = {
        let accent: Color = .hex(0x66D9E8)
        return ThemeColors(
            accent:               accent,
            accentSubtle:         .hex(0x66D9E8).opacity(0.15),
            background:           .hex(0x272822),
            surfacePrimary:       .hex(0x2F2F2A),
            surfaceSecondary:     .hex(0x383830),
            surfaceTertiary:      .hex(0x44443C),
            surfaceElevated:      .hex(0x2C2C27),
            sidebarBackground:    .hex(0x1E1E1A),
            sidebarItemHover:     .hex(0x2F2F2A),
            sidebarItemSelected:  .hex(0x66D9E8).opacity(0.15),
            textPrimary:          .hex(0xF8F8F2),
            textSecondary:        .hex(0xCFCFC2),
            textTertiary:         .hex(0x75715E),
            border:               .hex(0x49483E),
            borderSubtle:         .hex(0x383830),
            codeBackground:       .hex(0x1A1A17),
            codeHeaderBackground: .hex(0x212120),
            userBubble:           .hex(0x49483E),
            userBubbleText:       .hex(0xF8F8F2),
            assistantBubble:      .hex(0x2F2F2A),
            statusSuccess:        .hex(0xA6E22E),
            statusError:          .hex(0xF92672),
            statusWarning:        .hex(0xE6DB74),
            inputBackground:      .hex(0x1E1E1A),
            inputBorder:          .hex(0x49483E)
        )
    }()
}

extension ThemeColors {
    public static let oneDark: ThemeColors = {
        let accent: Color = .hex(0x61AFEF)
        return ThemeColors(
            accent:               accent,
            accentSubtle:         .hex(0x61AFEF).opacity(0.15),
            background:           .hex(0x282C34),
            surfacePrimary:       .hex(0x2C313C),
            surfaceSecondary:     .hex(0x323842),
            surfaceTertiary:      .hex(0x3A4050),
            surfaceElevated:      .hex(0x2F3340),
            sidebarBackground:    .hex(0x21252B),
            sidebarItemHover:     .hex(0x2C313C),
            sidebarItemSelected:  .hex(0x61AFEF).opacity(0.15),
            textPrimary:          .hex(0xABB2BF),
            textSecondary:        .hex(0x828997),
            textTertiary:         .hex(0x5C6370),
            border:               .hex(0x3E4451),
            borderSubtle:         .hex(0x323842),
            codeBackground:       .hex(0x1E2127),
            codeHeaderBackground: .hex(0x22262E),
            userBubble:           .hex(0x3A4050),
            userBubbleText:       .hex(0xABB2BF),
            assistantBubble:      .hex(0x2C313C),
            statusSuccess:        .hex(0x98C379),
            statusError:          .hex(0xE06C75),
            statusWarning:        .hex(0xE5C07B),
            inputBackground:      .hex(0x21252B),
            inputBorder:          .hex(0x3E4451)
        )
    }()
}

// MARK: - Extra Light Themes (always light regardless of system appearance)

extension ThemeColors {
    public static let rose: ThemeColors = {
        let accent: Color = .hex(0xD03A6A)
        return ThemeColors(
            accent:               accent,
            accentSubtle:         .hex(0xD03A6A).opacity(0.12),
            background:           .hex(0xFFF1F3),
            surfacePrimary:       .hex(0xFFE4E9),
            surfaceSecondary:     .hex(0xFFD5DC),
            surfaceTertiary:      .hex(0xFFC4CE),
            surfaceElevated:      .hex(0xFFF8F9),
            sidebarBackground:    .hex(0xFFEAEE),
            sidebarItemHover:     .hex(0xFFD5DC),
            sidebarItemSelected:  .hex(0xD03A6A).opacity(0.12),
            textPrimary:          .hex(0x2D0A13),
            textSecondary:        .hex(0x8C3050),
            textTertiary:         .hex(0xB07888),
            border:               .hex(0xF0B0BF),
            borderSubtle:         .hex(0xFFD5DC),
            codeBackground:       .hex(0xFFDAE1),
            codeHeaderBackground: .hex(0xFFCDD6),
            userBubble:           .hex(0x2D0A13),
            userBubbleText:       .hex(0xFFF1F3),
            assistantBubble:      .hex(0xFFDAE1),
            statusSuccess:        .hex(0x3A7D50),
            statusError:          .hex(0xC02040),
            statusWarning:        .hex(0xA06020),
            inputBackground:      .hex(0xFFF8F9),
            inputBorder:          .hex(0xF0B0BF)
        )
    }()
}

extension ThemeColors {
    public static let latte: ThemeColors = {
        let accent: Color = .hex(0x1E66F5)
        return ThemeColors(
            accent:               accent,
            accentSubtle:         .hex(0x1E66F5).opacity(0.12),
            background:           .hex(0xEFF1F5),
            surfacePrimary:       .hex(0xE6E9EF),
            surfaceSecondary:     .hex(0xDCE0E8),
            surfaceTertiary:      .hex(0xCCD0DA),
            surfaceElevated:      .hex(0xF5F6FA),
            sidebarBackground:    .hex(0xE8EAF0),
            sidebarItemHover:     .hex(0xDCE0E8),
            sidebarItemSelected:  .hex(0x1E66F5).opacity(0.12),
            textPrimary:          .hex(0x4C4F69),
            textSecondary:        .hex(0x6C6F85),
            textTertiary:         .hex(0x9CA0B0),
            border:               .hex(0xBCC0CC),
            borderSubtle:         .hex(0xDCE0E8),
            codeBackground:       .hex(0xE0E3EB),
            codeHeaderBackground: .hex(0xD5D9E5),
            userBubble:           .hex(0x4C4F69),
            userBubbleText:       .hex(0xEFF1F5),
            assistantBubble:      .hex(0xE0E3EB),
            statusSuccess:        .hex(0x40A02B),
            statusError:          .hex(0xD20F39),
            statusWarning:        .hex(0xDF8E1D),
            inputBackground:      .hex(0xF5F6FA),
            inputBorder:          .hex(0xBCC0CC)
        )
    }()
}

// MARK: - App Theme Enum

public enum AppTheme: String, CaseIterable, Identifiable {
    case claude   = "Terracotta"
    case ocean    = "Ocean"
    case forest   = "Forest"
    case lavender = "Lavender"
    case midnight = "Midnight"
    case amber    = "Amber"
    case dracula  = "Dracula"
    case nord     = "Nord"
    case monokai  = "Monokai"
    case oneDark  = "One Dark"
    case rose     = "Rose"
    case latte    = "Latte"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude:   "Terracotta (Default)"
        case .ocean:    "Ocean (Blue)"
        case .forest:   "Forest (Green)"
        case .lavender: "Lavender (Purple)"
        case .midnight: "Midnight (Indigo)"
        case .amber:    "Amber (Yellow)"
        case .dracula:  "Dracula (Dark)"
        case .nord:     "Nord (Dark)"
        case .monokai:  "Monokai (Dark)"
        case .oneDark:  "One Dark"
        case .rose:     "Rose (Light)"
        case .latte:    "Latte (Light)"
        }
    }

    public var colors: ThemeColors {
        switch self {
        case .claude:   .claude
        case .ocean:    .ocean
        case .forest:   .forest
        case .lavender: .lavender
        case .midnight: .midnight
        case .amber:    .amber
        case .dracula:  .dracula
        case .nord:     .nord
        case .monokai:  .monokai
        case .oneDark:  .oneDark
        case .rose:     .rose
        case .latte:    .latte
        }
    }
}

// MARK: - Theme Store

public extension Notification.Name {
    static let clarcThemeDidChange = Notification.Name("com.clarc.themeDidChange")
}

@MainActor
public final class ThemeStore {
    public static let shared = ThemeStore()
    private init() {}

    public var current: AppTheme = .claude {
        didSet {
            colors = current.colors
            NotificationCenter.default.post(name: .clarcThemeDidChange, object: nil)
        }
    }
    public var colors: ThemeColors = .claude

    public static let minFontSizeAdjustment: Int = -5
    public static let maxFontSizeAdjustment: Int = 8
    public var fontSizeAdjustment: Int = 0
    public var messageFontSizeAdjustment: Int = 0
}
