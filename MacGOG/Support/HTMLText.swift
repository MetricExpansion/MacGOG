import Foundation

/// Turns GOG's store description HTML into plain paragraphs. AppKit's HTML import would load remote
/// images through WebKit, so this strips tags instead.
nonisolated enum HTMLText {
    static func plainText(_ html: String) -> String {
        // HTML treats runs of whitespace, newlines included, as one space; only tags break lines.
        var text = html.replacingOccurrences(of: #"[\s\x{A0}]+"#, with: " ", options: .regularExpression)
        let rules = [
            (#"(?is)<(script|style)[^>]*>.*?</\1>"#, ""),
            (#"(?i)<br\s*/?>"#, "\n"),
            (#"(?i)</(p|div|h[1-6]|ul|ol)>"#, "\n\n"),
            (#"(?i)<li[^>]*>"#, "• "),
            (#"(?i)</li>"#, "\n"),
            (#"<[^>]+>"#, ""),
        ]
        for (pattern, replacement) in rules {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        let entities = [
            ("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"),
            ("&gt;", ">"), ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…"), ("&trade;", "™"),
            ("&reg;", "®"), ("&copy;", "©"), ("&amp;", "&"),
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacingOccurrences(
            of: #"[ \t\x{A0}]*\n[ \t\x{A0}]*"#,
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
