// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics

/// One record of a page's stroke log (`TOTALPATH`).
///
/// The log is not a picture of the page. It is everything the pen did, in the
/// order it did it: the ink, and also every eraser motion, every lasso loop,
/// every stroke later erased, moved or deleted, and the boxes the tablet draws
/// for headings and links. What the page shows is the subset `isDrawn` says,
/// and the record states that itself — `status` is the tablet's own verdict,
/// not something worked out by replaying the erasers, which cannot be done:
/// an eraser record and a selection record of the same shape mean opposite
/// things.
public struct SNStroke: Sendable, Hashable {
    /// The stroke's number on its page (`m_trailNumInPage`), counting from 1.
    /// Numbers a later edit superseded are simply absent.
    public let id: Int32
    public let pen: SNPen
    public let color: SNInkColor
    /// The width the tool was set to, in hundredths of a page pixel: `400` is a
    /// four-pixel line. The setting, not always the ink: the calligraphy pen
    /// lays down far less than its width, the older ink pen far more — the
    /// outline in `contour` is what the tablet actually filled.
    public let thickness: UInt32
    public let kind: Kind
    public let role: Role
    public let status: Status
    /// The operation that produced the record (`m_copy`): eraser and lasso
    /// tools and what a selection did. A number to look at, not to decide by —
    /// `status` already says what each operation did to each stroke.
    public let operation: Int32
    /// The layer the stroke was drawn on: `0` the main layer, `1`–`3` the
    /// others. Not the background, which holds no strokes.
    public let layer: Int
    /// The page the record names itself on, counting from 1.
    public let pageNumber: Int
    /// The sampled centreline, in page pixels.
    public let points: [SNStrokePoint]
    /// The filled outline the tablet renders for this stroke, in page pixels:
    /// closed rings, to be filled under the non-zero winding rule. Carries the
    /// width along the stroke that pressure and tilt gave it, which a
    /// centreline at `thickness` cannot.
    ///
    /// A record can have this and no `points` at all: the pieces a partial
    /// erase leaves are written that way, and so is a sticker's silhouette.
    /// Empty where the record stores none.
    public let contour: [[CGPoint]]
    /// The stroke's box, in page pixels: for ink the box the record declares,
    /// the centreline widened by half the stroke; for a frame or a heading's
    /// box, the rectangle its own corners make — the box those records
    /// declare is not their shape's.
    public let bounds: CGRect
    /// The style number the record's tail carries, which says what the record
    /// is for: `0` on ink, the heading's `TITLESTYLE`, a text box's or a
    /// link's own range (see `category`). `nil` where the tail does not read.
    public let style: UInt32?
    /// The fields the record's tail carries, decoded from base64: for a
    /// heading or a link, the same values as its footer block, in its order
    /// (type, direction, style, timestamp, rects, path, file, page, …). Empty
    /// on ink.
    public let attributes: [String]

    public let category: Category

    /// Whether the tablet draws this record on the page.
    ///
    /// The record's own status, and then the records that are never ink
    /// whatever their status: an eraser's or a lasso's motion, the frame of a
    /// link or a text box, and anything in the eraser's reserved colour.
    public let isDrawn: Bool
}

extension SNStroke {
    private static func category(for style: UInt32?) -> Category {
        guard let style, style != 0 else { return .ordinary }
        switch style {
        case 1_000_000...1_255_255: return .heading
        case 5_000_000...5_002_000: return .textBox
        case 24_000_000...24_000_003: return .pictureLink
        case 25_000_000...25_000_003: return .textLink
        case 20_000_000...26_000_000: return .link
        default: return .other(style)
        }
    }

    private static func isDrawn(status: Status, role: Role, kind: Kind, color: SNInkColor,
                                category: Category, pen: SNPen) -> Bool {
        guard status.rawValue >= 0 else { return false }
        switch role {
        case .eraser, .lasso: return false
        case .ink, .derived, .other: break
        }
        if kind == .frame || color == .eraser { return false }
        // A text box's text is in the layer's bitmap, drawn by the tablet from
        // the record's fields; the record's own geometry is not ink. Nor is a
        // link's, of whatever kind.
        switch category {
        case .textBox, .link, .pictureLink, .textLink: return false
        case .ordinary, .heading, .other: break
        }
        switch pen {
        case .eraser, .lasso, .eraserSelect: return false
        default: return pen.rawValue != -3
        }
    }

    public init(
        id: Int32,
        pen: SNPen,
        color: SNInkColor,
        thickness: UInt32,
        kind: Kind,
        role: Role,
        status: Status,
        operation: Int32 = 0,
        layer: Int = 0,
        pageNumber: Int = 1,
        points: [SNStrokePoint],
        contour: [[CGPoint]] = [],
        bounds: CGRect = .null,
        style: UInt32? = nil,
        attributes: [String] = []
    ) {
        category = Self.category(for: style)
        isDrawn = Self.isDrawn(status: status, role: role, kind: kind, color: color, category: category, pen: pen)
        self.style = style
        self.attributes = attributes
        self.id = id
        self.pen = pen
        self.color = color
        self.thickness = thickness
        self.kind = kind
        self.role = role
        self.status = status
        self.operation = operation
        self.layer = layer
        self.pageNumber = pageNumber
        self.points = points
        self.contour = contour
        self.bounds = bounds
    }
}

/// One sample of a stroke.
public struct SNStrokePoint: Sendable, Hashable {
    /// Where the pen was, in page pixels.
    public let position: CGPoint
    /// The pen's pressure as the digitiser reported it, unscaled.
    public let pressure: UInt16

    public init(position: CGPoint, pressure: UInt16) {
        self.position = position
        self.pressure = pressure
    }
}
