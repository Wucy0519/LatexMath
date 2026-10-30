import AppKit

@main
enum FormulaDeskMain {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--self-test") {
            exit(SelfTest.run())
        }
        if args.contains("--render-png") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = RenderDelegate()
            app.delegate = delegate
            app.run()
            return
        }
        if let code = CLI.run(args) {
            exit(code)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let editor = EditorController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu(editor)
        editor.show()
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        editor.persistThen {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

final class RenderDelegate: NSObject, NSApplicationDelegate {
    let raster = FormulaRasterizer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--render-png"), flag + 2 < args.count else {
            fputs("用法: 公式台 --render-png 输入.tex 输出.png [paper|clear|chalk] [--inline]\n", stderr)
            exit(2)
        }
        let input = args[flag + 1]
        let output = args[flag + 2]
        let appearance = (flag + 3 < args.count && !args[flag + 3].hasPrefix("--")) ? args[flag + 3] : "paper"
        let display = !args.contains("--inline")
        guard let latex = try? String(contentsOfFile: input, encoding: .utf8) else {
            fputs("打不开 \(input)\n", stderr)
            exit(1)
        }
        raster.render(latex: latex, display: display, appearance: appearance) { result in
            switch result {
            case .success(let image):
                do {
                    try image.png.write(to: URL(fileURLWithPath: output))
                    fputs("wrote \(output) \(Int(image.pointSize.width))x\(Int(image.pointSize.height))\n", stderr)
                    exit(0)
                } catch {
                    fputs("\(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            case .failure(let error):
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
    }
}

enum CLI {
    static func run(_ args: [String]) -> Int32? {
        let flags = ["--omml", "--html", "--clipboard", "--docx"]
        guard flags.contains(where: { args.contains($0) }) else { return nil }
        if let paths = values(after: "--docx", count: 2, in: args) { return docx(paths[0], paths[1]) }
        if let index = args.firstIndex(of: "--clipboard"), index + 2 < args.count {
            let points = index + 3 < args.count ? Double(args[index + 3]) ?? 18 : 18
            return clipboard(args[index + 1], args[index + 2], points)
        }
        if let paths = values(after: "--html", count: 2, in: args) { return html(paths[0], paths[1]) }
        if let paths = values(after: "--omml", count: 1, in: args) { return omml(paths[0]) }
        fputs("参数不完整\n", stderr)
        return 2
    }

    private static func values(after flag: String, count: Int, in args: [String]) -> [String]? {
        guard let index = args.firstIndex(of: flag), index + count < args.count else { return nil }
        let slice = args[(index + 1)...(index + count)]
        if slice.contains(where: { $0.hasPrefix("--") }) { return nil }
        return Array(slice)
    }

    private static func mathml(at path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    private static func target(_ name: String) -> OfficeTarget {
        name == "ppt" ? .powerpoint : .word
    }

    private static func omml(_ path: String) -> Int32 {
        guard let source = mathml(at: path) else { return missing(path) }
        do {
            print(try OfficeMath.convert(mathml: source))
            return 0
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            return 1
        }
    }

    private static func html(_ path: String, _ name: String) -> Int32 {
        guard let source = mathml(at: path) else { return missing(path) }
        do {
            let omml = try OfficeMath.convert(mathml: source)
            print(OfficeMath.html(for: omml, target: target(name), display: true))
            return 0
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            return 1
        }
    }

    private static func clipboard(_ path: String, _ name: String, _ points: Double) -> Int32 {
        guard let source = mathml(at: path) else { return missing(path) }
        _ = NSApplication.shared
        do {
            let omml = try OfficeMath.convert(mathml: source)
            Clipboard.copyOfficeHTML(OfficeMath.html(for: omml, target: target(name), display: true, points: points))
            fputs("已放入剪贴板\n", stderr)
            return 0
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            return 1
        }
    }

    private static func docx(_ path: String, _ output: String) -> Int32 {
        guard let source = mathml(at: path) else { return missing(path) }
        do {
            let omml = try OfficeMath.convert(mathml: source)
            try OfficeMath.writeDocx(omml: omml, name: "公式", to: URL(fileURLWithPath: output))
            fputs("wrote \(output)\n", stderr)
            return 0
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            return 1
        }
    }

    private static func missing(_ path: String) -> Int32 {
        fputs("打不开 \(path)\n", stderr)
        return 1
    }
}

private func buildMenu(_ editor: EditorController) {
    let main = NSMenu()

    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu(title: "公式台")
    appItem.submenu = appMenu
    item(appMenu, "关于公式台", #selector(EditorController.showAbout), "", editor)
    appMenu.addItem(.separator())
    item(appMenu, "使用说明", #selector(EditorController.showHelp), "", editor)
    item(appMenu, "显示公式库", #selector(EditorController.revealLibrary), "", editor)
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "退出公式台", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    let fileItem = NSMenuItem()
    main.addItem(fileItem)
    let file = NSMenu(title: "文件")
    fileItem.submenu = file
    item(file, "新公式", #selector(EditorController.newFormula), "n", editor)
    item(file, "保存", #selector(EditorController.saveFormula), "s", editor)
    item(file, "存为新公式", #selector(EditorController.saveAsNew), "S", editor)
    file.addItem(.separator())
    item(file, "导出 Word 文档…", #selector(EditorController.exportDocx), "", editor)
    item(file, "导出公式库…", #selector(EditorController.exportLibrary), "", editor)
    item(file, "导入公式库…", #selector(EditorController.importLibrary), "", editor)
    file.addItem(.separator())
    item(file, "关闭", #selector(EditorController.closeWindow), "w", editor)

    let editItem = NSMenuItem()
    main.addItem(editItem)
    let edit = NSMenu(title: "编辑")
    editItem.submenu = edit
    edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    item(edit, "搜索公式库", #selector(EditorController.focusSearch), "f", editor)

    let copyItem = NSMenuItem()
    main.addItem(copyItem)
    let copy = NSMenu(title: "复制")
    copyItem.submenu = copy
    item(copy, "复制 LaTeX", #selector(EditorController.copyLatex), "C", editor)
    item(copy, "复制到 Word / PPT", #selector(EditorController.copyWord), "W", editor)
    item(copy, "复制图片", #selector(EditorController.copyImage), "I", editor)
    item(copy, "复制透明图片", #selector(EditorController.copyClearImage), "", editor)
    item(copy, "复制白字图片", #selector(EditorController.copyChalkImage), "", editor)
    item(copy, "复制 MathML", #selector(EditorController.copyMathML), "", editor)
    item(copy, "复制 $$ 公式", #selector(EditorController.copyDollars), "", editor)

    let viewItem = NSMenuItem()
    main.addItem(viewItem)
    let view = NSMenu(title: "显示")
    viewItem.submenu = view
    item(view, "切换独立 / 行内", #selector(EditorController.toggleDisplay), "d", editor)
    item(view, "放大预览", #selector(EditorController.zoomIn), "=", editor)
    item(view, "缩小预览", #selector(EditorController.zoomOut), "-", editor)

    NSApp.mainMenu = main
}

private func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, _ target: AnyObject) {
    let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
    entry.target = target
}
