import AppKit
import Foundation

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = projectRoot.appendingPathComponent("Resources", isDirectory: true)
let swiftPackageResources = projectRoot.appendingPathComponent("Sources/iTelAS/Resources", isDirectory: true)
let previewDirectory = projectRoot.appendingPathComponent("Design/Previews", isDirectory: true)
let assetCatalog = resources.appendingPathComponent("Assets.xcassets", isDirectory: true)
let appIconSet = assetCatalog.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let temporaryRoot = URL(fileURLWithPath: "/tmp/itelas-brand-assets", isDirectory: true)
let iconset = temporaryRoot.appendingPathComponent("iTelAS.iconset", isDirectory: true)

try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: swiftPackageResources, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func chamferedPath(_ rect: CGRect, cut: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
    path.line(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
    path.line(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
    path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
    path.line(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
    path.line(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
    path.line(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
    path.line(to: CGPoint(x: rect.minX, y: rect.minY + cut))
    path.close()
    return path
}

func renderIcon(size: Int) -> Data {
    let dimension = CGFloat(size)
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
        fatalError("Could not create the iTelAS icon canvas.")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }
    graphicsContext.imageInterpolation = .high
    let canvas = CGRect(x: 0, y: 0, width: dimension, height: dimension)
    NSColor.clear.setFill()
    canvas.fill()

    let outer = canvas.insetBy(dx: dimension * 0.055, dy: dimension * 0.055)
    let outerPath = NSBezierPath(roundedRect: outer, xRadius: dimension * 0.19, yRadius: dimension * 0.19)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
    shadow.shadowBlurRadius = dimension * 0.055
    shadow.shadowOffset = NSSize(width: 0, height: -dimension * 0.025)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.035, green: 0.054, blue: 0.071, alpha: 1).setFill()
    outerPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.075, green: 0.115, blue: 0.15, alpha: 1),
        NSColor(calibratedRed: 0.026, green: 0.047, blue: 0.063, alpha: 1)
    ])!
    gradient.draw(in: outerPath, angle: -58)

    let plate = outer.insetBy(dx: dimension * 0.13, dy: dimension * 0.13)
    let platePath = chamferedPath(plate, cut: dimension * 0.075)
    NSColor(calibratedRed: 0.028, green: 0.066, blue: 0.081, alpha: 0.96).setFill()
    platePath.fill()
    NSColor(calibratedRed: 0.08, green: 0.48, blue: 0.91, alpha: 0.9).setStroke()
    platePath.lineWidth = max(1, dimension * 0.009)
    platePath.stroke()

    NSGraphicsContext.saveGraphicsState()
    platePath.addClip()
    NSColor.white.withAlphaComponent(0.075).setStroke()
    let grid = NSBezierPath()
    grid.lineWidth = max(0.5, dimension * 0.0022)
    for step in 1...4 {
        let fraction = CGFloat(step) / 5
        let x = plate.minX + plate.width * fraction
        grid.move(to: CGPoint(x: x, y: plate.minY))
        grid.line(to: CGPoint(x: x, y: plate.maxY))
        let y = plate.minY + plate.height * fraction
        grid.move(to: CGPoint(x: plate.minX, y: y))
        grid.line(to: CGPoint(x: plate.maxX, y: y))
    }
    grid.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let whitePath = NSBezierPath()
    whitePath.lineCapStyle = .square
    whitePath.lineJoinStyle = .miter
    whitePath.lineWidth = max(3, dimension * 0.055)
    whitePath.move(to: CGPoint(x: plate.minX + plate.width * 0.25, y: plate.maxY - plate.height * 0.22))
    whitePath.line(to: CGPoint(x: plate.minX + plate.width * 0.25, y: plate.minY + plate.height * 0.22))
    whitePath.line(to: CGPoint(x: plate.minX + plate.width * 0.46, y: plate.minY + plate.height * 0.22))
    NSColor.white.withAlphaComponent(0.96).setStroke()
    whitePath.stroke()

    let greenPath = NSBezierPath()
    greenPath.lineCapStyle = .square
    greenPath.lineJoinStyle = .miter
    greenPath.lineWidth = whitePath.lineWidth
    greenPath.move(to: CGPoint(x: plate.minX + plate.width * 0.44, y: plate.maxY - plate.height * 0.24))
    greenPath.line(to: CGPoint(x: plate.minX + plate.width * 0.78, y: plate.maxY - plate.height * 0.24))
    greenPath.line(to: CGPoint(x: plate.minX + plate.width * 0.78, y: plate.minY + plate.height * 0.43))
    greenPath.line(to: CGPoint(x: plate.minX + plate.width * 0.58, y: plate.minY + plate.height * 0.43))
    NSColor(calibratedRed: 0.42, green: 0.96, blue: 0.60, alpha: 1).setStroke()
    greenPath.stroke()

    let nodeSize = dimension * 0.085
    let blueNode = CGRect(
        x: plate.minX + plate.width * 0.25 - nodeSize / 2,
        y: plate.maxY - plate.height * 0.22 - nodeSize / 2,
        width: nodeSize,
        height: nodeSize
    )
    NSColor(calibratedRed: 0.08, green: 0.48, blue: 0.91, alpha: 1).setFill()
    blueNode.fill()

    let cursorNode = CGRect(
        x: plate.minX + plate.width * 0.78 - nodeSize / 2,
        y: plate.minY + plate.height * 0.43 - nodeSize / 2,
        width: nodeSize,
        height: nodeSize
    )
    NSColor.white.setFill()
    cursorNode.fill()

    NSColor(calibratedRed: 0.42, green: 0.96, blue: 0.60, alpha: 0.8).setFill()
    CGRect(x: plate.minX, y: plate.minY + dimension * 0.055, width: dimension * 0.055, height: dimension * 0.012).fill()
    NSColor.white.withAlphaComponent(0.36).setFill()
    CGRect(x: plate.maxX - dimension * 0.09, y: plate.maxY - dimension * 0.065, width: dimension * 0.09, height: dimension * 0.008).fill()

    graphicsContext.flushGraphics()
    guard let png = representation.representation(using: .png, properties: [:]) else {
        fatalError("Could not render the iTelAS brand mark.")
    }
    return png
}

let master = renderIcon(size: 1_024)
try master.write(to: resources.appendingPathComponent("iTelASIcon.png"), options: .atomic)
try master.write(to: swiftPackageResources.appendingPathComponent("iTelASIcon.png"), options: .atomic)
try master.write(to: previewDirectory.appendingPathComponent("iTelAS-brand-mark.png"), options: .atomic)

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1_024)
]
for (name, size) in iconFiles {
    let renderedIcon = renderIcon(size: size)
    try renderedIcon.write(to: iconset.appendingPathComponent(name), options: .atomic)
    try renderedIcon.write(to: appIconSet.appendingPathComponent(name), options: .atomic)
}

let appIconContents = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try Data(appIconContents.utf8).write(
    to: appIconSet.appendingPathComponent("Contents.json"),
    options: .atomic
)

let iconCompiler = Process()
iconCompiler.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconCompiler.arguments = [
    "--convert", "icns",
    "--output", resources.appendingPathComponent("iTelAS.icns").path,
    iconset.path
]
try iconCompiler.run()
iconCompiler.waitUntilExit()
guard iconCompiler.terminationReason == .exit, iconCompiler.terminationStatus == 0 else {
    fatalError("iconutil could not compile the complete Retina iconset.")
}

print(iconset.path)
