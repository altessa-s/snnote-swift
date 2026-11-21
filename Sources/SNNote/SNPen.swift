// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

internal import CSNNote

/// The tool a stroke record was made with: the record's `penType`.
///
/// The tablet's own numbers, and a firmware generation reuses them: the ink
/// pen was `1` before it was `16`, the marker `5` before `11`, and `1` is also
/// what a Nomad-era eraser writes. So the pen alone does not say whether a
/// record is ink — `SNStroke.role` does, from the record's own classification.
///
/// Frozen: an exhaustive `switch` over these cases in a consumer is the point.
@frozen
public enum SNPen: Sendable, Hashable {
    /// The ink pen, as older firmware numbers it (`1`). Also the Nomad-era
    /// eraser's number; an eraser record says so in its `role`.
    case inkPenLegacy
    /// The area eraser (`3`).
    case eraser
    /// The lasso (`4`).
    case lasso
    /// The marker, as older firmware numbers it (`5`). Also stamped by the
    /// tablet over the real tool of a star mark (see `SNStroke.Kind.star`).
    case markerLegacy
    /// The selecting eraser (`9`).
    case eraserSelect
    /// The needle-point pen (`10`).
    case needlePoint
    /// The marker (`11`).
    case marker
    /// The calligraphy pen (`15`).
    case calligraphy
    /// The ink pen (`16`).
    case inkPen
    /// A number this version does not know — including `0`, which geometry
    /// the tablet derives (a heading's box, a link's frame) carries in place
    /// of a tool.
    case other(Int32)

    public init(rawValue: Int32) {
        switch rawValue {
        case 1: self = .inkPenLegacy
        case 3: self = .eraser
        case 4: self = .lasso
        case 5: self = .markerLegacy
        case 9: self = .eraserSelect
        case 10: self = .needlePoint
        case 11: self = .marker
        case 15: self = .calligraphy
        case 16: self = .inkPen
        default: self = .other(rawValue)
        }
    }

    public var rawValue: Int32 {
        switch self {
        case .inkPenLegacy: 1
        case .eraser: 3
        case .lasso: 4
        case .markerLegacy: 5
        case .eraserSelect: 9
        case .needlePoint: 10
        case .marker: 11
        case .calligraphy: 15
        case .inkPen: 16
        case let .other(value): value
        }
    }

    /// Whether this is one of the marker's numbers. The marker is drawn
    /// beneath darker ink, and its colours carry `+1`.
    public var isMarker: Bool {
        sn_pen_is_marker(rawValue)
    }
}

extension SNPen {
    public static func == (a: SNPen, b: SNPen) -> Bool {
        a.rawValue == b.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

/// A stroke's colour as stored: the record's `penColor`.
///
/// On every current device the value is the grey itself — 0, 157, 201, 254 —
/// with `+1` when the marker drew it (1, 158, 202), and 255 reserved for an
/// eraser's own motion. The oldest A5X files store the two greys as ids
/// instead, 48 and 80 (49 and 81 for the marker), drawn as 157 and 201, and
/// `gray` reads them that way.
public struct SNInkColor: Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// The reserved value of an eraser's own motion.
    public static let eraser = SNInkColor(rawValue: 255)

    /// The grey this colour is drawn in, `0` black to `255` white, or `nil`
    /// for a value no device is known to write (a colour screen would be the
    /// first to).
    public var gray: UInt8? {
        var gray: UInt8 = 0
        return sn_ink_color_gray(rawValue, &gray) ? gray : nil
    }

    /// Whether the value is one of the marker's forms (`1`, `49`, `81`, `158`,
    /// `202`): the tablet rewrites a marker's colour that way, and nothing
    /// else.
    public var isMarkerForm: Bool {
        sn_ink_color_is_marker(rawValue)
    }
}
