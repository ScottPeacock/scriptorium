#!/usr/bin/env swift
// Renders the app icon so it is reproducible and reviewable as source rather
// than an opaque binary someone has to open a design tool to change.
//
//   swift Tools/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png

import AppKit
import CoreGraphics
import Foundation

let size = 1024.0
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-1024.png"

guard let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    // Opaque: App Store Connect rejects an app icon carrying an alpha
    // channel, even a fully-opaque one.
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(1) }

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let ink = rgb(30, 35, 60)
let inkDeep = rgb(11, 13, 26)
let parchment = rgb(246, 239, 223)
let parchmentShade = rgb(219, 209, 187)
let gold = rgb(203, 158, 76)
let goldDeep = rgb(168, 126, 55)

/// Background gradient, drawn before flipping so it reads top-left to
/// bottom-right on screen.
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [ink, inkDeep] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

// Flip to a top-left origin so the geometry below reads the way it looks.
context.translateBy(x: 0, y: size)
context.scaleBy(x: 1, y: -1)

let centre = size / 2
let gutterTop = size * 0.315
let gutterBottom = size * 0.735
let edgeInset = size * 0.155
let gutterGap = size * 0.016
/// How much the outer edges rise above the gutter, which is what makes it read
/// as an open book rather than two rectangles.
let fan = size * 0.070

/// One page, hinged at the centre gutter.
func page(mirrored: Bool) -> CGPath {
    let path = CGMutablePath()
    let sign: Double = mirrored ? -1 : 1
    let inner = centre + sign * gutterGap
    let edge = centre + sign * (centre - edgeInset)

    /// Interpolate between the gutter and the outer edge rather than doing
    /// signed arithmetic: `sign` moves the left page's handles the wrong way,
    /// which flattens one page and overshoots the other's corner.
    func across(_ t: Double) -> Double {
        inner + (edge - inner) * t
    }

    path.move(to: CGPoint(x: inner, y: gutterTop))
    // Top edge sweeps up toward the outer corner.
    path.addCurve(
        to: CGPoint(x: edge, y: gutterTop - fan),
        control1: CGPoint(x: across(0.40), y: gutterTop + fan * 0.28),
        control2: CGPoint(x: across(0.72), y: gutterTop - fan * 0.85)
    )
    path.addLine(to: CGPoint(x: edge, y: gutterBottom - fan))
    // Bottom edge mirrors it back down to the gutter.
    path.addCurve(
        to: CGPoint(x: inner, y: gutterBottom),
        control1: CGPoint(x: across(0.72), y: gutterBottom - fan * 0.85),
        control2: CGPoint(x: across(0.40), y: gutterBottom + fan * 0.28)
    )
    path.closeSubpath()
    return path
}

context.setShadow(
    offset: CGSize(width: 0, height: size * 0.014),
    blur: size * 0.055,
    color: rgb(0, 0, 0, 0.5)
)

// Left page sits slightly darker, which separates the two halves without
// needing an outline.
context.addPath(page(mirrored: true))
context.setFillColor(parchmentShade)
context.fillPath()

context.addPath(page(mirrored: false))
context.setFillColor(parchment)
context.fillPath()

context.setShadow(offset: .zero, blur: 0, color: nil)

/// The gutter: a soft shadow where the pages meet, rather than a hard line.
let gutterShadow = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [rgb(60, 50, 35, 0), rgb(60, 50, 35, 0.38), rgb(60, 50, 35, 0)] as CFArray,
    locations: [0, 0.5, 1]
)!
context.saveGState()
context.addPath(page(mirrored: true))
context.addPath(page(mirrored: false))
context.clip()
context.drawLinearGradient(
    gutterShadow,
    start: CGPoint(x: centre - size * 0.055, y: 0),
    end: CGPoint(x: centre + size * 0.055, y: 0),
    options: []
)
context.restoreGState()

// A ribbon marker hanging into the right-hand page: the one flash of colour,
// and the whole point of the app — keeping your place.
context.saveGState()
context.addPath(page(mirrored: false))
context.clip()

let ribbonWidth = size * 0.052
let ribbonX = centre + size * 0.125
let ribbonTop = gutterTop - fan * 0.55
let ribbonBottom = gutterBottom - fan * 0.42

context.setFillColor(gold)
context.move(to: CGPoint(x: ribbonX, y: ribbonTop))
context.addLine(to: CGPoint(x: ribbonX + ribbonWidth, y: ribbonTop))
context.addLine(to: CGPoint(x: ribbonX + ribbonWidth, y: ribbonBottom))
// The notched tail that makes a ribbon read as a ribbon.
context.addLine(to: CGPoint(x: ribbonX + ribbonWidth / 2, y: ribbonBottom - size * 0.038))
context.addLine(to: CGPoint(x: ribbonX, y: ribbonBottom))
context.closePath()
context.fillPath()

// A darker edge along one side gives the ribbon a fold.
context.setFillColor(goldDeep)
context.fill(CGRect(
    x: ribbonX,
    y: ribbonTop,
    width: ribbonWidth * 0.28,
    height: ribbonBottom - ribbonTop - size * 0.004
))
context.restoreGState()

guard let image = context.makeImage() else { exit(1) }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
