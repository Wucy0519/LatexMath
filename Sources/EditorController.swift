import AppKit
import UniformTypeIdentifiers
import WebKit

final class ScriptProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

final class EditorController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let window: NSWindow
    private let webView: WKWebView
    private let proxy = ScriptProxy()
    private lazy var rasterizer = FormulaRasterizer()
    private var pageReady = false
    private var pending: [String] = []

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "公式台"
        window.minSize = NSSize(width: 980, height: 680)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.086, green: 0.075, blue: 0.059, alpha: 1)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(proxy, name: "desk")
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        proxy.target = self
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        if let content = window.contentView {
            webView.frame = content.bounds
            webView.autoresizingMask = [.width, .height]
            content.addSubview(webView)
        }
        if !window.setFrameUsingName("公式台") {
            window.center()
        }
        window.setFrameAutosaveName("公式台")
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
    }

    func persistThen(_ done: @escaping () -> Void) {
        guard pageReady else { done(); return }
        var finished = false
        func finish() {
            if finished { return }
            finished = true
            done()
        }
        webView.evaluateJavaScript("window.desk.snapshotJSON()") { result, _ in
            if let text = result as? String, let data = text.data(using: .utf8) {
                try? LibraryStore.replace(data: data)
            }
            finish()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { finish() }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            pageReady = true
            let (library, warning) = LibraryStore.loadOrCreate()
            pushLibrary(library)
            if let warning { notify(warning, tone: "warn") }
            let queued = pending
            pending.removeAll()
            for script in queued {
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
        case "save":
            guard let library = body["library"] else { return }
            do {
                let data = try JSONSerialization.data(withJSONObject: library)
                try LibraryStore.replace(data: data)
            } catch {
                notify("公式库没有写进去。", tone: "warn")
            }
        case "copyText":
            guard let text = body["text"] as? String, !text.isEmpty else { return }
            Clipboard.copyText(text)
            notify(body["done"] as? String ?? "已复制")
        case "copyOffice":
            copyOffice(body)
        case "copyMathML":
            guard let mathml = body["mathml"] as? String else { return }
            Clipboard.copyMathML(mathml)
            notify("已复制 MathML")
        case "copyImage":
            copyImage(body)
        case "exportDocx":
            exportDocx(body)
        case "reveal":
            revealLibrary()
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    @objc func newFormula() { emit("window.desk.newFormula()") }
    @objc func saveFormula() { emit("window.desk.save()") }
    @objc func saveAsNew() { emit("window.desk.saveAsNew()") }
    @objc func copyLatex() { emit("window.desk.copyLatex()") }
    @objc func copyWord() { emit("window.desk.copyWord()") }
    @objc func copyPowerPoint() { emit("window.desk.copyPowerPoint()") }
    @objc func copyImage() { emit("window.desk.copyImage()") }
    @objc func copyClearImage() { emit("window.desk.copyClearImage()") }
    @objc func copyChalkImage() { emit("window.desk.copyChalkImage()") }
    @objc func copyMathML() { emit("window.desk.copyMathML()") }
    @objc func copyDollars() { emit("window.desk.copyDollars()") }
    @objc func toggleDisplay() { emit("window.desk.toggleDisplay()") }
    @objc func zoomIn() { emit("window.desk.bumpSize(2)") }
    @objc func zoomOut() { emit("window.desk.bumpSize(-2)") }
    @objc func focusSearch() { emit("window.desk.focusSearch()") }
    @objc func exportDocx() { emit("window.desk.exportDocx()") }
    @objc func showHelp() { emit("window.desk.help()") }
    @objc func closeWindow() { window.performClose(nil) }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "公式台"
        alert.informativeText = "公式以 LaTeX 存在本机。复制到 Word 或 PowerPoint 时，会转成 Office 公式，粘贴之后还能改。复制图片则按预览的样子贴进任何软件。\n\n版本 1.0"
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }

    @objc func revealLibrary() {
        let url = LibraryStore.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? LibraryStore.write(LibraryStore.emptyFile())
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func exportLibrary() {
        withSnapshot { [weak self] data in
            guard let self else { return }
            let panel = NSSavePanel()
            panel.title = "导出公式库"
            panel.nameFieldStringValue = "公式库.json"
            panel.allowedContentTypes = [.json]
            panel.beginSheetModal(for: self.window) { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    let file = try JSONDecoder().decode(LibraryFile.self, from: data)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(file).write(to: url, options: .atomic)
                    self.notify("已导出公式库")
                } catch {
                    self.notify("导出失败。", tone: "warn")
                }
            }
        }
    }

    @objc func importLibrary() {
        withSnapshot { [weak self] current in
            guard let self else { return }
            let panel = NSOpenPanel()
            panel.title = "导入公式库"
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.json]
            panel.beginSheetModal(for: self.window) { response in
                guard response == .OK, let url = panel.urls.first else { return }
                self.finishImport(current: current, url: url)
            }
        }
    }

    private func finishImport(current: Data, url: URL) {
        let incomingData: Data
        let incoming: LibraryFile
        do {
            incomingData = try Data(contentsOf: url)
            guard incomingData.count < 20_000_000 else {
                notify("这个文件太大了。", tone: "warn")
                return
            }
            incoming = try JSONDecoder().decode(LibraryFile.self, from: incomingData)
        } catch {
            notify("这个文件不是公式台的公式库。", tone: "warn")
            return
        }
        let alert = NSAlert()
        alert.messageText = "导入公式库"
        alert.informativeText = "合并会按编号更新已有的公式，并加入新的。替换会用这份文件盖掉现在的公式库。"
        alert.addButton(withTitle: "合并")
        alert.addButton(withTitle: "替换")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard let base = try? JSONDecoder().decode(LibraryFile.self, from: current) else { return }
            let file: LibraryFile
            if response == .alertFirstButtonReturn {
                file = LibraryStore.merging(base, with: incoming)
            } else if response == .alertSecondButtonReturn {
                file = incoming
            } else {
                return
            }
            do {
                try LibraryStore.write(file)
                self.pushLibrary(file)
                self.notify(response == .alertFirstButtonReturn ? "已合并进公式库" : "已换成这份公式库")
            } catch {
                self.notify("导入没有写进去。", tone: "warn")
            }
        }
    }

    private func copyOffice(_ body: [String: Any]) {
        guard let mathml = body["mathml"] as? String else { return }
        let display = bool(body["display"])
        let points = points(body["points"])
        let target: OfficeTarget = (body["target"] as? String) == "ppt" ? .powerpoint : .word
        do {
            let omml = try OfficeMath.convert(mathml: mathml)
            Clipboard.copyOfficeHTML(OfficeMath.html(for: omml, target: target, display: display, points: points))
            let size = Int(points.rounded())
            notify("已复制 \(size) pt 公式。在 Word 或 PowerPoint 里按 ⌘V。")
        } catch {
            notify(error.localizedDescription, tone: "warn")
        }
    }

    private func copyImage(_ body: [String: Any]) {
        guard let latex = body["latex"] as? String else { return }
        let display = bool(body["display"])
        let appearance = body["appearance"] as? String ?? "paper"
        rasterizer.render(latex: latex, display: display, appearance: appearance) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let image):
                    Clipboard.copyImage(png: image.png, pointSize: image.pointSize, pixels: image.pixels)
                    switch appearance {
                    case "clear":
                        self.notify("已复制透明底图片。浅色底上能直接看清。")
                    case "chalk":
                        self.notify("已复制白字透明图片。适合深色幻灯片。")
                    default:
                        self.notify("已复制白底图片。Word、PowerPoint 和其他软件都能按原样贴上。")
                    }
                case .failure(let error):
                    self.notify(error.localizedDescription, tone: "warn")
                }
            }
        }
    }

    private func exportDocx(_ body: [String: Any]) {
        guard let mathml = body["mathml"] as? String else { return }
        let name = safeName(body["name"] as? String ?? "公式")
        let chosen = points(body["points"])
        let panel = NSSavePanel()
        panel.title = "导出 Word 文档"
        panel.nameFieldStringValue = name + ".docx"
        if let type = UTType(filenameExtension: "docx") {
            panel.allowedContentTypes = [type]
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let omml = try OfficeMath.convert(mathml: mathml)
                try OfficeMath.writeDocx(omml: omml, name: name, to: url, points: chosen)
                self.notify("已导出 Word 文档")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self.notify(error.localizedDescription, tone: "warn")
            }
        }
    }

    private func withSnapshot(_ work: @escaping (Data) -> Void) {
        guard pageReady else { return }
        webView.evaluateJavaScript("window.desk.snapshotJSON()") { [weak self] result, _ in
            guard let text = result as? String, let data = text.data(using: .utf8) else {
                self?.notify("没能读到当前公式库", tone: "warn")
                return
            }
            work(data)
        }
    }

    private func pushLibrary(_ file: LibraryFile) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(file), var json = String(data: data, encoding: .utf8) else { return }
        json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        emit("window.desk.onLibrary(\(json))")
    }

    private func notify(_ text: String, tone: String = "good") {
        guard let data = try? JSONSerialization.data(withJSONObject: ["text": text, "tone": tone]),
              var json = String(data: data, encoding: .utf8) else { return }
        json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        emit("window.desk.onNotice(\(json))")
    }

    private func emit(_ script: String) {
        if !pageReady {
            pending.append(script)
            return
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func points(_ value: Any?) -> Double {
        let number = (value as? NSNumber)?.doubleValue ?? 18
        return min(96, max(8, number))
    }

    private func bool(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let flag = value as? Bool { return flag }
        return true
    }

    private func safeName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "公式" }
        return String(cleaned.prefix(40))
    }
}
