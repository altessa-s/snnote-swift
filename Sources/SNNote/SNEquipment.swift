// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
internal import CSNNote

/// The device a notebook was written for: the header's `APPLY_EQUIPMENT`.
///
/// It matters for one thing, the size of the sheet. The format stores bitmaps
/// as run lengths with no width or height beside them, so a page cannot be
/// laid out at all without knowing which screen it was drawn on — and the
/// header says that only by naming the device.
///
/// Frozen: an exhaustive `switch` over these cases in a consumer is the point.
@frozen
public enum SNEquipment: Sendable, Hashable {
    /// Supernote A5X.
    case a5x
    /// Supernote A6X.
    case a6x
    /// Supernote Nomad (A6X2), written `N6`.
    case nomad
    /// Supernote Manta (A5X2), written `N5`.
    case manta
    /// A name this version does not know, kept as written.
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "A5X": self = .a5x
        case "A6X": self = .a6x
        case "N6", "A6X2": self = .nomad
        case "N5", "A5X2": self = .manta
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .a5x: "A5X"
        case .a6x: "A6X"
        case .nomad: "N6"
        case .manta: "N5"
        case let .other(name): name
        }
    }

    /// The portrait sheet in pixels, or `nil` for a device this version does
    /// not know — the parser then measures the sheet out of the bitmaps
    /// themselves (see `SNParser`).
    ///
    /// The Manta is the one that differs: 1920 × 2560 against the 1404 × 1872
    /// every earlier device shares.
    public var portraitSize: CGSize? {
        let device: sn_equipment = switch self {
        case .a5x: SN_EQUIPMENT_A5X
        case .a6x: SN_EQUIPMENT_A6X
        case .nomad: SN_EQUIPMENT_NOMAD
        case .manta: SN_EQUIPMENT_MANTA
        case .other: SN_EQUIPMENT_OTHER
        }
        let sheet = sn_equipment_sheet(device)
        return sheet.width == 0 ? nil : CGSize(width: sheet.width, height: sheet.height)
    }
}

extension SNEquipment {
    public static func == (a: SNEquipment, b: SNEquipment) -> Bool {
        a.rawValue == b.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

/// How a page is turned: the page's `ORIENTATION`.
///
/// Four numbers, and they say two things at once — the turn of
/// the sheet and which way the toolbar sat. Only the first matters to reading:
/// a landscape page's bitmaps are stored landscape, width and height swapped.
@frozen
public enum SNOrientation: Sendable, Hashable {
    case portrait
    case landscape
    /// A value this version does not know; read as portrait.
    case other(Int)

    init(rawValue: Int?) {
        switch rawValue {
        case nil, 0, 1000, 1180: self = .portrait
        case 1090, 1270: self = .landscape
        case let value?: self = .other(value)
        }
    }
}

// Spelled out for the reason `SNParseError`'s are: a synthesised witness is
// absent from a binary framework's symbol table.
extension SNOrientation {
    public static func == (a: SNOrientation, b: SNOrientation) -> Bool {
        switch (a, b) {
        case (.portrait, .portrait), (.landscape, .landscape): true
        case let (.other(x), .other(y)): x == y
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .portrait: hasher.combine(0)
        case .landscape: hasher.combine(1)
        case let .other(value):
            hasher.combine(2)
            hasher.combine(value)
        }
    }
}
