import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// swift tools/flatten_icon.swift in.png out.png: the same pixels, without an alpha channel (refuses if any pixel isn't opaque).
let args = CommandLine.arguments
guard args.count == 3, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("usage: flatten in.png out.png") }
let (w, h) = (image.width, image.height)
let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
var rgba = [UInt8](repeating: 0, count: w * h * 4)
let check = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
check.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
let seeThrough = stride(from: 3, to: rgba.count, by: 4).filter { rgba[$0] != 255 }.count
guard seeThrough == 0 else { print("NOT OPAQUE: \(seeThrough) pixels"); exit(1) }
let out = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
out.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("couldn't write") }
print("opaque, \(w)×\(h), written without alpha")
