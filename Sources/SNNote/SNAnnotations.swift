// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
internal import CSNNote
import Foundation

/// A heading: handwriting the user circled and marked as a title.
///
/// Recorded in the footer, not on the page — `TITLE_<page><y><x>` naming a
/// block — which is also where its look lives: the box's own stroke record
/// (`SNStroke.Kind.headingBox`) carries no usable colour at all.
public struct SNTitle: Sendable, Hashable {
    /// The page it is on, counting from 1, from the footer key.
    public let pageNumber: Int
    /// Nesting level, from 1.
    public let level: Int
    /// The heading's box in page pixels.
    public let rect: CGRect
    /// The box as first drawn, before the tablet fitted it.
    public let originalRect: CGRect
    /// A snapshot of the region, for the tablet's list of headings.
    public let bitmap: SNBitmap?
    public let style: Style
    /// The block as stored, for keys this type does not name.
    public let metadata: SNMetadata

    public init(
        pageNumber: Int,
        level: Int,
        rect: CGRect,
        originalRect: CGRect,
        bitmap: SNBitmap?,
        style: Style,
        metadata: SNMetadata = SNMetadata(entries: [])
    ) {
        self.pageNumber = pageNumber
        self.level = level
        self.rect = rect
        self.originalRect = originalRect
        self.bitmap = bitmap
        self.style = style
        self.metadata = metadata
    }

    /// `TITLESTYLE`, which is decimal digits `1BBBFFF`: the background's grey
    /// and the grey the label's ink is shown in.
    public struct Style: Sendable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// The box's grey: `0`, `157`, `201`. A hatched box reads `0` here
        /// too — see `isHatched`.
        public var background: Int { Int(sn_title_style_background(Int64(rawValue))) }
        /// The grey the handwriting inside is shown in. Not its ink: the
        /// tablet turns black writing white on a dark box.
        public var foreground: Int { Int(sn_title_style_foreground(Int64(rawValue))) }
        /// The cross-hatched box, the one style that spells black-on-black: a
        /// solid black box always carries white text.
        public var isHatched: Bool { sn_title_style_is_hatched(Int64(rawValue)) }
    }
}

/// A keyword: a word the user lassoed and tagged, with the text the tablet
/// recognised in it stored beside it.
public struct SNKeyword: Sendable, Hashable {
    public let pageNumber: Int
    public let rect: CGRect
    public let originalRect: CGRect
    /// What the tablet read in the region — or what the user typed for a tag.
    public let text: String
    public let metadata: SNMetadata

    public init(
        pageNumber: Int,
        rect: CGRect,
        originalRect: CGRect,
        text: String,
        metadata: SNMetadata = SNMetadata(entries: [])
    ) {
        self.pageNumber = pageNumber
        self.rect = rect
        self.originalRect = originalRect
        self.text = text
        self.metadata = metadata
    }
}

/// A link drawn on a page, to a page of a notebook or to a file.
public struct SNLink: Sendable, Hashable {
    /// The page the link is drawn on, counting from 1. From the footer key —
    /// the block's own `OBJPAGE` does not reliably say it.
    public let pageNumber: Int
    /// The region on the page that is the link, in page pixels.
    public let rect: CGRect
    /// `LINKTYPE`: what kind of target — `0` a page of a notebook, `1` a
    /// notebook, `2` a document, `4` the web.
    public let kind: Int
    /// `LINKINOUT`: which way the link points, as the tablet numbers it.
    public let direction: Int
    /// The target's path on the device, `/storage/emulated/0/Note/…` — or,
    /// for a link to the web, its address.
    public let targetPath: String?

    /// The address of a link to the web.
    public var url: URL? {
        guard kind == 4, let targetPath else { return nil }
        return URL(string: targetPath)
    }
    /// The target notebook's `FILE_ID`.
    public let targetFileID: String?
    /// The target page's `PAGEID`, when the link is to a page.
    public let targetPageID: String?
    /// The target page's number as the tablet recorded it (`OBJPAGE`), from 1.
    /// The page may have moved since; `targetPageID` is what finds it.
    public let targetPageNumber: Int?
    /// `LINKSTYLE`: how the link looks and what it sits on — 20000000 a frame
    /// around handwriting, 24000000… on a picture, 25000000… on text (the
    /// ranges of `SNStroke.Category`).
    public let style: Int
    /// When the link was made, `yyyyMMddHHmmss` and microseconds, as stored.
    public let timestamp: String?
    /// The text a text link shows, when it is one.
    public let text: String?
    /// A snapshot of the linked region.
    public let bitmap: SNBitmap?
    public let metadata: SNMetadata

    public init(
        pageNumber: Int,
        rect: CGRect,
        kind: Int,
        direction: Int = 0,
        targetPath: String?,
        targetFileID: String? = nil,
        targetPageID: String? = nil,
        targetPageNumber: Int? = nil,
        style: Int = 20_000_000,
        timestamp: String? = nil,
        text: String? = nil,
        bitmap: SNBitmap? = nil,
        metadata: SNMetadata = SNMetadata(entries: [])
    ) {
        self.pageNumber = pageNumber
        self.rect = rect
        self.kind = kind
        self.direction = direction
        self.targetPath = targetPath
        self.targetFileID = targetFileID
        self.targetPageID = targetPageID
        self.targetPageNumber = targetPageNumber
        self.style = style
        self.timestamp = timestamp
        self.text = text
        self.bitmap = bitmap
        self.metadata = metadata
    }
}

/// A box of typed text on a page.
///
/// Recorded as a frame in the stroke log, style `5000000`, whose fields carry
/// the box: its place, its font and its text.
public struct SNTextBox: Sendable, Hashable {
    /// The record's number on its page.
    public let id: Int32
    /// The box, in page pixels.
    public let rect: CGRect
    public let text: String
    /// The font size, in page pixels.
    public let fontSize: Double?
    /// The font's path on the device.
    public let fontPath: String?
    /// When the box was made, `yyyyMMddHHmmss` and microseconds, as stored.
    public let timestamp: String?
    /// Every field the record carries, decoded.
    public let attributes: [String]

    public init(
        id: Int32,
        rect: CGRect,
        text: String,
        fontSize: Double? = nil,
        fontPath: String? = nil,
        timestamp: String? = nil,
        attributes: [String] = []
    ) {
        self.id = id
        self.rect = rect
        self.text = text
        self.fontSize = fontSize
        self.fontPath = fontPath
        self.timestamp = timestamp
        self.attributes = attributes
    }

    /// The text box a stroke record holds, or `nil` when it holds none — not
    /// a text box, or one since erased or deleted.
    public init?(stroke: SNStroke) {
        guard stroke.category == .textBox, stroke.status.rawValue >= 0 else { return nil }
        let fields = stroke.attributes
        func field(_ index: Int) -> String? {
            index < fields.count ? fields[index].unlessUnset : nil
        }
        id = stroke.id
        rect = CGRect(stored: field(4)) ?? stroke.bounds
        fontSize = field(10).flatMap(Double.init)
        fontPath = field(11)
        // The text as written: `0` is text here, not "unset".
        text = fields.count > 12 && fields[12] != "none" ? fields[12] : ""
        timestamp = field(3)
        attributes = fields
    }
}

extension CGRect {
    /// `x,y,w,h` as the footer writes a rectangle.
    init?(stored text: String?) {
        guard let text else { return nil }
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        self.init(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }
}

/// A mark made on the text of a `.mark` file's document: a highlight or an
/// underline over a run of its text, with the comment the user attached.
///
/// Stored apart from the handwriting, in the block the header's
/// `HIGHLIGHTINFO` names: base64 of a JSON object whose keys are the
/// document's page indexes, counting from 0.
public struct SNHighlight: Sendable, Hashable {
    /// The document page it is on, counting from 1.
    public let pageNumber: Int
    /// `annotationType`: `0` a highlight, `1` an underline.
    public let kind: Int
    /// `colorType`, as the tablet numbers it.
    public let colorType: Int
    /// The comment attached to it, if any.
    public let comment: String?
    /// The marked lines, in page pixels.
    public let rects: [CGRect]
    /// The same lines in the document's own coordinates (points, from the
    /// page's top left).
    public let documentRects: [CGRect]
    /// When it was made.
    public let date: Date?

    public init(
        pageNumber: Int,
        kind: Int,
        colorType: Int = 0,
        comment: String? = nil,
        rects: [CGRect],
        documentRects: [CGRect] = [],
        date: Date? = nil
    ) {
        self.pageNumber = pageNumber
        self.kind = kind
        self.colorType = colorType
        self.comment = comment
        self.rects = rects
        self.documentRects = documentRects
        self.date = date
    }
}
