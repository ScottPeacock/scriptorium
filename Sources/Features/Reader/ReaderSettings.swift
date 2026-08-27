import Foundation

struct ReaderSettings: Codable, Sendable, Equatable {
    enum Theme: String, Codable, Sendable, CaseIterable, Identifiable {
        case light, sepia, dark
        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .light: "Light"
            case .sepia: "Sepia"
            case .dark: "Dark"
            }
        }
    }

    enum Flow: String, Codable, Sendable, CaseIterable, Identifiable {
        case paginated, scrolled
        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .paginated: "Pages"
            case .scrolled: "Scroll"
            }
        }
    }

    var theme: Theme = .light
    var flow: Flow = .paginated
    /// Percentage of the reader's default size.
    var fontSize: Int = 100
    var lineHeight: Double = 1.5
    var justify = true
    var hyphenate = true
    /// Page gap as a percentage of width.
    var margin: Int = 6
    var fontFamily: String?

    var payload: [String: Any] {
        var dictionary: [String: Any] = [
            "theme": theme.rawValue,
            "flow": flow.rawValue,
            "fontSize": fontSize,
            "lineHeight": lineHeight,
            "justify": justify,
            "hyphenate": hyphenate,
            "margin": margin
        ]
        if let fontFamily {
            dictionary["fontFamily"] = fontFamily
        }
        return dictionary
    }

    private static let storageKey = "readerSettings"

    static func load(from defaults: UserDefaults = .standard) -> ReaderSettings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ReaderSettings.self, from: data)
        else { return ReaderSettings() }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

struct TOCEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    let label: String
    let href: String
    let depth: Int
}

/// A position in the book, as foliate-js reports it.
struct ReaderLocation: Sendable, Equatable {
    /// An EPUB CFI — the value Grimmory stores as `positionData`.
    let cfi: String?
    /// Spine href, stored as `positionHref`.
    let href: String?
    let fraction: Double?
    let tocLabel: String?
    let sectionCurrent: Int?
    let sectionTotal: Int?
}
