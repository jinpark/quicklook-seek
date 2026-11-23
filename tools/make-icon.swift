// Renders the app icon and builds Resources/AppIcon.icns.
//   swift tools/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func render(to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824pt body centered in 1024, continuous-ish corners.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    shape.fill()
    ctx.restoreGState()

    // Background gradient.
    NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.58, blue: 1.00, alpha: 1),
                        NSColor(srgbRed: 0.24, green: 0.27, blue: 0.85, alpha: 1)])!
        .draw(in: shape, angle: -90)

    // Soft highlight on the top half.
    ctx.saveGState()
    shape.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    ctx.restoreGState()

    func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, center: CGPoint) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
            .withSymbolConfiguration(config)!
        let size = image.size
        image.draw(in: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height))
    }

    // Circular "skip forward" arrow with a play triangle inside.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16,
                  color: NSColor.black.withAlphaComponent(0.25).cgColor)
    symbol("goforward", pointSize: 470, weight: .semibold, center: CGPoint(x: 512, y: 520))
    symbol("play.fill", pointSize: 190, weight: .bold, center: CGPoint(x: 530, y: 500))
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let work = FileManager.default.temporaryDirectory.appendingPathComponent("quicklookseek-icon-\(getpid())")
let iconset = work.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = work.appendingPathComponent("icon-1024.png")
try render(to: master)

func run(_ tool: String, _ args: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: tool, code: Int(process.terminationStatus)) }
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        let px = size * scale
        try run("/usr/bin/sips", ["-z", "\(px)", "\(px)", master.path, "--out", iconset.appendingPathComponent(name).path])
    }
}

let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path])
try? FileManager.default.removeItem(at: resources.appendingPathComponent("AppIcon-1024.png"))
try FileManager.default.copyItem(at: master, to: resources.appendingPathComponent("AppIcon-1024.png"))
try? FileManager.default.removeItem(at: work)
print("Wrote Resources/AppIcon.icns and Resources/AppIcon-1024.png")
