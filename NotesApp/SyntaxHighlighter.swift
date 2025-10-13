import UIKit

final class SyntaxHighlighter {
    struct Theme {
        let base: UIColor
        let keyword: UIColor
        let string: UIColor
        let comment: UIColor
        let number: UIColor

        static func system(dark: Bool) -> Theme { dark ? defaultDark() : defaultLight() }

        static func defaultLight() -> Theme {
            Theme(
                base: UIColor.label,
                keyword: UIColor.systemPurple,
                string: UIColor.systemGreen,
                comment: UIColor.systemGray,
                number: UIColor.systemOrange
            )
        }

        static func defaultDark() -> Theme {
            Theme(
                base: UIColor.white,
                keyword: UIColor.systemPink,
                string: UIColor.systemGreen,
                comment: UIColor.systemGray3,
                number: UIColor.systemYellow
            )
        }
    }

    private let keywords: Set<String> = [
        "def","class","for","in","while","if","elif","else","try","except","finally",
        "import","from","as","return","pass","break","continue","lambda","with","yield",
        "assert","del","global","nonlocal","raise","True","False","None","and","or","not","is"
    ]

    func highlight(textView: UITextView, theme: Theme, font: UIFont) {
        guard let text = textView.text else { return }
        let attr = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        attr.addAttributes([
            .font: font,
            .foregroundColor: theme.base
        ], range: fullRange)

        let ns = text as NSString

        // Comments: # ... end of line
        if let regex = try? NSRegularExpression(pattern: "#.*", options: []) {
            regex.enumerateMatches(in: text, options: [], range: fullRange) { m, _, _ in
                if let r = m?.range { attr.addAttribute(.foregroundColor, value: theme.comment, range: r) }
            }
        }

        // Triple-quoted strings: """...""" and '''...''' (match across newlines)
        if let tripleDQ = try? NSRegularExpression(pattern: #""""""[\s\S]*?""""""# , options: []) {
            tripleDQ.enumerateMatches(in: text, options: [], range: fullRange) { m, _, _ in
                if let r = m?.range { attr.addAttribute(.foregroundColor, value: theme.string, range: r) }
            }
        }
        if let tripleSQ = try? NSRegularExpression(pattern: #"'''[\s\S]*?'''"#, options: []) {
            tripleSQ.enumerateMatches(in: text, options: [], range: fullRange) { m, _, _ in
                if let r = m?.range { attr.addAttribute(.foregroundColor, value: theme.string, range: r) }
            }
        }

        // Single/double quoted strings
        if let str = try? NSRegularExpression(pattern: #"("[^"]*"|'[^']*')"#, options: []) {
            str.enumerateMatches(in: text, options: [], range: fullRange) { m, _, _ in
                if let r = m?.range { attr.addAttribute(.foregroundColor, value: theme.string, range: r) }
            }
        }

        // Numbers
        if let nums = try? NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\b"#, options: []) {
            nums.enumerateMatches(in: text, options: [], range: fullRange) { m, _, _ in
                if let r = m?.range { attr.addAttribute(.foregroundColor, value: theme.number, range: r) }
            }
        }

        // Keywords (basic word boundary scan)
        ns.enumerateSubstrings(in: fullRange, options: .byWords) { (substr, substrRange, _, _) in
            if let s = substr, self.keywords.contains(s) {
                attr.addAttribute(.foregroundColor, value: theme.keyword, range: substrRange)
            }
        }

        let selected = textView.selectedRange
        textView.attributedText = attr
        textView.selectedRange = selected
    }
}

