import Foundation

/// Grimmory stores book descriptions as HTML — metadata providers supply it
/// that way, and the web reader renders it in a browser. Rendering it as plain
/// text puts literal `<b>` and `&#160;` in front of the reader, so strip it
/// down to something a Text view can show.
enum HTMLText {
    /// Converts a fragment of HTML into readable plain text.
    static func plain(from html: String) -> String {
        guard !html.isEmpty else { return "" }

        var text = html

        // Block-level breaks become newlines before tags are stripped, so
        // paragraphs don't run together into a wall of text.
        for pattern in ["<br\\s*/?>", "</p\\s*>", "</div\\s*>", "</li\\s*>", "</h[1-6]\\s*>"] {
            text = text.replacingOccurrences(
                of: pattern,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        text = text.replacingOccurrences(
            of: "<li\\s*[^>]*>",
            with: "\n• ",
            options: [.regularExpression, .caseInsensitive]
        )

        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(in: text)

        // Collapse the runs of blank lines the tag stripping leaves behind.
        text = text.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let named: [String: String] = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
        "&apos;": "'", "&nbsp;": "\u{00A0}", "&hellip;": "…",
        "&mdash;": "—", "&ndash;": "–", "&bull;": "•",
        "&lsquo;": "'", "&rsquo;": "'", "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}"
    ]

    private static func decodeEntities(in text: String) -> String {
        var result = text
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        // Numeric entities: &#160; and &#x00A0;
        for pattern in ["&#([0-9]+);", "&#[xX]([0-9A-Fa-f]+);"] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let radix = pattern.contains("x") ? 16 : 10
            var output = ""
            var last = result.startIndex
            let full = NSRange(result.startIndex ..< result.endIndex, in: result)

            for match in regex.matches(in: result, range: full) {
                guard let range = Range(match.range, in: result),
                      let digits = Range(match.range(at: 1), in: result),
                      let value = UInt32(result[digits], radix: radix),
                      let scalar = Unicode.Scalar(value)
                else { continue }
                output += result[last ..< range.lowerBound] + String(Character(scalar))
                last = range.upperBound
            }
            output += result[last...]
            result = output
        }
        // &amp; last would double-decode; it ran first, which is correct for
        // input that was escaped once.
        return result
    }
}
