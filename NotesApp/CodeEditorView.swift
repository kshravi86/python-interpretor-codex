import SwiftUI
import UIKit

struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var isDark: Bool

    func makeUIView(context: Context) -> CodeEditorContainer {
        let v = CodeEditorContainer()
        v.configure(fontSize: fontSize, isDark: isDark)
        v.setText(text)
        v.onTextChanged = { newText in
            if newText != text { self.text = newText }
        }
        return v
    }

    func updateUIView(_ uiView: CodeEditorContainer, context: Context) {
        uiView.configure(fontSize: fontSize, isDark: isDark)
        if uiView.text != text { uiView.setText(text) }
    }
}

final class CodeEditorContainer: UIView, UITextViewDelegate {
    private let textView = UITextView()
    private let gutter = LineNumberView()
    private let highlighter = SyntaxHighlighter()
    private var font: UIFont = .monospacedSystemFont(ofSize: 15, weight: .regular)
    private var dark = false

    var onTextChanged: ((String) -> Void)?

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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { textView.removeObserver(self, forKeyPath: #keyPath(UITextView.contentOffset)) }

    func configure(fontSize: CGFloat, isDark: Bool) {
        dark = isDark
        font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = font
        backgroundColor = isDark ? UIColor.black : UIColor.systemBackground
        gutter.backgroundColor = isDark ? UIColor(white: 0.1, alpha: 1) : UIColor.secondarySystemBackground
        gutter.textColor = isDark ? UIColor(white: 0.8, alpha: 1) : UIColor.systemGray
        gutter.lineHeight = font.lineHeight
        gutter.textView = textView
        applyHighlighting()
        setNeedsLayout()
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
        applyHighlighting()
        gutter.setNeedsDisplay()
    }

    func textViewDidChange(_ textView: UITextView) {
        onTextChanged?(textView.text)
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
        let theme = SyntaxHighlighter.Theme.system(dark: dark)
        highlighter.highlight(textView: textView, theme: theme, font: font)
    }
}

final class LineNumberView: UIView {
    weak var textView: UITextView?
    var textColor: UIColor = .systemGray
    var lineHeight: CGFloat = 16
    var contentOffset: CGPoint = .zero

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
            let s = "\(i)" as NSString
            let size = s.size(withAttributes: attrs)
            let r = CGRect(x: rect.maxX - 6 - size.width, y: y + (lineHeight - size.height) / 2, width: size.width, height: size.height)
            s.draw(in: r, withAttributes: attrs)
        }
    }
}

