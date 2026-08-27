import SwiftUI

/// Whether the app follows the system, or is pinned light or dark.
///
/// Reading apps need this independently of the system setting: people read in
/// bed with the phone otherwise in light mode, and vice versa. The reader has
/// its own page theme (light/sepia/dark) — this is the surrounding chrome.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil hands control back to the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
