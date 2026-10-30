import AppKit

enum Clipboard {
    static func copyText(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    static func copyMathML(_ mathml: String) {
        let html = "<html><body><!--StartFragment-->\(mathml)<!--EndFragment--></body></html>"
        let board = NSPasteboard.general
        board.clearContents()
        board.declareTypes([.string, .html], owner: nil)
        board.setString(mathml, forType: .string)
        board.setString(html, forType: .html)
    }

    static func copyOfficeHTML(_ html: String) {
        let board = NSPasteboard.general
        board.clearContents()
        let appleHTML = NSPasteboard.PasteboardType("Apple HTML pasteboard type")
        board.declareTypes([.html, appleHTML], owner: nil)
        board.setString(html, forType: .html)
        board.setString(html, forType: appleHTML)
    }

    static func copyImage(png: Data, pointSize: NSSize, pixels: NSSize) {
        let board = NSPasteboard.general
        board.clearContents()
        board.declareTypes([.png, .rtf], owner: nil)
        board.setData(png, forType: .png)
        board.setData(rtfPicture(png: png, pointSize: pointSize, pixels: pixels), forType: .rtf)
    }

    private static func rtfPicture(png: Data, pointSize: NSSize, pixels: NSSize) -> Data {
        let twipsW = max(1, Int((pointSize.width * 20).rounded()))
        let twipsH = max(1, Int((pointSize.height * 20).rounded()))
        let pixelW = max(1, Int(pixels.width.rounded()))
        let pixelH = max(1, Int(pixels.height.rounded()))
        var hex = ""
        hex.reserveCapacity(png.count * 2)
        for byte in png {
            hex.append(String(format: "%02X", byte))
        }
        var wrapped = ""
        wrapped.reserveCapacity(hex.count + hex.count / 64)
        for (index, character) in hex.enumerated() {
            if index > 0 && index % 128 == 0 { wrapped.append("\n") }
            wrapped.append(character)
        }
        let rtf = "{\\rtf1\\ansi{\\pict\\pngblip\\picw\(pixelW)\\pich\(pixelH)\\picwgoal\(twipsW)\\pichgoal\(twipsH) \(wrapped)}}"
        return Data(rtf.utf8)
    }
}

struct RenderedImage {
    var png: Data
    var pointSize: NSSize
    var pixels: NSSize
}
