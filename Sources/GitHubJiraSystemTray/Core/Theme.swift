import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case white
    case black
    case blue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: return "Blanc"
        case .black: return "Noir"
        case .blue: return "Bleu"
        }
    }

    var subtitle: String {
        switch self {
        case .white: return "Clair et neutre"
        case .black: return "Sombre et discret"
        case .blue: return "Le thème actuel"
        }
    }

    var colorScheme: ColorScheme {
        self == .white ? .light : .dark
    }

    var accent: Color {
        switch self {
        case .white: return Color(red: 0.12, green: 0.34, blue: 0.78)
        case .black: return Color(red: 0.35, green: 0.60, blue: 1)
        case .blue: return Color(red: 0.28, green: 0.68, blue: 1)
        }
    }

    /// Indigo used by the reviewer chip/badge, tuned so it stays legible on every theme.
    var reviewerAccent: Color {
        switch self {
        case .white: return Color(red: 0.27, green: 0.29, blue: 0.72)
        case .black, .blue: return Color(red: 0.56, green: 0.60, blue: 1)
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .white:
            return [Color(red: 0.96, green: 0.97, blue: 0.99), Color(red: 0.87, green: 0.90, blue: 0.95)]
        case .black:
            return [Color.black, Color(red: 0.045, green: 0.045, blue: 0.05)]
        case .blue:
            return [Color(red: 0.035, green: 0.085, blue: 0.14), Color(red: 0.025, green: 0.055, blue: 0.09)]
        }
    }

    var selectionGradient: LinearGradient {
        let colors: [Color]
        if self == .white {
            colors = [Color(red: 0.22, green: 0.55, blue: 0.96), Color(red: 0.14, green: 0.43, blue: 0.86)]
        } else {
            colors = [Color(red: 0.06, green: 0.40, blue: 0.95), Color(red: 0.08, green: 0.27, blue: 0.71)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    @Published var selection: AppTheme {
        didSet {
            guard !isOverridden else { return }
            UserDefaults.standard.set(selection.rawValue, forKey: "appearance.theme")
        }
    }

    private let isOverridden: Bool

    init() {
        let override = ProcessInfo.processInfo.environment["JIRA_TRACKER_THEME"]
        isOverridden = override != nil
        let stored = UserDefaults.standard.string(forKey: "appearance.theme")
        selection = AppTheme(rawValue: override ?? stored ?? "blue") ?? .blue
    }
}
