import Foundation

enum BadgeDisplayStyle: String, CaseIterable, Identifiable {
    case full
    case compact
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Complet"
        case .compact: return "Compact"
        case .minimal: return "Minimal"
        }
    }

    var subtitle: String {
        switch self {
        case .full: return "Pastille + logo + chiffre"
        case .compact: return "Pastille colorée avec le chiffre"
        case .minimal: return "Point de couleur + chiffre"
        }
    }
}

@MainActor
final class BadgeStyleStore: ObservableObject {
    @Published var style: BadgeDisplayStyle {
        didSet { defaults.set(style.rawValue, forKey: "menuBar.badgeStyle") }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = defaults.string(forKey: "menuBar.badgeStyle")
            .flatMap(BadgeDisplayStyle.init(rawValue:)) ?? .full
    }
}
