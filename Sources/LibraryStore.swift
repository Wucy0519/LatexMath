import Foundation

struct Formula: Codable {
    var id: String
    var name: String
    var latex: String
    var note: String
    var tag: String
    var pinned: Bool
    var display: Bool
    var created: Double
    var updated: Double
}

struct Draft: Codable {
    var latex: String
    var name: String
    var note: String
    var tag: String
    var display: Bool
    var loadedId: String?
}

struct Settings: Codable {
    var previewSize: Double
    var libraryWidth: Double
    var pastePoints: Double

    private enum CodingKeys: String, CodingKey {
        case previewSize, libraryWidth, pastePoints
    }

    init(previewSize: Double, libraryWidth: Double, pastePoints: Double = 18) {
        self.previewSize = previewSize
        self.libraryWidth = libraryWidth
        self.pastePoints = pastePoints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        previewSize = try container.decodeIfPresent(Double.self, forKey: .previewSize) ?? 32
        libraryWidth = try container.decodeIfPresent(Double.self, forKey: .libraryWidth) ?? 300
        pastePoints = try container.decodeIfPresent(Double.self, forKey: .pastePoints) ?? 18
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(previewSize, forKey: .previewSize)
        try container.encode(libraryWidth, forKey: .libraryWidth)
        try container.encode(pastePoints, forKey: .pastePoints)
    }
}

struct LibraryFile: Codable {
    var version: Int
    var draft: Draft
    var settings: Settings
    var formulas: [Formula]
}

private struct ExampleFile: Codable {
    var id: String
    var name: String
    var tag: String
    var note: String
    var latex: String
}

enum LibraryStore {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("公式台", isDirectory: true)
    }

    static var fileURL: URL {
        folder.appendingPathComponent("library.json")
    }

    static func loadOrCreate() -> (LibraryFile, String?) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return (emptyFile(), "没法创建公式库文件夹。")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let seeded = (try? makeSeeded()) ?? emptyFile()
            try? write(seeded)
            return (seeded, nil)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return (try JSONDecoder().decode(LibraryFile.self, from: data), nil)
        } catch {
            let broken = folder.appendingPathComponent("library-broken-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: broken)
            let seeded = (try? makeSeeded()) ?? emptyFile()
            try? write(seeded)
            return (seeded, "原来的公式库读不了，已保留为 \(broken.lastPathComponent)。这次先打开一份新的。")
        }
    }

    static func write(_ file: LibraryFile) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: fileURL, options: .atomic)
    }

    static func replace(data: Data) throws {
        let file = try JSONDecoder().decode(LibraryFile.self, from: data)
        guard file.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        try write(file)
    }

    static func merging(_ base: LibraryFile, with incoming: LibraryFile) -> LibraryFile {
        var file = base
        var positions = Dictionary(uniqueKeysWithValues: file.formulas.enumerated().map { ($1.id, $0) })
        for formula in incoming.formulas {
            if let index = positions[formula.id] {
                file.formulas[index] = formula
            } else {
                positions[formula.id] = file.formulas.count
                file.formulas.append(formula)
            }
        }
        return file
    }

    static func makeSeeded() throws -> LibraryFile {
        guard let url = Bundle.main.url(forResource: "examples", withExtension: "json") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let examples = try JSONDecoder().decode([ExampleFile].self, from: Data(contentsOf: url))
        guard !examples.isEmpty else { return emptyFile() }
        let now = Date().timeIntervalSince1970 * 1000
        let formulas = examples.enumerated().map { index, example in
            Formula(
                id: example.id,
                name: example.name,
                latex: example.latex,
                note: example.note,
                tag: example.tag,
                pinned: false,
                display: true,
                created: now + Double(index),
                updated: now + Double(index)
            )
        }
        let first = formulas[0]
        return LibraryFile(
            version: 1,
            draft: Draft(latex: first.latex, name: first.name, note: first.note, tag: first.tag, display: true, loadedId: first.id),
            settings: Settings(previewSize: 32, libraryWidth: 300),
            formulas: formulas
        )
    }

    static func emptyFile() -> LibraryFile {
        LibraryFile(
            version: 1,
            draft: Draft(latex: "", name: "", note: "", tag: "", display: true, loadedId: nil),
            settings: Settings(previewSize: 32, libraryWidth: 300),
            formulas: []
        )
    }
}
