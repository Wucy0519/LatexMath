import Foundation

enum OfficeTarget {
    case word
    case powerpoint
}

enum OfficeMathError: LocalizedError {
    case noStylesheet
    case notMath
    case transform(String)
    case zip(String)

    var errorDescription: String? {
        switch self {
        case .noStylesheet:
            return "没有找到 Word 的公式转换表。请确认 Microsoft Word 已安装。"
        case .notMath:
            return "这条公式没有变成 MathML。"
        case .transform(let detail):
            return "公式转换失败。\(detail)"
        case .zip(let detail):
            return "写出 Word 文档失败。\(detail)"
        }
    }
}

/// LaTeX 先在页面里用 Temml 变成 MathML。这里清掉多余分组、标好重音，
/// 再用本机 Word 自带的 mathml2omml.xsl 转成 Office 公式。
enum OfficeMath {
    static func stylesheetURL() -> URL? {
        let homes = ["/Applications", NSHomeDirectory() + "/Applications"]
        for home in homes {
            let url = URL(fileURLWithPath: home)
                .appendingPathComponent("Microsoft Word.app")
                .appendingPathComponent("Contents/Resources/mathml2omml.xsl")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static func convert(mathml: String) throws -> String {
        let prepared = try prepare(mathml)
        guard let stylesheet = stylesheetURL() else { throw OfficeMathError.noStylesheet }
        let directory = FileManager.default.temporaryDirectory
        let input = directory.appendingPathComponent("formula-\(UUID().uuidString).mml")
        let output = directory.appendingPathComponent("formula-\(UUID().uuidString).omml")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }
        try prepared.data(using: .utf8)?.write(to: input)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xsltproc")
        task.arguments = ["--nonet", "--encoding", "UTF-8", "-o", output.path, stylesheet.path, input.path]
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = Pipe()
        try task.run()
        task.waitUntilExit()
        let errorText = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard task.terminationStatus == 0, let omml = try? String(contentsOf: output, encoding: .utf8), omml.contains("oMath") else {
            let line = errorText.split(separator: "\n").first.map(String.init) ?? "转换表没有给出公式"
            throw OfficeMathError.transform(line)
        }
        return stripInvisibles(stripDeclaration(omml))
    }

    static func html(for omml: String, target: OfficeTarget, display: Bool, points: Double = 18) -> String {
        var math = stripInvisibles(stripDeclaration(omml))
        if target == .powerpoint || !display {
            math = inlineFragment(math)
        }
        math = applyingPointSize(points, to: math)
        // Word 的剪贴板认的是 2004 年的公式命名空间，并且要包在条件注释里，才会变成可编辑公式。
        math = math.replacingOccurrences(
            of: "http://schemas.openxmlformats.org/officeDocument/2006/math",
            with: "http://schemas.microsoft.com/office/2004/12/omml"
        )
        math = expandEmptyTags(math)
        let size = String(format: "%.1f", min(96, max(8, points)))
        let align = display && target == .word ? "text-align:center;" : ""
        let body = "<p class=MsoNormal style='font-size:\(size)pt;\(align)'><!--[if gte msEquation 12]>\(math)<![endif]--></p>"
        return """
        <html xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns:m="http://schemas.microsoft.com/office/2004/12/omml" xmlns="http://www.w3.org/TR/REC-html40">
        <head><meta http-equiv=Content-Type content="text/html; charset=utf-8"><meta name=ProgId content=Word.Document></head>
        <body><!--StartFragment-->\(body)<!--EndFragment--></body></html>
        """
    }

    static func writeDocx(omml: String, name: String, to url: URL, points: Double = 18) throws {
        let math = applyingPointSize(points, to: stripInvisibles(stripDeclaration(omml)))
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("formuladesk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try file(contentTypes, staging.appendingPathComponent("[Content_Types].xml"))
        try file(packageRels, staging.appendingPathComponent("_rels/.rels"))
        try file(documentXML(math), staging.appendingPathComponent("word/document.xml"))
        try file(stylesXML, staging.appendingPathComponent("word/styles.xml"))
        try file(documentRels, staging.appendingPathComponent("word/_rels/document.xml.rels"))
        try file(coreXML(name), staging.appendingPathComponent("docProps/core.xml"))
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        task.currentDirectoryURL = staging
        task.arguments = ["-X", "-q", "-r", url.path, "[Content_Types].xml", "_rels", "word", "docProps"]
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = Pipe()
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let detail = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw OfficeMathError.zip(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func prepare(_ mathml: String) throws -> String {
        let extracted = extractMath(mathml)
        let document: XMLDocument
        do {
            document = try XMLDocument(xmlString: extracted, options: [.nodeLoadExternalEntitiesNever])
        } catch {
            throw OfficeMathError.notMath
        }
        guard let root = document.rootElement(), root.localName == "math" else { throw OfficeMathError.notMath }
        dropPresentationAttributes(in: root)
        removeInvisibleOperators(in: root)
        unwrapTrivialRows(in: root)
        markAccents(in: root)
        return document.xmlString
    }

    private static func extractMath(_ source: String) -> String {
        guard let start = source.range(of: "<math"), let end = source.range(of: "</math>", options: .backwards) else {
            return source
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    private static func dropPresentationAttributes(in root: XMLElement) {
        let nodes = ([root] + descendants(of: root))
        for node in nodes {
            node.removeAttribute(forName: "class")
            node.removeAttribute(forName: "style")
            node.removeAttribute(forName: "id")
        }
    }

    private static func removeInvisibleOperators(in root: XMLElement) {
        for node in descendants(of: root) where node.localName == "mo" && isInvisible(node.stringValue ?? "") {
            node.detach()
        }
    }

    private static func isInvisible(_ text: String) -> Bool {
        let scalars = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard !scalars.isEmpty else { return false }
        let invisible: Set<UInt32> = [0x2061, 0x2062, 0x2063, 0x2064, 0x200B]
        return scalars.allSatisfy { invisible.contains($0.value) }
    }

    private static func unwrapTrivialRows(in root: XMLElement) {
        for _ in 0..<80 {
            let rows = descendants(of: root).filter { $0.localName == "mrow" }
            var changed = false
            for row in rows {
                let elements = elementChildren(row)
                let strayText = (row.children ?? []).contains { node in
                    node.kind == .text && !(node.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                guard elements.count == 1, !strayText, (row.attributes ?? []).isEmpty, let parent = row.parent as? XMLElement else { continue }
                parent.replaceChild(at: row.index, with: elements[0].copy() as! XMLNode)
                changed = true
                break
            }
            if !changed { break }
        }
    }

    private static let accentMap: [String: String] = [
        "^": "\u{02C6}",
        "~": "\u{02DC}",
        "\u{203E}": "\u{00AF}",
        "\u{2192}": "\u{20D7}",
        "\u{02C6}": "\u{02C6}",
        "\u{00AF}": "\u{00AF}",
        "\u{02D9}": "\u{02D9}",
        "\u{00A8}": "\u{00A8}",
        "\u{02DC}": "\u{02DC}",
        "\u{02D8}": "\u{02D8}",
        "\u{02C7}": "\u{02C7}",
        "\u{20D7}": "\u{20D7}",
        "\u{0302}": "\u{02C6}",
        "\u{0304}": "\u{00AF}",
        "\u{0307}": "\u{02D9}",
        "\u{0308}": "\u{00A8}",
        ".": "\u{02D9}",
    ]

    private static func markAccents(in root: XMLElement) {
        for node in descendants(of: root) where node.localName == "mover" || node.localName == "munder" {
            guard let op = accentOperator(of: node) else { continue }
            let raw = (op.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let mapped = accentMap[raw] else { continue }
            if mapped != raw { op.stringValue = mapped }
            let name = node.localName == "munder" ? "accentunder" : "accent"
            setAttribute(node, name, "true")
        }
    }

    private static func accentOperator(of node: XMLElement) -> XMLElement? {
        var kids = elementChildren(node)
        guard kids.count >= 2 else { return nil }
        var op = kids[1]
        if op.localName == "mrow" {
            let inner = elementChildren(op)
            if inner.count == 1, let only = inner.first { op = only }
        }
        kids = elementChildren(node)
        return op.localName == "mo" ? op : nil
    }

    private static func descendants(of root: XMLElement) -> [XMLElement] {
        (try? root.nodes(forXPath: ".//*"))?.compactMap { $0 as? XMLElement } ?? []
    }

    private static func elementChildren(_ node: XMLElement) -> [XMLElement] {
        (node.children ?? []).compactMap { $0 as? XMLElement }
    }

    /// 把用户选的字号写进每个数学字符。上下标按比例缩小，Word 和 PowerPoint 才会按这个大小显示。
    static func applyingPointSize(_ points: Double, to omml: String) -> String {
        let source = stripDeclaration(omml)
        guard let document = try? XMLDocument(xmlString: source, options: [.nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else { return source }
        if root.namespaces?.contains(where: { $0.name == "w" }) != true {
            root.addNamespace(XMLNode.namespace(withName: "w", stringValue: wordNamespace) as! XMLNode)
        }
        stampSize(root, points: min(96, max(8, points)), level: 0)
        return stripDeclaration(document.xmlString)
    }

    private static let wordNamespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private static let scriptSlots: [String: Set<String>] = [
        "sSub": ["sub"],
        "sSup": ["sup"],
        "sSubSup": ["sub", "sup"],
        "sPre": ["sub", "sup"],
        "rad": ["deg"],
        "nary": ["sub", "sup"],
        "limLow": ["lim"],
        "limUpp": ["lim"],
    ]

    private static func stampSize(_ node: XMLElement, points: Double, level: Int) {
        if node.localName == "r" {
            let scale = level == 0 ? 1.0 : (level == 1 ? 0.7 : 0.5)
            let halfPoints = max(12, Int((points * scale * 2).rounded()))
            setRunSize(node, halfPoints: halfPoints)
        }
        let slots = scriptSlots[node.localName ?? ""] ?? []
        for child in elementChildren(node) {
            let next = slots.contains(child.localName ?? "") ? level + 1 : level
            stampSize(child, points: points, level: next)
        }
    }

    private static func setRunSize(_ run: XMLElement, halfPoints: Int) {
        for child in elementChildren(run) where child.name == "w:rPr" || (child.localName == "rPr" && child.uri == wordNamespace) {
            child.detach()
        }
        let properties = XMLElement(name: "w:rPr")
        properties.addChild(sizeElement("w:sz", halfPoints))
        properties.addChild(sizeElement("w:szCs", halfPoints))
        let index = (elementChildren(run).firstIndex { $0.localName == "rPr" && $0.name != "w:rPr" } ?? -1) + 1
        run.insertChild(properties, at: index)
    }

    private static func sizeElement(_ name: String, _ halfPoints: Int) -> XMLElement {
        let element = XMLElement(name: name)
        element.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: "\(halfPoints)") as! XMLNode)
        return element
    }

    private static func setAttribute(_ element: XMLElement, _ name: String, _ value: String) {
        if let existing = element.attribute(forName: name) {
            existing.stringValue = value
            return
        }
        element.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
    }

    private static func stripDeclaration(_ xml: String) -> String {
        var text = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<?xml"), let end = text.range(of: "?>") {
            text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func stripInvisibles(_ text: String) -> String {
        ["\u{2061}", "\u{2062}", "\u{2063}", "\u{2064}", "\u{200B}"].reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
    }

    private static func expandEmptyTags(_ xml: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<([A-Za-z]+):([A-Za-z]+)([^<>]*?)/>") else { return xml }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.stringByReplacingMatches(in: xml, range: range, withTemplate: "<$1:$2$3></$1:$2>")
    }

    private static func inlineFragment(_ omml: String) -> String {
        guard let document = try? XMLDocument(xmlString: omml, options: [.nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else { return omml }
        guard root.localName == "oMathPara",
              let math = elementChildren(root).first(where: { $0.localName == "oMath" }) else { return omml }
        let copy = math.copy() as! XMLElement
        if copy.attribute(forName: "xmlns:m") == nil && !(copy.xmlString.contains("xmlns:m")) {
            copy.addNamespace(XMLNode.namespace(withName: "m", stringValue: "http://schemas.openxmlformats.org/officeDocument/2006/math") as! XMLNode)
        }
        return stripDeclaration(copy.xmlString)
    }

    private static func file(_ contents: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.data(using: .utf8)?.write(to: url)
    }

    private static func documentXML(_ math: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
          <w:body>
            <w:p>
              <w:pPr><w:jc w:val="center"/></w:pPr>
              \(math)
            </w:p>
            <w:sectPr>
              <w:pgSz w:w="11906" w:h="16838"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private static func coreXML(_ name: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>\(xmlEscape(name))</dc:title>
          <dc:creator>公式台</dc:creator>
        </cp:coreProperties>
        """
    }

    private static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
      <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
    </Types>
    """

    private static let packageRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
    </Relationships>
    """

    private static let documentRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:docDefaults>
        <w:rPrDefault><w:rPr><w:rFonts w:ascii="Cambria Math" w:hAnsi="Cambria Math"/></w:rPr></w:rPrDefault>
      </w:docDefaults>
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
    </w:styles>
    """
}
