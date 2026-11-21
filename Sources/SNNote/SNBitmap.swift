// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

internal import CSNNote
import Foundation

/// A picture stored in the notebook — a layer, a template, a title's or a
/// link's snapshot, the cover — exactly as stored.
///
/// Kept encoded. A Manta page decodes to five megapixels, a notebook carries
/// one per layer per page, and most callers want the strokes or the text and
/// never a single pixel; decoding is `raster(width:height:)`, on request.
public struct SNBitmap: Sendable, Hashable {
    /// How the bytes are encoded.
    ///
    /// Frozen: an exhaustive `switch` over these cases in a consumer is the
    /// point.
    @frozen
    public enum Encoding: Sendable, Hashable {
        /// `RATTA_RLE`, the tablet's own run-length codes (see `SNPalette`).
        case rattaRLE
        /// A PNG file: a background the user imported as a template, or a
        /// cover.
        case png
        /// A JPEG file: a cover.
        case jpeg
        /// A protocol name this version does not decode, as written.
        case other(String)
    }

    public let encoding: Encoding
    public let data: Data

    public init(encoding: Encoding, data: Data) {
        self.encoding = encoding
        self.data = data
    }

    /// The bitmap's stored codes, one byte per pixel, row by row — the
    /// lossless form of a `RATTA_RLE` bitmap, before any palette has said what
    /// a code looks like. `nil` for anything that is not RLE.
    public func codes(width: Int, height: Int) throws -> [UInt8]? {
        guard encoding == .rattaRLE else { return nil }
        return try withBitmap { bitmap in
            var codes: UnsafeMutablePointer<UInt8>?
            var size = 0
            var error = sn_error()
            let status = sn_bitmap_codes(&bitmap, width, height, &codes, &size, &error)
            try check(status, &error)
            defer { sn_codes_free(codes) }
            return Array(UnsafeBufferPointer(start: codes, count: size))
        }
    }

    /// The bitmap as grey and coverage, at `width × height`.
    ///
    /// An RLE bitmap is decoded through `palette`; a PNG or a JPEG is decoded
    /// by the platform and reduced to luminance, and must already be the size asked
    /// for. Anything else throws.
    public func raster(width: Int, height: Int, palette: SNPalette = .current) throws -> SNRaster {
        switch encoding {
        case .rattaRLE, .other:
            return try withBitmap { bitmap in
                var table = palette.cPalette
                var raster: UnsafeMutablePointer<sn_raster>?
                var error = sn_error()
                let status = sn_bitmap_raster(&bitmap, width, height, &table, &raster, &error)
                try check(status, &error)
                defer { sn_raster_free(raster) }
                guard let planes = raster?.pointee, planes.gray != nil, planes.alpha != nil
                else { throw SNParseError.malformed("missing raster") }
                guard planes.width == width, planes.height == height
                else { throw SNParseError.malformed("invalid raster planes") }
                let count = planes.width * planes.height
                guard let result = SNRaster(width: width, height: height,
                                            gray: Array(UnsafeBufferPointer(start: planes.gray, count: count)),
                                            alpha: Array(UnsafeBufferPointer(start: planes.alpha, count: count)))
                else { throw SNParseError.malformed("invalid raster planes") }
                return result
            }
        case .png, .jpeg:
            return try SNRaster(image: data, width: width, height: height)
        }
    }

    private func withBitmap<T>(_ body: (inout sn_bitmap) throws -> T) rethrows -> T {
        try data.withUnsafeBytes { bytes in
            var bitmap = sn_bitmap()
            bitmap.encoding = switch encoding {
            case .rattaRLE: SN_ENCODING_RATTA_RLE
            case .png: SN_ENCODING_PNG
            case .jpeg: SN_ENCODING_JPEG
            case .other: SN_ENCODING_OTHER
            }
            bitmap.bytes = sn_bytes(data: bytes.bindMemory(to: UInt8.self).baseAddress, size: bytes.count)
            return try body(&bitmap)
        }
    }
}

extension SNBitmap.Encoding {
    public static func == (a: SNBitmap.Encoding, b: SNBitmap.Encoding) -> Bool {
        switch (a, b) {
        case (.rattaRLE, .rattaRLE), (.png, .png), (.jpeg, .jpeg): true
        case let (.other(x), .other(y)): x == y
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .rattaRLE: hasher.combine(0)
        case .png: hasher.combine(1)
        case .jpeg: hasher.combine(2)
        case let .other(name): hasher.combine(name)
        }
    }
}
