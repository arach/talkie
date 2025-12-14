//
//  TerminalView.swift
//  Talkie
//
//  Embedded terminal for power users - access your memos with Unix tools
//  Uses xterm.js for GPU-accelerated rendering via WKWebView
//

import SwiftUI
import AppKit
import WebKit
import Darwin

// MARK: - Terminal Controller

@MainActor
final class TerminalController: ObservableObject {
    static let shared = TerminalController()

    private var window: NSWindow?
    @Published var isVisible = false

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if window == nil {
            createWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func hide() {
        window?.orderOut(nil)
        isVisible = false
    }

    private func createWindow() {
        let contentView = TerminalContentView()
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "Talkie Shell"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = WindowDelegate(controller: self)

        self.window = window
    }

    private class WindowDelegate: NSObject, NSWindowDelegate {
        weak var controller: TerminalController?

        init(controller: TerminalController) {
            self.controller = controller
        }

        func windowWillClose(_ notification: Notification) {
            Task { @MainActor in
                self.controller?.isVisible = false
            }
        }
    }
}

// MARK: - Terminal Content View

struct TerminalContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TALKIE SHELL")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Text(dataDirectory)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))

            Divider()

            // xterm.js terminal
            XTermView()
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
    }

    private var dataDirectory: String {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("Talkie").path
        }
        return "~/Library/Application Support/Talkie"
    }
}

// MARK: - Terminal Bootstrap

private enum TalkieTerminalBootstrap {
    static func prepare() -> (env: [String: String], args: [String]) {
        let fm = FileManager.default

        // Base app support: sandbox-safe
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let talkieSupport = (appSupport?.appendingPathComponent("Talkie") ?? URL(fileURLWithPath: NSHomeDirectory()))

        // Terminal-owned HOME/ZDOTDIR to avoid picking up the user's personal dotfiles
        let terminalHome = talkieSupport
            .appendingPathComponent("terminal", isDirectory: true)
            .appendingPathComponent("home", isDirectory: true)

        // Preferred user-visible dirs (may require permissions if sandboxed)
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let preferredPlay = userHome.appendingPathComponent("talkie-play", isDirectory: true)
        let preferredCopy = userHome.appendingPathComponent("talkie-copy", isDirectory: true)

        // Sandbox-safe fallback dir
        let fallbackPlay = talkieSupport
            .appendingPathComponent("terminal", isDirectory: true)
            .appendingPathComponent("playground", isDirectory: true)

        let fallbackCopy = talkieSupport
            .appendingPathComponent("terminal", isDirectory: true)
            .appendingPathComponent("copy", isDirectory: true)

        // Ensure dirs exist
        try? fm.createDirectory(at: talkieSupport, withIntermediateDirectories: true, attributes: nil)
        try? fm.createDirectory(at: terminalHome, withIntermediateDirectories: true, attributes: nil)

        // Try preferred dirs first; if creation fails (common in sandbox), fall back.
        let playURL: URL
        let copyURL: URL
        do {
            try fm.createDirectory(at: preferredPlay, withIntermediateDirectories: true, attributes: nil)
            try fm.createDirectory(at: preferredCopy, withIntermediateDirectories: true, attributes: nil)
            playURL = preferredPlay
            copyURL = preferredCopy
        } catch {
            try? fm.createDirectory(at: fallbackPlay, withIntermediateDirectories: true, attributes: nil)
            try? fm.createDirectory(at: fallbackCopy, withIntermediateDirectories: true, attributes: nil)
            playURL = fallbackPlay
            copyURL = fallbackCopy
        }

        // Write a minimal .zshenv to ensure PROMPT / PROMPT_EOL_MARK are applied reliably.
        let zshenvURL = terminalHome.appendingPathComponent(".zshenv")
        let zshenv = """
        # Talkie Shell bootstrap (boring + deterministic)
        if [[ -o interactive ]]; then
          unsetopt BEEP
          unsetopt MONITOR

          setopt PROMPT_CR
          setopt PROMPT_SP

          PROMPT='%n %~ > '
          RPROMPT=''
          PROMPT_EOL_MARK=''
          PS2=''

          # Some zsh configs can reintroduce PROMPT_EOL_MARK; force it off every prompt.
          function precmd() { PROMPT_EOL_MARK='' }

          # minimal convenience
          alias talkie-play='cd "$TALKIE_PLAY"'
          alias talkie-copy='cd "$TALKIE_EXPORT"'
          alias talkie-env='echo "PLAY=$TALKIE_PLAY"; echo "COPY=$TALKIE_EXPORT"; pwd'

          # JSON-only mirror into talkie-copy
          alias talkie-sync='rsync -a --delete --include="*/" --include="*.json" --exclude="*" "$TALKIE_DATA/export/" "$TALKIE_EXPORT/"'

          # quick access to recordings JSON
          alias talkie-json='cat "$TALKIE_DATA/export/recordings.json" | jq'
          alias talkie-recent='cat "$TALKIE_DATA/export/recordings-recent.json" | jq'
          alias talkie-list='cat "$TALKIE_DATA/export/recordings.json" | jq ".memos[] | {title, createdAt, duration}"'

          # sensible default directory
          if [ -d "$TALKIE_PLAY" ]; then
            cd "$TALKIE_PLAY"
          elif [ -d "$TALKIE_EXPORT" ]; then
            cd "$TALKIE_EXPORT"
          elif [ -d "$TALKIE_DATA/export" ]; then
            cd "$TALKIE_DATA/export"
          elif [ -d "$TALKIE_DATA" ]; then
            cd "$TALKIE_DATA"
          fi
        fi
        """
        try? zshenv.write(to: zshenvURL, atomically: true, encoding: .utf8)

        // Environment: minimal, but include brew paths so jq/rg/etc work when installed
        let env: [String: String] = [
            "TERM": "xterm-256color",
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": terminalHome.path,
            "ZDOTDIR": terminalHome.path,
            "TALKIE_DATA": talkieSupport.path,
            "TALKIE_EXPORT": copyURL.path,
            "TALKIE_PLAY": playURL.path
        ]

        // Interactive shell; -f disables reading /etc/zshrc and ~/.zshrc, +m disables job control
        let args = ["-f", "-i", "+m"]
        return (env, args)
    }
}

// MARK: - PTY Process Manager

/// Manages a pseudo-terminal running zsh
final class PTYProcess {
    private var masterFD: Int32 = -1
    private var pid: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var isRunning = false

    var onOutput: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?

    deinit {
        terminate()
    }

    /// Start the shell process
    func start(executable: String = "/bin/zsh", args: [String], environment: [String: String]) -> Bool {
        guard !isRunning else { return false }

        // Set up environment
        var envArray = environment.map { "\($0.key)=\($0.value)" }
        envArray.append("LANG=en_US.UTF-8")

        // Create C-style string arrays
        let cArgs = ([executable] + args).map { strdup($0) } + [nil]
        let cEnv = envArray.map { strdup($0) } + [nil]

        defer {
            cArgs.forEach { if let p = $0 { free(p) } }
            cEnv.forEach { if let p = $0 { free(p) } }
        }

        // Fork with PTY
        var winSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)

        pid = forkpty(&masterFD, nil, nil, &winSize)

        if pid < 0 {
            // Fork failed
            return false
        } else if pid == 0 {
            // Child process - execve expects null-terminated arrays of optional pointers
            var argsCopy: [UnsafeMutablePointer<CChar>?] = cArgs
            var envCopy: [UnsafeMutablePointer<CChar>?] = cEnv
            execve(executable, &argsCopy, &envCopy)
            _exit(1) // execve failed
        }

        // Parent process
        isRunning = true

        // Set non-blocking mode
        let flags = fcntl(masterFD, F_GETFL)
        _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

        // Create dispatch source for reading
        readSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: .global(qos: .userInteractive))

        readSource?.setEventHandler { [weak self] in
            self?.handleRead()
        }

        readSource?.setCancelHandler { [weak self] in
            if let fd = self?.masterFD, fd >= 0 {
                close(fd)
            }
            self?.masterFD = -1
        }

        readSource?.resume()

        // Monitor child process
        DispatchQueue.global().async { [weak self] in
            var status: Int32 = 0
            waitpid(self?.pid ?? 0, &status, 0)

            DispatchQueue.main.async {
                self?.isRunning = false
                self?.onExit?(status)
            }
        }

        return true
    }

    private func handleRead() {
        var buffer = [UInt8](repeating: 0, count: 4096)

        let bytesRead = read(masterFD, &buffer, buffer.count)

        if bytesRead > 0 {
            let data = Data(bytes: buffer, count: bytesRead)
            DispatchQueue.main.async { [weak self] in
                self?.onOutput?(data)
            }
        } else if bytesRead < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
            // Error or EOF
            readSource?.cancel()
        }
    }

    /// Write data to the PTY
    func write(_ data: Data) {
        guard isRunning, masterFD >= 0 else { return }

        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                _ = Darwin.write(masterFD, baseAddress, data.count)
            }
        }
    }

    /// Write string to the PTY
    func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            write(data)
        }
    }

    /// Resize the PTY
    func resize(cols: UInt16, rows: UInt16) {
        guard isRunning, masterFD >= 0 else { return }

        var winSize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &winSize)
    }

    /// Terminate the shell process
    func terminate() {
        if isRunning, pid > 0 {
            kill(pid, SIGTERM)
        }
        readSource?.cancel()
        isRunning = false
    }
}

// MARK: - XTerm WebView

/// WKWebView subclass that hosts xterm.js and manages the PTY
final class XTermWebView: WKWebView {
    private var ptyProcess: PTYProcess?
    private var isTerminalReady = false
    private var pendingOutput: [Data] = []

    override var acceptsFirstResponder: Bool { true }

    init() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Set up user content controller for message handling
        let contentController = WKUserContentController()
        config.userContentController = contentController

        super.init(frame: .zero, configuration: config)

        // Register message handlers
        contentController.add(LeakAvoider(delegate: self), name: "terminalInput")
        contentController.add(LeakAvoider(delegate: self), name: "terminalResize")
        contentController.add(LeakAvoider(delegate: self), name: "terminalReady")
        contentController.add(LeakAvoider(delegate: self), name: "terminalTitle")

        // Allow inspecting with Safari developer tools
        if #available(macOS 13.3, *) {
            isInspectable = true
        }

        // Load xterm.html
        loadTerminalHTML()

        // Set up context menu
        setupContextMenu()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        ptyProcess?.terminate()
        configuration.userContentController.removeAllScriptMessageHandlers()
    }

    private func loadTerminalHTML() {
        // Try to load from bundle
        if let htmlURL = Bundle.main.url(forResource: "xterm", withExtension: "html", subdirectory: "Resources/Terminal") {
            loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else if let htmlURL = Bundle.main.url(forResource: "xterm", withExtension: "html") {
            loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            // Fallback: load from app support or use inline HTML
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let terminalHTML = appSupport?.appendingPathComponent("Talkie/terminal/xterm.html")

            if let url = terminalHTML, FileManager.default.fileExists(atPath: url.path) {
                loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                // Use CDN-based fallback
                loadCDNFallback()
            }
        }
    }

    private func loadCDNFallback() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <link rel="stylesheet" href="https://unpkg.com/@xterm/xterm@5.5.0/css/xterm.css">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; overflow: hidden; background: #1a1a1a; }
                #terminal { width: 100%; height: 100%; }
            </style>
        </head>
        <body>
            <div id="terminal"></div>
            <script src="https://unpkg.com/@xterm/xterm@5.5.0/lib/xterm.js"></script>
            <script src="https://unpkg.com/@xterm/addon-fit@0.10.0/lib/addon-fit.js"></script>
            <script>
                const term = new Terminal({
                    fontFamily: 'SF Mono, Menlo, Monaco, monospace',
                    fontSize: 12,
                    cursorBlink: true,
                    theme: { background: '#1a1a1a', foreground: '#e0e0e0' }
                });
                const fitAddon = new FitAddon.FitAddon();
                term.loadAddon(fitAddon);
                term.open(document.getElementById('terminal'));
                fitAddon.fit();
                new ResizeObserver(() => {
                    fitAddon.fit();
                    window.webkit?.messageHandlers?.terminalResize?.postMessage({ cols: term.cols, rows: term.rows });
                }).observe(document.getElementById('terminal'));
                term.onData(data => window.webkit?.messageHandlers?.terminalInput?.postMessage(data));
                window.terminalAPI = {
                    write: data => term.write(data),
                    writeBase64: b64 => term.write(Uint8Array.from(atob(b64), c => c.charCodeAt(0))),
                    focus: () => term.focus(),
                    fit: () => { fitAddon.fit(); return { cols: term.cols, rows: term.rows }; }
                };
                window.webkit?.messageHandlers?.terminalReady?.postMessage({ cols: term.cols, rows: term.rows });
                term.focus();
            </script>
        </body>
        </html>
        """
        loadHTMLString(html, baseURL: nil)
    }

    private func setupContextMenu() {
        let menu = NSMenu(title: "Terminal")
        menu.addItem(withTitle: "Copy", action: #selector(copySelection), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(pasteClipboard), keyEquivalent: "v")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Select All", action: #selector(selectAllText), keyEquivalent: "a")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Clear", action: #selector(clearTerminal), keyEquivalent: "k")
        self.menu = menu
    }

    private func startShell() {
        let boot = TalkieTerminalBootstrap.prepare()

        ptyProcess = PTYProcess()

        ptyProcess?.onOutput = { [weak self] data in
            self?.handlePTYOutput(data)
        }

        ptyProcess?.onExit = { [weak self] status in
            // Shell exited, could restart or show message
            self?.evaluateJavaScript("terminalAPI.write('\\r\\n[Process exited with code \(status)]\\r\\n')", completionHandler: nil)
        }

        _ = ptyProcess?.start(args: boot.args, environment: boot.env)
    }

    private func handlePTYOutput(_ data: Data) {
        if isTerminalReady {
            sendToTerminal(data)
        } else {
            pendingOutput.append(data)
        }
    }

    private func sendToTerminal(_ data: Data) {
        let base64 = data.base64EncodedString()
        evaluateJavaScript("terminalAPI.writeBase64('\(base64)')", completionHandler: nil)
    }

    private func flushPendingOutput() {
        for data in pendingOutput {
            sendToTerminal(data)
        }
        pendingOutput.removeAll()
    }

    // MARK: - Actions

    @objc private func copySelection() {
        evaluateJavaScript("terminalAPI.copySelection()") { result, error in
            // Selection copied to clipboard via JS
        }
    }

    @objc private func pasteClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            let escaped = string.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: "\\n")
            evaluateJavaScript("terminalAPI.paste('\(escaped)')", completionHandler: nil)
        }
    }

    @objc private func selectAllText() {
        evaluateJavaScript("terminalAPI.selectAll()", completionHandler: nil)
    }

    @objc private func clearTerminal() {
        evaluateJavaScript("terminalAPI.clear()", completionHandler: nil)
    }

    // MARK: - Keyboard Handling

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if mods.contains(.command) {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "c":
                    copySelection()
                    return
                case "v":
                    pasteClipboard()
                    return
                case "a":
                    selectAllText()
                    return
                case "k":
                    clearTerminal()
                    return
                default:
                    break
                }
            }
        }

        super.keyDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
            self?.evaluateJavaScript("terminalAPI?.focus()", completionHandler: nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

// MARK: - Script Message Handler

extension XTermWebView: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "terminalInput":
            if let input = message.body as? String {
                ptyProcess?.write(input)
            }

        case "terminalResize":
            if let dict = message.body as? [String: Int],
               let cols = dict["cols"],
               let rows = dict["rows"] {
                ptyProcess?.resize(cols: UInt16(cols), rows: UInt16(rows))
            }

        case "terminalReady":
            isTerminalReady = true

            // Start the shell now that terminal is ready
            startShell()

            // Flush any pending output
            flushPendingOutput()

            // Get initial dimensions
            if let dict = message.body as? [String: Int],
               let cols = dict["cols"],
               let rows = dict["rows"] {
                ptyProcess?.resize(cols: UInt16(cols), rows: UInt16(rows))
            }

        case "terminalTitle":
            // Could update window title if needed
            break

        default:
            break
        }
    }
}

// MARK: - Leak Avoider

/// Prevents retain cycle between WKUserContentController and the delegate
private class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - SwiftUI Views

struct XTermView: NSViewRepresentable {
    func makeNSView(context: Context) -> XTermWebView {
        XTermWebView()
    }

    func updateNSView(_ nsView: XTermWebView, context: Context) {
        // No updates needed
    }
}

// MARK: - Embedded Terminal View (for bottom panel - no chrome)

struct EmbeddedTerminalView: NSViewRepresentable {
    func makeNSView(context: Context) -> XTermWebView {
        XTermWebView()
    }

    func updateNSView(_ nsView: XTermWebView, context: Context) {
        // No updates needed
    }
}

#Preview {
    TerminalContentView()
        .frame(width: 700, height: 400)
}
