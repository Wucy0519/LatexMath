import Foundation

enum SelfTest {
    static func run() -> Int32 {
        var failures: [String] = []
        failures += libraryRoundTrip()
        failures += officeFixtures()
        if failures.isEmpty {
            fputs("self-test ok\n", stderr)
            return 0
        }
        for failure in failures {
            fputs(failure + "\n", stderr)
        }
        fputs("\(failures.count) 项没通过\n", stderr)
        return 1
    }

    private static func libraryRoundTrip() -> [String] {
        let file = LibraryFile(
            version: 1,
            draft: Draft(latex: "当 x>0", name: "名称", note: "备注", tag: "代数", display: false, loadedId: nil),
            settings: Settings(previewSize: 28, libraryWidth: 280),
            formulas: [
                Formula(id: "a", name: "欧拉", latex: "e^{i\\pi}+1=0", note: "", tag: "分析", pinned: true, display: true, created: 1, updated: 2)
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file),
              let back = try? JSONDecoder().decode(LibraryFile.self, from: data) else {
            return ["公式库没法编码"]
        }
        if back.draft.latex != "当 x>0" || back.draft.loadedId != nil || back.formulas.first?.pinned != true {
            return ["公式库往返之后变了"]
        }
        let merged = LibraryStore.merging(back, with: LibraryFile(
            version: 1,
            draft: Draft(latex: "", name: "", note: "", tag: "", display: true, loadedId: nil),
            settings: Settings(previewSize: 32, libraryWidth: 300),
            formulas: [
                Formula(id: "a", name: "欧拉改", latex: "e^{i\\pi}+1=0", note: "", tag: "分析", pinned: true, display: true, created: 1, updated: 3),
                Formula(id: "b", name: "新", latex: "x", note: "", tag: "", pinned: false, display: true, created: 4, updated: 4)
            ]
        ))
        if merged.formulas.count != 2 || merged.formulas[0].name != "欧拉改" || merged.draft.latex != "当 x>0" {
            return ["合并公式库不对"]
        }
        return []
    }

    private static func officeFixtures() -> [String] {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("fixtures") else {
            return ["应用里没有测试公式"]
        }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            return ["读不到测试公式"]
        }
        if files.isEmpty { return ["测试公式是空的"] }
        var failures: [String] = []
        for url in files {
            guard let data = try? Data(contentsOf: url),
                  let fixture = try? JSONDecoder().decode(Fixture.self, from: data) else {
                failures.append("读不懂 \(url.lastPathComponent)")
                continue
            }
            let omml: String
            do {
                omml = try OfficeMath.convert(mathml: fixture.mathml)
            } catch {
                failures.append("\(fixture.name) 转换失败：\(error.localizedDescription)")
                continue
            }
            if let dump = ProcessInfo.processInfo.environment["FORMULA_DUMP"], !dump.isEmpty {
                try? FileManager.default.createDirectory(atPath: dump, withIntermediateDirectories: true)
                try? omml.write(toFile: (dump as NSString).appendingPathComponent(fixture.name + ".omml"), atomically: true, encoding: .utf8)
            }
            if omml.unicodeScalars.contains(where: { $0.value == 0x2061 }) {
                failures.append("\(fixture.name) 里还有不可见的函数符")
            }
            for needle in fixture.expect where !omml.contains(needle) {
                failures.append("\(fixture.name) 缺少 \(needle)。开头：\(prefix(omml))")
            }
            if let needle = fixture.naryContains, !naryBaseContains(omml, needle) {
                failures.append("\(fixture.name) 的求和或积分没有带上后面的式子。开头：\(prefix(omml))")
            }
            let html = OfficeMath.html(for: omml, target: .word, display: fixture.display)
            if html.contains("<?xml") {
                failures.append("\(fixture.name) 的剪贴板里带了 XML 声明")
            }
            if !html.contains("msEquation") {
                failures.append("\(fixture.name) 的剪贴板没有 Word 公式标记")
            }
            if fixture.name == "quad" {
                let sized = OfficeMath.html(for: omml, target: .word, display: true, points: 24)
                if !sized.contains("w:val=\"48\"") {
                    failures.append("24 pt 没有写成 Word 字号。开头：\(prefix(sized))")
                }
                if !sized.contains("w:sz") {
                    failures.append("字号标签没有 Word 前缀")
                }
            }
            if html.range(of: #"<m:[A-Za-z]+[^<>]*/>"#, options: .regularExpression) != nil {
                failures.append("\(fixture.name) 的剪贴板里还有没展开的空标签")
            }
            if fixture.name == "quad" {
                let slides = OfficeMath.html(for: omml, target: .powerpoint, display: true)
                if slides.contains("oMathPara") {
                    failures.append("给 PowerPoint 的公式仍包着段落")
                }
            }
        }
        return failures
    }

    private static func naryBaseContains(_ omml: String, _ needle: String) -> Bool {
        guard let document = try? XMLDocument(xmlString: omml, options: [.nodeLoadExternalEntitiesNever]),
              let nary = (try? document.nodes(forXPath: "//*[local-name()='nary']"))?.first as? XMLElement,
              let base = (try? nary.nodes(forXPath: "./*[local-name()='e']"))?.first as? XMLElement else {
            return false
        }
        return base.xmlString.contains(needle)
    }

    private static func prefix(_ text: String) -> String {
        let compact = text.replacingOccurrences(of: "\n", with: "")
        return String(compact.prefix(360))
    }
}

private struct Fixture: Codable {
    var name: String
    var latex: String
    var display: Bool
    var mathml: String
    var expect: [String]
    var naryContains: String?
}
