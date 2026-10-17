import CoreGraphics
import Foundation
import Testing
@testable import AgentOverview

@Suite("App icon")
struct IconRendererTests {
    /// RGBA of one pixel (x from the left, y from the top) of an image redrawn into a known layout.
    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let index = (y * width + x) * 4
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }

    @Test("The flag names the folder; without a folder or the flag there is no icon run")
    func flag() {
        #expect(IconRenderer.requestedFolder(in: ["app", "--render-icon", "/tmp/x.iconset"])?.path == "/tmp/x.iconset")
        #expect(IconRenderer.requestedFolder(in: ["app", "--render-icon"]) == nil)
        #expect(IconRenderer.requestedFolder(in: ["app", "--sessions-folder", "/tmp"]) == nil)
    }

    @Test("The iconset has every size iconutil wants, 16 to 512 at 1x and 2x")
    func entries() {
        let entries = IconRenderer.iconsetEntries
        #expect(entries.count == 10)
        #expect(entries.first! == ("icon_16x16.png", 16) && entries.last! == ("icon_512x512@2x.png", 1024))
        #expect(Set(entries.map(\.name)).count == 10)
    }

    @Test("Corners stay transparent, the body is near black, the face centre is the face colour")
    func pixels() {
        for side in [16, 128, 1024] {
            let image = IconRenderer.image(pixels: side)
            #expect(image.width == side && image.height == side)
            #expect(Self.pixel(image, x: 0, y: 0).a == 0, "outside the rounded square at \(side) px")
            let look = IconRenderer.look(forPixels: side)
            let scale = Double(side) / Double(IconRenderer.canvas)
            // The face square's centre, a little below the eyes: solid body colour.
            let centre = Self.pixel(image, x: Int(look.faceCentre.x * scale), y: side - 1 - Int((look.faceCentre.y - look.faceSize * 0.15) * scale))
            #expect(centre.a == 255 && centre.g > 200 && centre.r < 150, "mint at \(side) px")
            // Inside the rounded square, outside the face and glow reach: near black.
            let edge = Self.pixel(image, x: Int(Double(side) * 0.14), y: side / 2)
            #expect(edge.a == 255 && max(edge.r, edge.g, edge.b) < 40, "dark body at \(side) px")
        }
        let large = IconRenderer.look(forPixels: 1024)
        #expect(large.color == Theme.justFinishedColor && large.body.shape == Theme.blobIdleShape, "the done mint on the idle pill")
    }
}
