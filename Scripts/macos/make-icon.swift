import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let fileManager = FileManager.default
let iconsetURL = URL(fileURLWithPath: "build/AppIcon.iconset", isDirectory: true)
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: size, height: size)
guard let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("context") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let full = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.clear.setFill()
full.fill()

let iconRect = full.insetBy(dx: 34, dy: 34)
let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 216, yRadius: 216)

iconPath.addClip()
let background = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.18, alpha: 1), 0.0),
    (NSColor(calibratedRed: 0.035, green: 0.20, blue: 0.28, alpha: 1), 0.52),
    (NSColor(calibratedRed: 0.05, green: 0.36, blue: 0.36, alpha: 1), 1.0)
)!
background.draw(in: iconPath, angle: -42)

let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.26, green: 0.96, blue: 0.78, alpha: 0.55),
    NSColor(calibratedRed: 0.26, green: 0.96, blue: 0.78, alpha: 0.0)
])!
let glowPath = NSBezierPath(ovalIn: NSRect(x: 470, y: 470, width: 720, height: 720))
glow.draw(in: glowPath, relativeCenterPosition: NSPoint(x: 0.1, y: 0.1))

let indigoGlow = NSGradient(colors: [
    NSColor(calibratedRed: 0.42, green: 0.47, blue: 1.0, alpha: 0.36),
    NSColor(calibratedRed: 0.42, green: 0.47, blue: 1.0, alpha: 0.0)
])!
let indigoPath = NSBezierPath(ovalIn: NSRect(x: -100, y: -80, width: 650, height: 650))
indigoGlow.draw(in: indigoPath, relativeCenterPosition: NSPoint(x: 0.0, y: 0.0))

// Fine highlight wash.
let sheen = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.12),
    NSColor.white.withAlphaComponent(0.0)
])!
sheen.draw(in: NSBezierPath(rect: NSRect(x: 34, y: 520, width: 956, height: 470)), angle: -90)

// Soft shadow under the cube.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 46
shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.set()
NSColor.black.withAlphaComponent(0.22).setFill()
NSBezierPath(ovalIn: NSRect(x: 260, y: 160, width: 504, height: 120)).fill()
NSGraphicsContext.restoreGraphicsState()

// Isometric box.
let topPoint = NSPoint(x: 512, y: 818)
let leftPoint = NSPoint(x: 238, y: 660)
let centerPoint = NSPoint(x: 512, y: 502)
let rightPoint = NSPoint(x: 786, y: 660)
let leftBottom = NSPoint(x: 238, y: 368)
let centerBottom = NSPoint(x: 512, y: 212)
let rightBottom = NSPoint(x: 786, y: 368)

func polygon(_ points: [NSPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.close()
    return path
}

let topFace = polygon([topPoint, rightPoint, centerPoint, leftPoint])
let leftFace = polygon([leftPoint, centerPoint, centerBottom, leftBottom])
let rightFace = polygon([rightPoint, rightBottom, centerBottom, centerPoint])

let topGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.55, green: 1.0, blue: 0.86, alpha: 1),
    NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.78, alpha: 1)
])!
topGradient.draw(in: topFace, angle: 35)

let leftGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.44, blue: 0.58, alpha: 1),
    NSColor(calibratedRed: 0.08, green: 0.20, blue: 0.40, alpha: 1)
])!
leftGradient.draw(in: leftFace, angle: -60)

let rightGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.32, blue: 0.56, alpha: 1),
    NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.46, alpha: 1)
])!
rightGradient.draw(in: rightFace, angle: -110)

for face in [topFace, leftFace, rightFace] {
    NSColor.white.withAlphaComponent(0.24).setStroke()
    face.lineWidth = 2.0
    face.stroke()
}

// Edge highlight.
let edge = NSBezierPath()
edge.move(to: topPoint)
edge.line(to: centerPoint)
edge.line(to: centerBottom)
edge.line(to: rightBottom)
edge.line(to: rightPoint)
edge.line(to: topPoint)
edge.lineWidth = 4
NSColor.white.withAlphaComponent(0.34).setStroke()
edge.stroke()

// Terminal prompt on the box.
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let promptShadow = NSShadow()
promptShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
promptShadow.shadowBlurRadius = 16
promptShadow.shadowOffset = NSSize(width: 0, height: -6)
let promptAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 162, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .shadow: promptShadow
]
let prompt = NSAttributedString(string: ">_", attributes: promptAttributes)
let promptSize = prompt.size()
prompt.draw(at: NSPoint(x: 512 - promptSize.width / 2, y: 318))

// Small status lights floating in the upper-right corner.
for (index, color) in [
    NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.35, alpha: 0.95),
    NSColor(calibratedRed: 0.35, green: 0.93, blue: 0.78, alpha: 0.95),
    NSColor(calibratedRed: 0.43, green: 0.49, blue: 1.0, alpha: 0.95)
].enumerated() {
    let dot = NSBezierPath(ovalIn: NSRect(x: 764 + CGFloat(index) * 30, y: 798, width: 15, height: 15))
    color.setFill()
    dot.fill()
}

// Crisp inner border.
let border = NSBezierPath(roundedRect: iconRect.insetBy(dx: 2, dy: 2), xRadius: 213, yRadius: 213)
NSColor.white.withAlphaComponent(0.18).setStroke()
border.lineWidth = 4
border.stroke()

NSGraphicsContext.restoreGraphicsState()

let masterURL = URL(fileURLWithPath: "build/AppIcon-1024.png")
try rep.representation(using: .png, properties: [:])!.write(to: masterURL)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in sizes {
    let destination = iconsetURL.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", String(pixels), String(pixels), masterURL.path, "--out", destination.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("sips failed for (name)") }
}

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let icnsURL = outputDirectory.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(icnsURL.path)")
