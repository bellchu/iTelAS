#!/usr/bin/swift

import AppKit
import Darwin
import Foundation

private enum IconVerificationError: LocalizedError {
    case usage
    case unreadable(String)
    case missingRepresentations([Int])
    case blank(String)
    case flat(String)
    case missingTransparentCorners(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: verify-app-icon.swift <master-png> <fallback-icns>"
        case .unreadable(let path):
            "AppKit could not decode the packaged icon at \(path)."
        case .missingRepresentations(let sizes):
            "The fallback ICNS is missing required pixel representations: \(sizes)."
        case .blank(let label):
            "The \(label) renders with too little visible content and may appear blank."
        case .flat(let label):
            "The \(label) lacks sufficient color or luminance variation and may be a placeholder."
        case .missingTransparentCorners(let label):
            "The \(label) has no transparent corner margin; the intended macOS icon silhouette was lost."
        }
    }
}

private struct RenderStatistics {
    let visibleFraction: Double
    let transparentFraction: Double
    let colorBucketCount: Int
    let luminanceRange: Double
}

private func renderStatistics(for image: NSImage, label: String) throws -> RenderStatistics {
    let side = 256
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconVerificationError.unreadable(label)
    }

    bitmap.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: side, height: side))
    image.draw(
        in: NSRect(x: 0, y: 0, width: side, height: side),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    var visiblePixels = 0
    var transparentPixels = 0
    var colorBuckets: Set<Int> = []
    var minimumLuminance = 1.0
    var maximumLuminance = 0.0

    for y in 0..<side {
        for x in 0..<side {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            if color.alphaComponent < 0.04 {
                transparentPixels += 1
                continue
            }

            visiblePixels += 1
            let red = color.redComponent
            let green = color.greenComponent
            let blue = color.blueComponent
            let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
            minimumLuminance = min(minimumLuminance, luminance)
            maximumLuminance = max(maximumLuminance, luminance)

            let bucket = (Int(red * 15) << 8) | (Int(green * 15) << 4) | Int(blue * 15)
            colorBuckets.insert(bucket)
        }
    }

    let totalPixels = Double(side * side)
    let statistics = RenderStatistics(
        visibleFraction: Double(visiblePixels) / totalPixels,
        transparentFraction: Double(transparentPixels) / totalPixels,
        colorBucketCount: colorBuckets.count,
        luminanceRange: maximumLuminance - minimumLuminance
    )

    guard statistics.visibleFraction > 0.50 else {
        throw IconVerificationError.blank(label)
    }
    guard statistics.colorBucketCount >= 12, statistics.luminanceRange > 0.40 else {
        throw IconVerificationError.flat(label)
    }
    guard statistics.transparentFraction > 0.02 else {
        throw IconVerificationError.missingTransparentCorners(label)
    }
    return statistics
}

private func printStatistics(_ statistics: RenderStatistics, label: String) {
    print(String(
        format: "Verified %@: %.1f%% visible, %.1f%% transparent, %d color buckets, %.2f luminance range",
        label,
        statistics.visibleFraction * 100,
        statistics.transparentFraction * 100,
        statistics.colorBucketCount,
        statistics.luminanceRange
    ))
}

do {
    guard CommandLine.arguments.count == 3 else { throw IconVerificationError.usage }
    let pngPath = CommandLine.arguments[1]
    let icnsPath = CommandLine.arguments[2]
    guard let png = NSImage(contentsOfFile: pngPath) else {
        throw IconVerificationError.unreadable(pngPath)
    }
    guard let icns = NSImage(contentsOfFile: icnsPath) else {
        throw IconVerificationError.unreadable(icnsPath)
    }

    let requiredSizes: Set<Int> = [16, 32, 64, 128, 256, 512, 1_024]
    let availableSizes = Set(icns.representations.map(\.pixelsWide))
    let missingSizes = requiredSizes.subtracting(availableSizes).sorted()
    guard missingSizes.isEmpty else {
        throw IconVerificationError.missingRepresentations(missingSizes)
    }

    printStatistics(try renderStatistics(for: png, label: "runtime PNG"), label: "runtime PNG")
    printStatistics(try renderStatistics(for: icns, label: "fallback ICNS"), label: "fallback ICNS")
} catch {
    let message = "App icon verification failed: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
