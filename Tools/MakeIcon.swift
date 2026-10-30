import AppKit

let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    let ground = NSBezierPath(roundedRect: rect.insetBy(dx: 64, dy: 64), xRadius: 220, yRadius: 220)
    NSColor(srgbRed: 0.165, green: 0.129, blue: 0.094, alpha: 1).setFill()
    ground.fill()

    let paper = NSBezierPath(roundedRect: rect.insetBy(dx: 168, dy: 196), xRadius: 72, yRadius: 72)
    NSColor(srgbRed: 0.953, green: 0.933, blue: 0.894, alpha: 1).setFill()
    paper.fill()

    let ink = NSColor(srgbRed: 0.141, green: 0.110, blue: 0.086, alpha: 1)
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: 300, y: 560, width: 250, height: 64), xRadius: 18, yRadius: 18).fill()
    NSBezierPath(roundedRect: NSRect(x: 250, y: 488, width: 524, height: 36), xRadius: 10, yRadius: 10).fill()
    NSBezierPath(roundedRect: NSRect(x: 330, y: 392, width: 300, height: 64), xRadius: 18, yRadius: 18).fill()

    let seal = NSBezierPath(ovalIn: NSRect(x: 690, y: 250, width: 168, height: 168))
    NSColor(srgbRed: 0.761, green: 0.294, blue: 0.196, alpha: 1).setFill()
    seal.fill()
    NSColor(srgbRed: 0.98, green: 0.94, blue: 0.90, alpha: 1).setStroke()
    let mark = NSBezierPath()
    mark.lineWidth = 16
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    mark.move(to: NSPoint(x: 742, y: 318))
    mark.line(to: NSPoint(x: 786, y: 300))
    mark.line(to: NSPoint(x: 804, y: 360))
    mark.stroke()
    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("无法生成图标\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
