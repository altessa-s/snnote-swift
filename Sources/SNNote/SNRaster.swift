// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation
import ImageIO

/// A decoded bitmap: a grey level and a coverage per pixel, row by row.
///
/// Grey and not colour because every Supernote the format has been written by
/// is a greyscale screen, and the stored codes say nothing else. Coverage is
/// separate because a layer's empty pixels are not white: they are the layers
/// beneath, and a page is the stack of them.
public struct SNRaster: Sendable, Hashable {
    public let width: Int
    public let height: Int
    /// `0` black to `255` white.
    public private(set) var gray: [UInt8]
    /// `0` uncovered to `255` covered. RLE bitmaps hold only the two
    /// extremes; a PNG template may hold anything between.
    public private(set) var alpha: [UInt8]

    /// A raster of the given planes, or `nil` when either holds other than
    /// `width × height` pixels. Failable rather than trapping: this ships
    /// inside somebody else's process, and a trap there takes the host down.
    public init?(width: Int, height: Int, gray: [UInt8], alpha: [UInt8]) {
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard width >= 0, height >= 0, !overflow, gray.count == count, alpha.count == count else {
            return nil
        }
        self.init(checked: width, height: height, gray: gray, alpha: alpha)
    }

    private init(checked width: Int, height: Int, gray: [UInt8], alpha: [UInt8]) {
        self.width = width
        self.height = height
        self.gray = gray
        self.alpha = alpha
    }

    /// An empty, uncovered sheet.
    ///
    /// A size whose pixel count does not fit in an `Int` gives an empty
    /// raster rather than a trap.
    public init(width: Int, height: Int) {
        let (count, overflow) = max(width, 0).multipliedReportingOverflow(by: max(height, 0))
        let fits = !overflow
        self.init(
            checked: fits ? max(width, 0) : 0,
            height: fits ? max(height, 0) : 0,
            gray: [UInt8](repeating: 255, count: fits ? count : 0),
            alpha: [UInt8](repeating: 0, count: fits ? count : 0)
        )
    }

    /// The pixel at `(x, y)`, or `nil` outside the raster.
    public func pixel(x: Int, y: Int) -> (gray: UInt8, alpha: UInt8)? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let index = y * width + x
        return (gray[index], alpha[index])
    }

    /// This raster laid over `below`: a covered pixel here replaces the one
    /// beneath, a partly covered one blends into it, an uncovered one shows
    /// it.
    ///
    /// The tablet stacks a page's layers this way — the top layer's ink over
    /// the next, the template at the bottom — and the stored codes leave no
    /// room for anything subtler: a marker's grey is already the grey it shows.
    public func over(_ below: SNRaster) throws -> SNRaster {
        guard width == below.width, height == below.height else {
            throw SNParseError.malformed("layers differ in size: \(width)×\(height) over \(below.width)×\(below.height)")
        }
        var outGray = below.gray
        var outAlpha = below.alpha
        gray.withUnsafeBufferPointer { gray in
            alpha.withUnsafeBufferPointer { alpha in
                outGray.withUnsafeMutableBufferPointer { outGray in
                    outAlpha.withUnsafeMutableBufferPointer { outAlpha in
                        for index in 0..<gray.count {
                            let a = Int(alpha[index])
                            if a == 255 {
                                outGray[index] = gray[index]
                                outAlpha[index] = 255
                            } else if a > 0 {
                                let b = Int(outAlpha[index])
                                let covered = a + b * (255 - a) / 255
                                let mixed = (Int(gray[index]) * a + Int(outGray[index]) * b * (255 - a) / 255)
                                    / max(covered, 1)
                                outGray[index] = UInt8(clamping: mixed)
                                outAlpha[index] = UInt8(clamping: covered)
                            }
                        }
                    }
                }
            }
        }
        return SNRaster(checked: width, height: height, gray: outGray, alpha: outAlpha)
    }

    /// The raster on paper: every uncovered pixel white, every partly covered
    /// one blended toward it. Coverage is full everywhere afterwards.
    public func flattened(onto paper: UInt8 = 255) -> SNRaster {
        var outGray = gray
        alpha.withUnsafeBufferPointer { alpha in
            outGray.withUnsafeMutableBufferPointer { outGray in
                for index in 0..<alpha.count where alpha[index] < 255 {
                    let a = Int(alpha[index])
                    outGray[index] = UInt8((Int(outGray[index]) * a + Int(paper) * (255 - a)) / 255)
                }
            }
        }
        return SNRaster(
            checked: width,
            height: height,
            gray: outGray,
            alpha: [UInt8](repeating: 255, count: gray.count)
        )
    }

    /// A greyscale `CGImage` of the raster, with its coverage as alpha.
    public func cgImage() -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        var interleaved = [UInt8](repeating: 0, count: gray.count * 2)
        gray.withUnsafeBufferPointer { gray in
            alpha.withUnsafeBufferPointer { alpha in
                interleaved.withUnsafeMutableBufferPointer { out in
                    for index in 0..<gray.count {
                        // Premultiplied, as CoreGraphics wants a grey-alpha
                        // image to be.
                        out[index * 2] = UInt8(Int(gray[index]) * Int(alpha[index]) / 255)
                        out[index * 2 + 1] = alpha[index]
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(interleaved) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 16,
            bytesPerRow: width * 2,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// A PNG of the raster. For looking at; nothing here reads it back.
    public func pngData() -> Data? {
        guard let image = cgImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// A PNG decoded by the platform and reduced to luminance and coverage.
    ///
    /// A template the user imported is an arbitrary PNG — palette, grey, RGB,
    /// with or without alpha — and is drawn into one known layout here rather
    /// than read in each of them.
    ///
    /// The size is checked before a pixel is allocated: a PNG's header is the
    /// file's word, and believed it can ask for gigabytes.
    init(image data: Data, width: Int, height: Int) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw SNParseError.malformed("image bitmap does not decode")
        }
        guard image.width == width, image.height == height else {
            throw SNParseError.malformed("PNG bitmap is \(image.width)×\(image.height), the sheet is \(width)×\(height)")
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= Int.max / 4 else { throw SNParseError.malformed("PNG bitmap is too large") }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw SNParseError.malformed("PNG bitmap does not decode") }
        var gray = [UInt8](repeating: 255, count: width * height)
        var alpha = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let a = Int(rgba[index * 4 + 3])
            alpha[index] = UInt8(a)
            guard a > 0 else { continue }
            // Un-premultiplied, then Rec. 601 luma.
            let r = Int(rgba[index * 4]) * 255 / a
            let g = Int(rgba[index * 4 + 1]) * 255 / a
            let b = Int(rgba[index * 4 + 2]) * 255 / a
            gray[index] = UInt8(clamping: (299 * r + 587 * g + 114 * b) / 1000)
        }
        self.init(checked: width, height: height, gray: gray, alpha: alpha)
    }
}
