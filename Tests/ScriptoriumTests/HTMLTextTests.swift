import Foundation
@testable import Scriptorium
import Testing

/// Grimmory stores descriptions as HTML — metadata providers supply it that way.
/// Rendering it raw put literal `<b>` and `&#160;` in front of the reader.
@Suite("HTML descriptions")
struct HTMLTextTests {
    @Test("Tags are stripped")
    func stripsTags() {
        #expect(HTMLText.plain(from: "<b>Bold</b> and <i>italic</i>") == "Bold and italic")
    }

    @Test("Line breaks become newlines rather than vanishing")
    func lineBreaks() {
        #expect(HTMLText.plain(from: "One<br>Two") == "One\nTwo")
        #expect(HTMLText.plain(from: "<p>One</p><p>Two</p>") == "One\nTwo")
    }

    @Test("Numeric entities decode — &#160; was showing up literally")
    func numericEntities() {
        #expect(HTMLText.plain(from: "presents&#160;the insights") == "presents\u{00A0}the insights")
    }

    @Test("Hex entities decode")
    func hexEntities() {
        #expect(HTMLText.plain(from: "a&#x2014;b") == "a—b")
    }

    @Test("Named entities decode")
    func namedEntities() {
        #expect(HTMLText.plain(from: "Tom &amp; Jerry") == "Tom & Jerry")
        #expect(HTMLText.plain(from: "&bull; point") == "• point")
    }

    @Test("List items become bullets")
    func listItems() {
        let result = HTMLText.plain(from: "<ul><li>One</li><li>Two</li></ul>")
        #expect(result.contains("• One"))
        #expect(result.contains("• Two"))
    }

    @Test("Runs of blank lines collapse")
    func collapsesBlankLines() {
        #expect(HTMLText.plain(from: "One<br><br><br><br>Two") == "One\n\nTwo")
    }

    @Test("Plain text passes through untouched")
    func plainPassthrough() {
        #expect(HTMLText.plain(from: "Just a sentence.") == "Just a sentence.")
    }

    @Test("Empty input stays empty")
    func empty() {
        #expect(HTMLText.plain(from: "") == "")
    }

    @Test("A real Grimmory description reads as prose")
    func realDescription() {
        let raw = "<b>Build a meaningful life</b><br>Are you caught&#160;in the trap? " +
            "<br>&bull;&#160;Reduce stress and worry"
        let result = HTMLText.plain(from: raw)
        #expect(!result.contains("<"))
        #expect(!result.contains("&#"))
        #expect(result.hasPrefix("Build a meaningful life"))
    }
}
