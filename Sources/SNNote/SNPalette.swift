// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

internal import CSNNote

/// What an RLE code looks like: a grey level and whether the pixel is covered.
///
/// The code byte in a `RATTA_RLE` run means one of two things, depending on
/// the generation of the file:
///
/// - **Before format 15** (`SN_FILE_VER_…0011` and older) it names a palette
///   entry: `0x61` black, `0x62` the empty background, `0x63` dark grey,
///   `0x64` grey, `0x65` white, and `0x66`–`0x68` the marker's forms of the
///   first three, drawn in the same greys. (`legacy`)
/// - **From format 15** it is a grey level, so that anti-aliased ink can
///   carry the ramp along its edges — with eight values swapped so the old
///   palette codes still mean what they meant: the grey that would have been
///   written `0x61` is written `0x00` and the other way round, and likewise
///   for 0x62↔255, 0x63↔48, 0x64↔80, 0x65↔254, 0x66↔1, 0x67↔49, 0x68↔81.
///   (`current`)
public struct SNPalette: Sendable, Hashable {
    /// One code's appearance.
    public struct Ink: Sendable, Hashable {
        /// Luminance, `0` black to `255` white.
        public let gray: UInt8
        /// Whether the pixel is covered at all. The background code is not:
        /// a layer's empty pixels show whatever is beneath them.
        public let isOpaque: Bool

        public init(gray: UInt8, isOpaque: Bool) {
            self.gray = gray
            self.isOpaque = isOpaque
        }

        public static let transparent = Ink(gray: 255, isOpaque: false)
    }

    /// The appearance of every code, indexed by the code.
    public let inks: [Ink]

    /// A palette of 256 entries; any other count is padded with opaque literal
    /// greys or cut.
    public init(inks: [Ink]) {
        var table = Array(inks.prefix(256))
        while table.count < 256 {
            table.append(Ink(gray: UInt8(table.count), isOpaque: true))
        }
        self.inks = table
    }

    public func ink(for code: UInt8) -> Ink {
        inks[Int(code)]
    }

    /// Files before format 15: the code names a palette entry. The marker's
    /// codes are drawn in the pen's greys. Every other code is no colour at
    /// all, and covers nothing.
    public static let legacy = SNPalette(sn_palette_legacy())
    public static let current = SNPalette(sn_palette_current())

    public static func forFormat(_ version: Int) -> SNPalette {
        SNPalette(sn_palette_for_format(Int64(version)))
    }

    init(_ value: sn_palette) {
        inks = withUnsafePointer(to: value.inks) { table in
            table.withMemoryRebound(to: sn_ink.self, capacity: 256) { pointer in
                UnsafeBufferPointer(start: pointer, count: 256).map { Ink(gray: $0.gray, isOpaque: $0.alpha != 0) }
            }
        }
    }

    var cPalette: sn_palette {
        var result = sn_palette()
        withUnsafeMutablePointer(to: &result.inks) { table in
            table.withMemoryRebound(to: sn_ink.self, capacity: 256) { pointer in
                for (index, ink) in inks.enumerated() {
                    pointer[index] = sn_ink(gray: ink.gray, alpha: ink.isOpaque ? 255 : 0)
                }
            }
        }
        return result
    }
}
