import Cocoa

class AIPanel: NSPanel {
    private var input: NSTextField!
    private var output: NSTextView!

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Kiro AI"
        titlebarAppearsTransparent = true
        backgroundColor = Theme.offWhite
        setupUI()
    }

    private func setupUI() {
        input = NSTextField(frame: NSRect(x: 10, y: 260, width: 300, height: 24))
        input.placeholderString = "Ask Kiro..."
        input.target = self
        input.action = #selector(send)
        contentView?.addSubview(input)

        let sendBtn = NSButton(frame: NSRect(x: 320, y: 260, width: 70, height: 24))
        sendBtn.title = "Send"
        sendBtn.bezelStyle = .rounded
        sendBtn.target = self
        sendBtn.action = #selector(send)
        contentView?.addSubview(sendBtn)

        let scroll = NSScrollView(frame: NSRect(x: 10, y: 10, width: 380, height: 240))
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.backgroundColor = Theme.offWhite

        output = NSTextView(frame: scroll.bounds)
        output.isEditable = false
        output.font = Theme.monoFont
        output.backgroundColor = Theme.offWhite
        output.textColor = Theme.offBlack
        scroll.documentView = output
        contentView?.addSubview(scroll)
    }

    @objc private func send() {
        let prompt = input.stringValue
        guard !prompt.isEmpty else { return }
        output.string = "Thinking..."
        input.stringValue = ""

        DispatchQueue.global().async {
            var response = "Error: No response"
            if let cPrompt = prompt.cString(using: .utf8),
               let result = kiro_chat(cPrompt) {
                response = String(cString: result)
                free_string(result)
            }
            DispatchQueue.main.async {
                self.output.string = response
            }
        }
    }
}
