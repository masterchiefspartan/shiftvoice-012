import SwiftUI

enum SVTheme {
    static let background = Color(.systemBackground)
    static let surface = Color(.secondarySystemBackground)
    static let surfaceSecondary = Color(.tertiarySystemBackground)
    static let surfaceBorder = Color(.separator)
    static let divider = Color(.separator)

    static let cardBackground = Color(.secondarySystemBackground)
    static let cardBackgroundElevated = Color(.tertiarySystemBackground)

    static let accent = Color(red: 29/255, green: 78/255, blue: 216/255)
    static let accentGreen = Color(red: 22/255, green: 163/255, blue: 74/255)

    static let urgentRed = Color(red: 220/255, green: 38/255, blue: 38/255)
    static let amber = Color(red: 217/255, green: 119/255, blue: 6/255)
    static let infoBlue = Color(red: 37/255, green: 99/255, blue: 235/255)
    static let mutedGray = Color(.secondaryLabel)
    static let successGreen = Color(red: 22/255, green: 163/255, blue: 74/255)

    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    static let darkSurface = Color(red: 24/255, green: 24/255, blue: 27/255)

    static let iconBackground = Color(.tertiarySystemFill)

    static func urgencyColor(_ urgency: UrgencyLevel) -> Color {
        switch urgency {
        case .immediate: return urgentRed
        case .nextShift: return amber
        case .thisWeek: return infoBlue
        case .fyi: return mutedGray
        }
    }

    static func categoryColor(_ category: NoteCategory) -> Color {
        switch category {
        case .eightySixed: return urgentRed
        case .equipment: return amber
        case .guestIssue: return Color(red: 190/255, green: 24/255, blue: 93/255)
        case .staffNote: return infoBlue
        case .reservation: return Color(red: 124/255, green: 58/255, blue: 237/255)
        case .inventory: return amber
        case .maintenance: return Color(red: 234/255, green: 88/255, blue: 12/255)
        case .healthSafety: return urgentRed
        case .general: return mutedGray
        case .incident: return urgentRed
        }
    }

    static func color(fromHex hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
