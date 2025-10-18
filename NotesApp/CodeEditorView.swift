import SwiftUI
import UIKit
import Foundation

struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String
    @Binding var breakpoints: [Int: String]
    @Binding var navigateToLine: Int?
    var fontSize: CGFloat
    var isDark: Bool
    var theme: SyntaxHighlighter.Theme
    var onEditCondition: ((Int) -> Void)? = nil

    func makeUIView(context: Context) -> CodeEditorContainer {
        let v = CodeEditorContainer()
        AppLogger.log("CodeEditor.makeUIView")
        v.configure(fontSize: fontSize, isDark: isDark, theme: theme)
        v.setText(text)
        v.setBreakpoints(breakpoints)
        v.onTextChanged = { newText in
            AppLogger.log("Editor text changed, length: \(newText.count)")
            if newText != text { self.text = newText }
        }
        v.onBreakpointsChanged = { newBP in
            AppLogger.log("Breakpoints changed, count: \(newBP.count)")
            if newBP != breakpoints { self.breakpoints = newBP }
        }
        v.onRequestEditCondition = onEditCondition
        return v
    }

    func updateUIView(_ uiView: CodeEditorContainer, context: Context) {
        AppLogger.log("CodeEditor.updateUIView (fontSize=\(fontSize), dark=\(isDark))")
        uiView.configure(fontSize: fontSize, isDark: isDark, theme: theme)
        if uiView.text != text { uiView.setText(text) }
        uiView.setBreakpoints(breakpoints)
        if let line = navigateToLine {
            AppLogger.log("Navigate requested to line: \(line)")
            uiView.goTo(line: line)
            DispatchQueue.main.async { self.navigateToLine = nil }
        }
        uiView.onRequestEditCondition = onEditCondition
    }
}

final class CodeEditorContainer: UIView, UITextViewDelegate {
    private let textView = UITextView()
    private let gutter = LineNumberView()
    private let highlighter = SyntaxHighlighter()
    private var font: UIFont = CodeEditorContainer.fixedMonospaceFont(ofSize: 15)
    private var dark = false
    private var theme: SyntaxHighlighter.Theme = .defaultLight()
    private var breakpoints: [Int: String] = [:]
    private var currentLine: Int = 1

    var onTextChanged: ((String) -> Void)?
    var onBreakpointsChanged: (([Int: String]) -> Void)?
    var onRequestEditCondition: ((Int) -> Void)?

    var text: String { textView.text ?? "" }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        textView.delegate = self
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.textDragInteraction?.isEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        addSubview(textView)
        addSubview(gutter)

        // Sync scrolling
        textView.addObserver(self, forKeyPath: #keyPath(UITextView.contentOffset), options: [.new, .initial], context: nil)

        // Tap to toggle breakpoints
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleGutterTap(_:)))
        gutter.addGestureRecognizer(tap)
        gutter.isUserInteractionEnabled = true
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleGutterLongPress(_:)))
        gutter.addGestureRecognizer(longPress)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { textView.removeObserver(self, forKeyPath: #keyPath(UITextView.contentOffset)) }

    func configure(fontSize: CGFloat, isDark: Bool, theme: SyntaxHighlighter.Theme) {
        dark = isDark
        self.theme = theme
        font = CodeEditorContainer.fixedMonospaceFont(ofSize: fontSize)
        textView.font = font
        backgroundColor = isDark ? UIColor.black : UIColor.systemBackground
        gutter.backgroundColor = isDark ? UIColor(white: 0.1, alpha: 1) : UIColor.secondarySystemBackground
        gutter.textColor = isDark ? UIColor(white: 0.8, alpha: 1) : UIColor.systemGray
        gutter.lineHeight = font.lineHeight
        gutter.textView = textView
        updateCurrentLine()
        applyHighlighting()
        setNeedsLayout()
    }

    // Prefer a non-variable monospace font to avoid CoreText variable font crashes on some iOS versions
    static func fixedMonospaceFont(ofSize size: CGFloat) -> UIFont {
        if let menlo = UIFont(name: "Menlo-Regular", size: size) { return menlo }
        if let menloAlt = UIFont(name: "Menlo", size: size) { return menloAlt }
        if let courier = UIFont(name: "CourierNewPSMT", size: size) { return courier }
        return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gutterWidth: CGFloat = 44
        gutter.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        textView.frame = CGRect(x: gutterWidth, y: 0, width: bounds.width - gutterWidth, height: bounds.height)
        // Add left inset padding so text doesn't overlap gutter line
        textView.textContainerInset.left = 8
    }

    func setText(_ t: String) {
        if textView.text == t { return }
        textView.text = t
        AppLogger.log("setText called, new length: \((t as NSString).length)")
        updateCurrentLine()
        applyHighlighting()
        gutter.setNeedsDisplay()
    }

    func setBreakpoints(_ bp: [Int: String]) {
        if bp == breakpoints { return }
        breakpoints = bp
        AppLogger.log("setBreakpoints called, count: \(bp.count)")
        gutter.breakpoints = breakpoints
        gutter.setNeedsDisplay()
    }

    func textViewDidChange(_ textView: UITextView) {
        AppLogger.log("textViewDidChange, length: \(textView.text.count)")
        onTextChanged?(textView.text)
        updateCurrentLine()
        applyHighlighting()
        gutter.setNeedsDisplay()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        AppLogger.log("selection changed, currentLine before update: \(currentLine)")
        updateCurrentLine()
        AppLogger.log("selection changed, currentLine after update: \(currentLine)")
        applyHighlighting()
        gutter.setNeedsDisplay()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(UITextView.contentOffset) {
            gutter.contentOffset = textView.contentOffset
            gutter.setNeedsDisplay()
        }
    }

    private func applyHighlighting() {
        highlighter.highlight(textView: textView, theme: theme, font: font)
        // Add current-line background highlight
        guard let text = textView.text else { return }
        let ns = text as NSString
        let length = ns.length
        let caret = min(textView.selectedRange.location, length)
        let start = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: caret)).location
        let lineStart = (start == NSNotFound) ? 0 : (start + 1)
        let nextRangeStart = (caret < length) ? caret : (length - 1)
        let endSearchRange = NSRange(location: max(0, nextRangeStart), length: length - max(0, nextRangeStart))
        let next = ns.range(of: "\n", options: [], range: endSearchRange).location
        let lineEnd = (next == NSNotFound) ? length : next
        if lineEnd >= lineStart && lineStart <= length {
            let bgRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            let bg = (dark ? UIColor.systemBlue.withAlphaComponent(0.18) : UIColor.systemBlue.withAlphaComponent(0.12))
            let mut = NSMutableAttributedString(attributedString: textView.attributedText)
            mut.addAttribute(.backgroundColor, value: bg, range: bgRange)
            let sel = textView.selectedRange
            textView.attributedText = mut
            textView.selectedRange = sel
        }
        gutter.currentLine = currentLine
        gutter.breakpoints = breakpoints
    }

    private func updateCurrentLine() {
        guard let text = textView.text else { currentLine = 1; return }
        let caret = min(textView.selectedRange.location, (text as NSString).length)
        if caret <= 0 { currentLine = 1; return }
        let prefix = (text as NSString).substring(to: caret)
        currentLine = prefix.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) } + 1
    }

    @objc private func handleGutterTap(_ gr: UITapGestureRecognizer) {
        let point = gr.location(in: gutter)
        let insetTop = textView.textContainerInset.top
        let line = max(1, Int(floor((point.y + contentOffsetY() + insetTop) / max(1, gutter.lineHeight))) + 1)
        toggleBreakpoint(line)
    }

    private func contentOffsetY() -> CGFloat { textView.contentOffset.y }

    private func toggleBreakpoint(_ line: Int) {
        if breakpoints[line] != nil {
            breakpoints.removeValue(forKey: line)
            AppLogger.log("Breakpoint removed at line \(line)")
        } else {
            breakpoints[line] = ""
            AppLogger.log("Breakpoint added at line \(line)")
        }
        gutter.breakpoints = breakpoints
        gutter.setNeedsDisplay()
        onBreakpointsChanged?(breakpoints)
    }

    @objc private func handleGutterLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began else { return }
        let point = gr.location(in: gutter)
        let insetTop = textView.textContainerInset.top
        let line = max(1, Int(floor((point.y + contentOffsetY() + insetTop) / max(1, gutter.lineHeight))) + 1)
        onRequestEditCondition?(line)
    }

    func goTo(line: Int) {
        guard let text = textView.text, line > 0 else { return }
        AppLogger.log("goTo(line:) called with line=\(line)")
        let ns = text as NSString
        let total = ns.length
        var targetIndex = 0
        var current = 1
        if line == 1 { targetIndex = 0 }
        else {
            ns.enumerateSubstrings(in: NSRange(location: 0, length: total), options: [.byComposedCharacterSequences]) { _, substrRange, _, stop in
                if ns.substring(with: substrRange) == "\n" { current += 1; if current == line { targetIndex = substrRange.location + substrRange.length; stop.pointee = true } }
            }
        }
        targetIndex = min(targetIndex, total)
        let range = NSRange(location: targetIndex, length: 0)
        textView.selectedRange = range
        textView.scrollRangeToVisible(range)
        updateCurrentLine()
        applyHighlighting()
        gutter.setNeedsDisplay()
    }
}

final class LineNumberView: UIView {
    weak var textView: UITextView?
    var textColor: UIColor = .systemGray
    var lineHeight: CGFloat = 16
    var contentOffset: CGPoint = .zero
    var currentLine: Int = 1
    var breakpoints: [Int: String] = [:]

    override func draw(_ rect: CGRect) {
        guard let tv = textView else { return }
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setFillColor((backgroundColor ?? .clear).cgColor)
        ctx?.fill(rect)

        // Vertical separator
        let sepX = rect.maxX - 1
        ctx?.setFillColor(UIColor.separator.cgColor)
        ctx?.fill(CGRect(x: sepX, y: rect.minY, width: 1, height: rect.height))

        // Compute logical line numbers (based on \n)
        let text = tv.text ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count

        // Estimate first visible line by contentOffset
        let insetTop = tv.textContainerInset.top
        let firstVisible = max(0, Int(floor((contentOffset.y + insetTop) / max(1, lineHeight))))
        let visibleCount = Int(ceil(rect.height / max(1, lineHeight))) + 2

        let attrs: [NSAttributedString.Key: Any] = [
            .font: tv.font ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: textColor
        ]
        let start = firstVisible + 1
        let end = min(lines, firstVisible + visibleCount)
        for i in start...max(start, end) {
            let y = insetTop - contentOffset.y + CGFloat(i - 1) * lineHeight
            // Current-line highlight band in gutter
            if i == currentLine {
                let hl = UIBezierPath(roundedRect: CGRect(x: rect.minX + 2, y: y + 2, width: rect.width - 6, height: lineHeight - 4), cornerRadius: 4)
                (UIColor.systemBlue.withAlphaComponent(0.12)).setFill()
                hl.fill()
            }
            // Breakpoint dot
            if let cond = breakpoints[i] {
                let dotRect = CGRect(x: rect.minX + 8, y: y + (lineHeight - 10) / 2, width: 10, height: 10)
                let dot = UIBezierPath(ovalIn: dotRect)
                let color: UIColor = (cond.isEmpty ? UIColor.systemRed : UIColor.systemOrange)
                color.setFill()
                dot.fill()
            }
            let s = "\(i)" as NSString
            let size = s.size(withAttributes: attrs)
            let r = CGRect(x: rect.maxX - 6 - size.width, y: y + (lineHeight - size.height) / 2, width: size.width, height: size.height)
            s.draw(in: r, withAttributes: attrs)
        }
    }
}
