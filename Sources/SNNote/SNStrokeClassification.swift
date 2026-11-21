// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// What a stroke record is, what it does, whether it is drawn and what it is
// for: the four classifications a record carries, each read from its own
// field.
extension SNStroke {
    /// What the record is for, by its style number.
    ///
    /// Frozen: an exhaustive `switch` over these cases in a consumer is the
    /// point.
    @frozen
    public enum Category: Sendable, Hashable {
        /// Ink, or a record whose tail carries no style.
        case ordinary
        /// A heading's box (1000000–1255255, the `TITLESTYLE`).
        case heading
        /// A text box (5000000–5002000).
        case textBox
        /// A link to a page or a file (20000000–26000000).
        case link
        /// A link on a picture (24000000–24000003).
        case pictureLink
        /// A link on text (25000000–25000003).
        case textLink
        /// A style in none of the ranges.
        case other(UInt32)
    }

    /// What a record is, by the name the tablet gives it (`predictName`).
    ///
    /// Frozen: an exhaustive `switch` over these cases in a consumer is the
    /// point.
    @frozen
    public enum Kind: Sendable, Hashable {
        /// Freehand ink, any tool (`others`).
        case freehand
        /// A ruled line: two points, its ends (`straightLine`).
        case straightLine
        /// A heading's background: two points, opposite corners of a filled box
        /// (`0001`). Its own colour fields mean nothing; the title's
        /// `SNTitle.style` says how it looks.
        case headingBox
        /// The frame of a link or of a text box (`0000`): five points, a closed
        /// rectangle. Never shown as ink; `category` says which it frames.
        case frame
        /// A star mark (`fiveStarsSignal`). The tablet overwrites the pen and
        /// width of these on save, so `pen` here names no real tool.
        case star
        /// A name this version does not know, as written.
        case other(String)

        init(name: String) {
            switch name {
            case "others": self = .freehand
            case "straightLine": self = .straightLine
            case "0001": self = .headingBox
            case "0000": self = .frame
            case "fiveStarsSignal": self = .star
            default: self = .other(name)
            }
        }
    }

    /// What a record does, by the tablet's own classification of it
    /// (`preNum`) — durable where the pen number is not, since a firmware
    /// generation reuses pen numbers across tools.
    @frozen
    public enum Role: Sendable, Hashable {
        /// Ink (`5000`).
        case ink
        /// Geometry derived from two points — a heading's box, a link's frame,
        /// a ruled line (`0`).
        case derived
        /// An eraser's own motion (`-1`, `-2`, `-4`, one per tool mode).
        case eraser
        /// A lasso loop (`-5`).
        case lasso
        case other(Int32)

        init(rawValue: Int32) {
            switch rawValue {
            case 5000: self = .ink
            case 0: self = .derived
            case -1, -2, -4: self = .eraser
            case -5: self = .lasso
            default: self = .other(rawValue)
            }
        }
    }

    /// Whether the tablet still draws the record, and if not, why
    /// (`m_trailStatus`). The tablet's test is the sign: anything below zero
    /// is not drawn.
    @frozen
    public enum Status: Sendable, Hashable {
        /// Drawn (`0`).
        case live
        /// Removed with the page cleared (`-2`).
        case cleared
        /// Moved by a lasso; the ink lives on in a later record (`-3`).
        case moved
        /// Partly erased; what survived follows as separate contour-only
        /// records (`-4`).
        case partiallyErased
        /// Deleted through a lasso selection (`-16`).
        case deleted
        /// Erased whole (`-99`).
        case erased
        case other(Int32)

        init(rawValue: Int32) {
            switch rawValue {
            case 0: self = .live
            case -2: self = .cleared
            case -3: self = .moved
            case -4: self = .partiallyErased
            case -16: self = .deleted
            case -99: self = .erased
            default: self = .other(rawValue)
            }
        }

        public var rawValue: Int32 {
            switch self {
            case .live: 0
            case .cleared: -2
            case .moved: -3
            case .partiallyErased: -4
            case .deleted: -16
            case .erased: -99
            case let .other(value): value
            }
        }
    }
}

extension SNStroke.Kind {
    public static func == (a: SNStroke.Kind, b: SNStroke.Kind) -> Bool {
        switch (a, b) {
        case (.freehand, .freehand), (.straightLine, .straightLine), (.headingBox, .headingBox),
             (.frame, .frame), (.star, .star): true
        case let (.other(x), .other(y)): x == y
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .freehand: hasher.combine("others")
        case .straightLine: hasher.combine("straightLine")
        case .headingBox: hasher.combine("0001")
        case .frame: hasher.combine("0000")
        case .star: hasher.combine("fiveStarsSignal")
        case let .other(name): hasher.combine("other:" + name)
        }
    }
}

extension SNStroke.Role {
    public static func == (a: SNStroke.Role, b: SNStroke.Role) -> Bool {
        switch (a, b) {
        case (.ink, .ink), (.derived, .derived), (.eraser, .eraser), (.lasso, .lasso): true
        case let (.other(x), .other(y)): x == y
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .ink: hasher.combine(0)
        case .derived: hasher.combine(1)
        case .eraser: hasher.combine(2)
        case .lasso: hasher.combine(3)
        case let .other(value):
            hasher.combine(4)
            hasher.combine(value)
        }
    }
}

extension SNStroke.Status {
    public static func == (a: SNStroke.Status, b: SNStroke.Status) -> Bool {
        a.rawValue == b.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension SNStroke.Category {
    public static func == (a: SNStroke.Category, b: SNStroke.Category) -> Bool {
        switch (a, b) {
        case (.ordinary, .ordinary), (.heading, .heading), (.textBox, .textBox), (.link, .link),
             (.pictureLink, .pictureLink), (.textLink, .textLink): true
        case let (.other(x), .other(y)): x == y
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .ordinary: hasher.combine(0)
        case .heading: hasher.combine(1)
        case .textBox: hasher.combine(2)
        case .link: hasher.combine(3)
        case .pictureLink: hasher.combine(4)
        case .textLink: hasher.combine(5)
        case let .other(value):
            hasher.combine(6)
            hasher.combine(value)
        }
    }
}
