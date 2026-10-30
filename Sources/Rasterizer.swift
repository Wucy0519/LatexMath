import AppKit
import WebKit

enum RasterError: LocalizedError {
    case failed(String)
    case blank
    case encode

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        case .blank: return "生成的图片是空白的"
        case .encode: return "图片没有写出来"
        }
    }
}

final class QuietWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FormulaRasterizer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let window: QuietWindow
    private var ready = false
    private var queue: [(String, Bool, String, (Result<RenderedImage, Error>) -> Void)] = []
    private var working = false

    override init() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 240), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        window = QuietWindow(
            contentRect: NSRect(x: -8000, y: -8000, width: 800, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        super.init()
        webView.navigationDelegate = self
        window.contentView = webView
        window.orderFrontRegardless()
        if let url = Bundle.main.url(forResource: "render", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func render(latex: String, display: Bool, appearance: String, completion: @escaping (Result<RenderedImage, Error>) -> Void) {
        queue.append((latex, display, appearance, completion))
        pump()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        pump()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failAll(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failAll(error)
    }

    private func failAll(_ error: Error) {
        let pending = queue
        queue.removeAll()
        working = false
        for item in pending { item.3(.failure(error)) }
    }

    private func pump() {
        guard ready, !working, !queue.isEmpty else { return }
        working = true
        let job = queue.removeFirst()
        let payload: [String: Any] = ["latex": job.0, "display": job.1, "appearance": job.2]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            job.3(.failure(RasterError.failed("公式内容没法送去排版")))
            working = false
            pump()
            return
        }
        webView.evaluateJavaScript("renderFormula(\(json))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                job.3(.failure(RasterError.failed(error.localizedDescription)))
                self.working = false
                self.pump()
                return
            }
            self.waitForRender(job: job, attempt: 0)
        }
    }

    private func waitForRender(job: (String, Bool, String, (Result<RenderedImage, Error>) -> Void), attempt: Int) {
        webView.evaluateJavaScript("window.__renderResult") { [weak self] result, error in
            guard let self else { return }
            if let error {
                job.3(.failure(RasterError.failed(error.localizedDescription)))
                self.working = false
                self.pump()
                return
            }
            let text = result as? String ?? ""
            if text.isEmpty {
                if attempt > 80 {
                    job.3(.failure(RasterError.failed("公式排版超时")))
                    self.working = false
                    self.pump()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.waitForRender(job: job, attempt: attempt + 1)
                    }
                }
                return
            }
            guard let data = text.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                job.3(.failure(RasterError.failed("没有量到公式的大小")))
                self.working = false
                self.pump()
                return
            }
            if let message = dict["error"] as? String {
                job.3(.failure(RasterError.failed(message)))
                self.working = false
                self.pump()
                return
            }
            guard let width = (dict["width"] as? NSNumber)?.doubleValue,
                  let height = (dict["height"] as? NSNumber)?.doubleValue,
                  width > 1, height > 1 else {
                job.3(.failure(RasterError.failed("没有量到公式的大小")))
                self.working = false
                self.pump()
                return
            }
            let size = NSSize(width: CGFloat(width), height: CGFloat(height))
            self.window.setContentSize(size)
            self.webView.frame = NSRect(origin: .zero, size: size)
            DispatchQueue.main.async {
                self.capture(job: job, pointSize: size)
            }
        }
    }

    private func capture(job: (String, Bool, String, (Result<RenderedImage, Error>) -> Void), pointSize: NSSize) {
        let appearance = job.2
        if appearance == "paper" {
            takeSnapshot(pointSize: pointSize) { [weak self] result in
                self?.finish(job: job, pointSize: pointSize, result: result, expectInk: true)
            }
            return
        }
        matte(pointSize: pointSize, chalk: appearance == "chalk") { [weak self] result in
            self?.finish(job: job, pointSize: pointSize, result: result, expectInk: true)
        }
    }

    private func finish(job: (String, Bool, String, (Result<RenderedImage, Error>) -> Void), pointSize: NSSize, result: Result<NSImage, Error>, expectInk: Bool) {
        defer {
            working = false
            pump()
        }
        switch result {
        case .failure(let error):
            job.3(.failure(error))
        case .success(let image):
            if expectInk && mostlyBlank(image, chalk: job.2 == "chalk") {
                job.3(.failure(RasterError.blank))
                return
            }
            guard let encoded = pngData(from: image, pointSize: pointSize) else {
                job.3(.failure(RasterError.encode))
                return
            }
            let pixels = NSSize(width: encoded.pixels.width, height: encoded.pixels.height)
            job.3(.success(RenderedImage(png: encoded.data, pointSize: pointSize, pixels: pixels)))
        }
    }

    private func takeSnapshot(pointSize: NSSize, completion: @escaping (Result<NSImage, Error>) -> Void) {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        config.snapshotWidth = NSNumber(value: Double(pointSize.width * 2))
        webView.takeSnapshot(with: config) { image, error in
            if let image {
                completion(.success(image))
            } else {
                completion(.failure(error ?? RasterError.failed("截图失败")))
            }
        }
    }

    private func matte(pointSize: NSSize, chalk: Bool, completion: @escaping (Result<NSImage, Error>) -> Void) {
        webView.evaluateJavaScript("setMatte('black')") { [weak self] _, error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }
            self.takeSnapshot(pointSize: pointSize) { blackResult in
                switch blackResult {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let blackImage):
                    self.webView.evaluateJavaScript("setMatte('white')") { _, error in
                        if let error {
                            completion(.failure(error))
                            return
                        }
                        self.takeSnapshot(pointSize: pointSize) { whiteResult in
                            switch whiteResult {
                            case .failure(let error):
                                completion(.failure(error))
                            case .success(let whiteImage):
                                if let image = Self.composite(white: whiteImage, black: blackImage, chalk: chalk) {
                                    completion(.success(image))
                                } else {
                                    completion(.failure(RasterError.failed("透明底没有合成出来")))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func composite(white: NSImage, black: NSImage, chalk: Bool) -> NSImage? {
        guard let whiteRep = bitmap(white), let blackRep = bitmap(black) else { return nil }
        guard whiteRep.pixelsWide == blackRep.pixelsWide, whiteRep.pixelsHigh == blackRep.pixelsHigh else { return nil }
        let width = whiteRep.pixelsWide
        let height = whiteRep.pixelsHigh
        guard let output = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else { return nil }
        for y in 0..<height {
            for x in 0..<width {
                guard let wc = whiteRep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let bc = blackRep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                var wr: CGFloat = 0, wg: CGFloat = 0, wb: CGFloat = 0, wa: CGFloat = 0
                var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
                wc.getRed(&wr, green: &wg, blue: &wb, alpha: &wa)
                bc.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
                let diff = (Double(wr - br) + Double(wg - bg) + Double(wb - bb)) / 3
                let alpha = min(1, max(0, 1 - diff))
                let red: Double
                let green: Double
                let blue: Double
                if alpha > 0.004 {
                    red = min(1, Double(br) / alpha)
                    green = min(1, Double(bg) / alpha)
                    blue = min(1, Double(bb) / alpha)
                } else {
                    red = 0
                    green = 0
                    blue = 0
                }
                let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
                output.setColor(color, atX: x, y: y)
            }
        }
        _ = chalk
        output.size = white.size
        let image = NSImage(size: white.size)
        image.addRepresentation(output)
        return image
    }

    private static func bitmap(_ image: NSImage) -> NSBitmapImageRep? {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first { return rep }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    private func mostlyBlank(_ image: NSImage, chalk: Bool) -> Bool {
        guard let rep = Self.bitmap(image) else { return true }
        let stepX = max(1, rep.pixelsWide / 48)
        let stepY = max(1, rep.pixelsHigh / 32)
        var ink = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                if a < 0.15 { continue }
                let sum = r + g + b
                if chalk {
                    if sum > 1.6 { ink += 1 }
                } else if sum < 2.4 {
                    ink += 1
                }
            }
        }
        return ink < 4
    }

    private func pngData(from image: NSImage, pointSize: NSSize) -> (data: Data, pixels: NSSize)? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        rep.size = pointSize
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return (data, NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    }
}
