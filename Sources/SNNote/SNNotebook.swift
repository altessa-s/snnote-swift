// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation

/// A parsed Supernote file: a notebook (`.note`) or the annotations over a
/// document (`.mark`), which share one container.
public struct SNNotebook: Sendable, Hashable {
    /// Which of the two the signature says this is.
    ///
    /// Frozen: an exhaustive `switch` over these cases in a consumer is the
    /// point.
    @frozen
    public enum Kind: Sendable, Hashable {
        case note
        case mark
    }

    public let kind: Kind
    /// The format version from the signature, `SN_FILE_VER_20260016` read as
    /// `20260016` — a date-like number, not a firmware version.
    public let formatVersion: Int
    /// The device the file was written for.
    public let equipment: SNEquipment
    /// The file's identity (`FILE_ID`), which links point at. `nil` on files
    /// older than the field.
    public let fileID: String?
    /// The portrait sheet of the device, in pixels. A page turned landscape
    /// says so in its own `size`.
    public let sheet: CGSize
    public let pages: [SNPage]
    public let titles: [SNTitle]
    public let keywords: [SNKeyword]
    public let links: [SNLink]
    /// The highlights and underlines on a `.mark` file's document, from the
    /// header's `HIGHLIGHTINFO`. Empty on a notebook.
    public let highlights: [SNHighlight]
    /// The templates the notebook carries, by name — the background bitmaps
    /// its pages' `template` names.
    public let templates: [String: SNBitmap]
    /// The cover picture, when the notebook has one: an RLE bitmap, or the
    /// PNG or JPEG the user chose.
    public let cover: SNBitmap?
    /// How the cover was chosen — the digit of the footer's `COVER_<n>` key,
    /// which is a kind and not a page. `0` when there is no cover; a picture
    /// the user chose is `2`.
    public let coverType: Int
    /// Pages the footer lists that would not read. Counted so that a loss is
    /// visible rather than silent; `pages` then has a gap in its numbers.
    public let skippedPages: Int
    /// The header block as stored.
    public let header: SNMetadata
    /// The footer block as stored.
    public let footer: SNMetadata
}
