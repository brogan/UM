import Foundation
import CoreGraphics
import ImageIO

// Proportions measured from Loom.app icon (1024×1024 reference)
let outerBorderFraction = 0.044   // ~45px at 1024
let innerInsetFraction  = 0.225   // ~230px at 1024
let innerBorderFraction = 0.052   // ~53px at 1024

func generateUMIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let outer  = s * outerBorderFraction
    let inset  = s * innerInsetFraction
    let border = s * innerBorderFraction

    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
                   | CGBitmapInfo.byteOrder32Little.rawValue
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: bitmapInfo) else { fatalError("ctx") }

    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

    // Outer border: black fill, then white punch-out
    ctx.setFillColor(black)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    ctx.setFillColor(white)
    ctx.fill(CGRect(x: outer, y: outer, width: s - 2*outer, height: s - 2*outer))

    // Inner rectangle: black fill, then white interior
    ctx.setFillColor(black)
    ctx.fill(CGRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset))
    let interior = inset + border
    ctx.setFillColor(white)
    ctx.fill(CGRect(x: interior, y: interior, width: s - 2*interior, height: s - 2*interior))

    // 2×2 grid: horizontal + vertical center lines (same thickness as inner border)
    let mid = s / 2
    ctx.setFillColor(black)
    // Horizontal
    ctx.fill(CGRect(x: interior, y: mid - border/2, width: s - 2*interior, height: border))
    // Vertical
    ctx.fill(CGRect(x: mid - border/2, y: interior, width: border, height: s - 2*interior))

    guard let image = ctx.makeImage() else { fatalError("makeImage") }
    return image
}

func save(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { fatalError("dest for \(path)") }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/um_iconset.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

var cache: [Int: CGImage] = [:]
func icon(_ size: Int) -> CGImage {
    if let cached = cache[size] { return cached }
    let img = generateUMIcon(size: size)
    cache[size] = img
    return img
}

let entries: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in entries {
    save(icon(size), to: "\(outDir)/\(name)")
    print("  \(name) (\(size)px)")
}
print("Done.")
