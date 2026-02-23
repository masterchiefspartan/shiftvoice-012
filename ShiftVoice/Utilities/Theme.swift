import SwiftUI

enum SVTheme {
    static let background = Color(red: 250/255, green: 250/255, blue: 248/255)
    static let surface = Color.white
    static let surfaceSecondary = Color(red: 245/255, green: 244/255, blue: 240/255)
    static let surfaceBorder = Color(red: 232/255, green: 230/255, blue: 225/255)
    static let divider = Color(red: 235/255, green: 235/255, blue: 235/255)

    static let cardBackground = Color.white
    static let cardBackgroundElevated = Color(red: 245/255, green: 244/255, blue: 240/255)

    static let accent = Color(red: 29/255, green: 78/255, blue: 216/255)
    static let accentGreen = Color(red: 22/255, green: 163/255, blue: 74/255)

    static let urgentRed = Color(red: 220/255, green: 38/255, blue: 38/255)
    static let amber = Color(red: 217/255, green: 119/255, blue: 6/255)
    static let infoBlue = Color(red: 37/255, green: 99/255, blue: 235/255)
    static let mutedGray = Color(red: 156/255, green: 163/255, blue: 175/255)
    static let successGreen = Color(red: 22/255, green: 163/255, blue: 74/255)

    static let textPrimary = Color(red: 26/255, green: 26/255, blue: 26/255)
    static let textSecondary = Color(red: 107/255, green: 105/255, blue: 102/255)
    static let textTertiary = Color(red: 168/255, green: 165/255, blue: 160/255)

    static let darkSurface = Color(red: 24/255, green: 24/255, blue: 27/255)

    static let iconBackground = Color(red: 240/255, green: 238/255, blue: 233/255)

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
