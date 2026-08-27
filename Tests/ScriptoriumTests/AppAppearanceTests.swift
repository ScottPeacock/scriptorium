import Foundation
@testable import Scriptorium
import SwiftUI
import Testing

@Suite("App appearance")
struct AppAppearanceTests {
    @Test("System hands control back to iOS rather than forcing a scheme")
    func systemIsUnset() {
        #expect(AppAppearance.system.colorScheme == nil)
    }

    @Test("Light and dark override the system")
    func overrides() {
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test("Raw values are stable — they're persisted in UserDefaults")
    func stableRawValues() {
        #expect(AppAppearance.system.rawValue == "system")
        #expect(AppAppearance.light.rawValue == "light")
        #expect(AppAppearance.dark.rawValue == "dark")
        #expect(AppAppearance(rawValue: "dark") == .dark)
    }

    @Test("Every case is offered in the picker")
    func allCases() {
        #expect(AppAppearance.allCases.count == 3)
        #expect(AppAppearance.allCases.allSatisfy { !$0.label.isEmpty })
    }
}
