// AUTO-GENERATED ICON RENDERER — keep in sync with
// Ikeru/Views/Shared/Theme/IkeruLogo.swift and ColorExtensions.swift.
//
// Standalone macOS SwiftPM executable. Renders the Ikeru app icon as a
// fully-opaque 1024x1024 PNG into the main app's AppIcon.appiconset.
// Run with:  swift run --package-path scripts/AppIconGen

import SwiftUI
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Vendored geometry (mirrors IkeruLogo.swift — keep in sync!)

private enum Ikebana {
    static let pivot = CGPoint(x: 0.42, y: 0.86)
    static let bloomCenter = CGPoint(x: 0.60, y: 0.20)
}

struct IkebanaShinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        path.move(to: p(Ikebana.pivot.x, Ikebana.pivot.y))
        path.addCurve(
            to: p(0.34, 0.55),
            control1: p(0.46, 0.76),
            control2: p(0.34, 0.66)
        )
        path.addCurve(
            to: p(Ikebana.bloomCenter.x, Ikebana.bloomCenter.y),
            control1: p(0.34, 0.42),
            control2: p(0.54, 0.28)
        )
        return path
    }
}

struct IkebanaSoeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        path.move(to: p(Ikebana.pivot.x, Ikebana.pivot.y))
        path.addCurve(
            to: p(0.12, 0.38),
            control1: p(0.46, 0.62),
            control2: p(0.22, 0.40)
        )
        return path
    }
}

struct IkebanaHikaeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        path.move(to: p(Ikebana.pivot.x, Ikebana.pivot.y))
        path.addCurve(
            to: p(0.82, 0.74),
            control1: p(0.56, 0.94),
            control2: p(0.74, 0.86)
        )
        return path
    }
}

struct IkebanaLeafShape: Shape {
    let center: CGPoint
    let length: CGFloat
    let rotation: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let cx = rect.minX + w * center.x
        let cy = rect.minY + h * center.y
        let side = min(w, h)
        let len = side * length
        let thick = len * 0.32
        let cosR = CGFloat(cos(rotation))
        let sinR = CGFloat(sin(rotation))
        func tx(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            CGPoint(x: cx + lx * cosR - ly * sinR,
                    y: cy + lx * sinR + ly * cosR)
        }
        path.move(to: tx(-len / 2, 0))
        path.addQuadCurve(to: tx(len / 2, 0), control: tx(0, -thick))
        path.addQuadCurve(to: tx(-len / 2, 0), control: tx(0, thick))
        path.closeSubpath()
        return path
    }
}

struct IkebanaPetalShape: Shape {
    let angle: Double
    let length: CGFloat
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let side = min(w, h)
        let cx = rect.minX + w * Ikebana.bloomCenter.x
        let cy = rect.minY + h * Ikebana.bloomCenter.y
        let len = side * length
        let half = len * width * 0.5
        let cosA = CGFloat(cos(angle))
        let sinA = CGFloat(sin(angle))
        func tx(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            CGPoint(x: cx + lx * cosA - ly * sinA,
                    y: cy + lx * sinA + ly * cosA)
        }
        path.move(to: tx(0, 0))
        path.addCurve(
            to: tx(len, 0),
            control1: tx(len * 0.15, -half),
            control2: tx(len * 0.85, -half * 0.9)
        )
        path.addCurve(
            to: tx(0, 0),
            control1: tx(len * 0.85, half * 0.9),
            control2: tx(len * 0.15, half)
        )
        path.closeSubpath()
        return path
    }
}

struct BloomCenter: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let side = min(w, h)
        let r = side * 0.035
        let c = CGPoint(
            x: rect.minX + w * Ikebana.bloomCenter.x,
            y: rect.minY + h * Ikebana.bloomCenter.y
        )
        return Path(ellipseIn: CGRect(
            x: c.x - r, y: c.y - r, width: r * 2, height: r * 2
        ))
    }
}

private struct PetalSpec {
    let angle: Double
    let length: CGFloat
    let width: CGFloat
}

private let petalSpecs: [PetalSpec] = [
    PetalSpec(angle: -.pi * 0.95, length: 0.18, width: 0.55),
    PetalSpec(angle: -.pi * 0.70, length: 0.22, width: 0.60),
    PetalSpec(angle: -.pi * 0.48, length: 0.24, width: 0.62),
    PetalSpec(angle: -.pi * 0.25, length: 0.21, width: 0.58),
    PetalSpec(angle: -.pi * 0.02, length: 0.18, width: 0.54),
    PetalSpec(angle:  .pi * 0.25, length: 0.15, width: 0.50)
]

private let leafSpecs: [IkebanaLeafShape] = [
    IkebanaLeafShape(
        center: CGPoint(x: 0.51, y: 0.58),
        length: 0.20,
        rotation: -Double.pi / 3.5
    ),
    IkebanaLeafShape(
        center: CGPoint(x: 0.22, y: 0.55),
        length: 0.17,
        rotation: -Double.pi * 0.62
    )
]

// MARK: - Colors (mirrors ColorExtensions.swift)

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

private let goldAccent = Color(hex: 0xD4A574)

private let heroWarm = LinearGradient(
    colors: [Color(hex: 0x1A1218), Color(hex: 0x0F0D14), Color(hex: 0x0A0A0F)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

// MARK: - Logo view (vendored, tuned for icon — fully drawn, no animation)

struct IkeruLogoView: View {
    var strokeScale: CGFloat = 0.060
    var tint: Color = goldAccent

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let baseWidth = side * strokeScale
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: side * 0.045, height: side * 0.045)
                    .position(
                        x: side * Ikebana.pivot.x,
                        y: side * Ikebana.pivot.y
                    )
                strokes(baseWidth: baseWidth, bleed: true)
                    .blur(radius: baseWidth * 1.4)
                    .opacity(0.4)
                strokes(baseWidth: baseWidth, bleed: false)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func strokes(baseWidth: CGFloat, bleed: Bool) -> some View {
        let shinWidth  = baseWidth * 0.95
        let soeWidth   = baseWidth * 0.72
        let hikaeWidth = baseWidth * 0.55
        let widthMul: CGFloat = bleed ? 1.6 : 1.0

        ZStack {
            IkebanaShinShape()
                .stroke(tint, style: StrokeStyle(
                    lineWidth: shinWidth * widthMul,
                    lineCap: .round, lineJoin: .round))
            IkebanaSoeShape()
                .stroke(tint, style: StrokeStyle(
                    lineWidth: soeWidth * widthMul,
                    lineCap: .round, lineJoin: .round))
            IkebanaHikaeShape()
                .stroke(tint, style: StrokeStyle(
                    lineWidth: hikaeWidth * widthMul,
                    lineCap: .round, lineJoin: .round))
            ForEach(Array(leafSpecs.enumerated()), id: \.offset) { _, leaf in
                leaf.fill(tint)
            }
            ForEach(Array(petalSpecs.enumerated()), id: \.offset) { _, spec in
                IkebanaPetalShape(angle: spec.angle, length: spec.length, width: spec.width)
                    .fill(tint)
            }
            BloomCenter()
                .fill(tint.opacity(0.95))
        }
    }
}

// MARK: - Icon composition

struct AppIconView: View {
    var body: some View {
        ZStack {
            // Fully opaque warm-dark background.
            heroWarm
            // Soft warm radial glow behind the logo for depth.
            RadialGradient(
                colors: [
                    Color(hex: 0xD4A574, opacity: 0.22),
                    Color(hex: 0xD4A574, opacity: 0.0)
                ],
                center: UnitPoint(x: 0.58, y: 0.42),
                startRadius: 40,
                endRadius: 620
            )
            // Logo, padded so it fills ~65% of the canvas.
            IkeruLogoView()
                .padding(180)
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - Render

@MainActor
func render() throws {
    let renderer = ImageRenderer(content: AppIconView())
    renderer.proposedSize = ProposedViewSize(width: 1024, height: 1024)
    renderer.scale = 1.0
    renderer.isOpaque = true

    guard let cgImage = renderer.cgImage else {
        throw NSError(domain: "AppIconGen", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "ImageRenderer returned nil"])
    }

    // Composite onto an opaque sRGB context to strip any alpha channel.
    let width = 1024, height = 1024
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw NSError(domain: "AppIconGen", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "CGContext creation failed"])
    }
    ctx.setFillColor(CGColor(srgbRed: 0x1A / 255.0, green: 0x12 / 255.0, blue: 0x18 / 255.0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let finalImage = ctx.makeImage() else {
        throw NSError(domain: "AppIconGen", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Context makeImage failed"])
    }

    let fm = FileManager.default
    var candidate = URL(fileURLWithPath: fm.currentDirectoryPath)
    var outURL: URL?
    for _ in 0..<6 {
        let probe = candidate
            .appendingPathComponent("Ikeru/Resources/Assets.xcassets/AppIcon.appiconset")
        if fm.fileExists(atPath: probe.path) {
            outURL = probe.appendingPathComponent("AppIcon.png")
            break
        }
        candidate = candidate.deletingLastPathComponent()
    }
    guard let outURL else {
        throw NSError(domain: "AppIconGen", code: 6,
                      userInfo: [NSLocalizedDescriptionKey: "AppIcon.appiconset not found from \(fm.currentDirectoryPath)"])
    }
    print("Resolved output: \(outURL.path)")

    guard let dest = CGImageDestinationCreateWithURL(
        outURL as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw NSError(domain: "AppIconGen", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "CGImageDestination failed"])
    }
    CGImageDestinationAddImage(dest, finalImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "AppIconGen", code: 5,
                      userInfo: [NSLocalizedDescriptionKey: "PNG finalize failed"])
    }
    print("Wrote \(outURL.path)")
}

do {
    try MainActor.assumeIsolated { try render() }
} catch {
    FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
