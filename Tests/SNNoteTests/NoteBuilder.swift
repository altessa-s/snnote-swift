// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Compression
import Foundation

/// Assembles a `.note` from parts, for the tests that need a file the corpus
/// does not have: one broken in exactly one place.
///
/// The layout is the format's own — signature, blocks addressed by offset, the
/// footer, `tail`, the footer's address — and nothing here is clever: each
/// `append` returns the address the next block can point at.
struct NoteBuilder {
    private(set) var bytes = Data("noteSN_FILE_VER_20230015".utf8)

    init(signature: String = "noteSN_FILE_VER_20230015") {
        bytes = Data(signature.utf8)
    }

    /// Appends a length-prefixed block and answers its address.
    @discardableResult
    mutating func append(_ block: Data) -> Int {
        let address = bytes.count
        bytes.append(le32(UInt32(block.count)))
        bytes.append(block)
        return address
    }

    mutating func append(tags: [(String, String)]) -> Int {
        append(Data(tags.map { "<\($0.0):\($0.1)>" }.joined().utf8))
    }

    /// Closes the file: footer, `tail`, the footer's address.
    mutating func finish(footer: [(String, String)]) -> Data {
        let address = append(tags: footer)
        bytes.append(Data("tail".utf8))
        bytes.append(le32(UInt32(address)))
        return bytes
    }

    /// A one-page Nomad notebook: a blank main layer, the given stroke log.
    static func onePage(strokeLog: Data?) -> Data {
        var builder = NoteBuilder()
        let header = builder.append(tags: [("FILE_TYPE", "NOTE"), ("APPLY_EQUIPMENT", "N6"), ("FILE_ID", "F1")])
        let bitmap = builder.append(blankRLE(pixels: 1404 * 1872))
        let layer = builder.append(tags: [
            ("LAYERTYPE", "NOTE"), ("LAYERPROTOCOL", "RATTA_RLE"), ("LAYERNAME", "MAINLAYER"),
            ("LAYERBITMAP", String(bitmap)),
        ])
        let log = strokeLog.map { builder.append($0) } ?? 0
        let page = builder.append(tags: [
            ("PAGESTYLE", "style_white"), ("LAYERSEQ", "MAINLAYER"), ("MAINLAYER", String(layer)),
            ("TOTALPATH", String(log)), ("ORIENTATION", "1000"), ("PAGEID", "P1"),
        ])
        return builder.finish(footer: [("FILE_FEATURE", String(header)), ("PAGE1", String(page))])
    }

    /// A page of the background code in runs of `0x4000`, the tail cut to fit.
    static func blankRLE(pixels: Int) -> Data {
        var data = Data()
        var left = pixels
        while left >= 0x4000 {
            data.append(contentsOf: [0x62, 0xFF])
            left -= 0x4000
        }
        while left > 0 {
            let run = min(left, 128)
            data.append(contentsOf: [0x62, UInt8(run - 1)])
            left -= run
        }
        return data
    }

    /// One stroke record: the 208-byte header, the points (in digitiser
    /// units), pressures, the empty arrays, the status block, an outline.
    static func strokeRecord(
        pen: UInt32 = 10,
        color: UInt32 = 0,
        thickness: UInt32 = 400,
        kind: String = "others",
        role: Int32 = 5000,
        status: Int32 = 0,
        id: Int32 = 1,
        points: [(y: UInt32, x: UInt32)] = [(1000, 1000), (2000, 2000)],
        range: (y: UInt32, x: UInt32) = (15819, 11864),
        style: UInt32? = nil,
        fields: [String] = []
    ) -> Data {
        var header = Data(count: 208)
        header.replaceSubrange(0..<4, with: le32(pen))
        header.replaceSubrange(4..<8, with: le32(color))
        header.replaceSubrange(8..<12, with: le32(thickness))
        header.replaceSubrange(28..<32, with: le32(1))
        header.replaceSubrange(40..<44, with: le32(UInt32(bitPattern: role)))
        let name = Data(kind.utf8.prefix(51))
        header.replaceSubrange(48..<(48 + name.count), with: name)
        header.replaceSubrange(128..<132, with: le32(range.y))
        header.replaceSubrange(132..<136, with: le32(range.x))

        var record = header
        record.append(le32(0))                                   // disableAreaList
        record.append(le32(UInt32(points.count)))
        for point in points {
            record.append(le32(point.y))
            record.append(le32(point.x))
        }
        record.append(le32(UInt32(points.count)))
        for _ in points { record.append(contentsOf: [0x00, 0x08]) }  // pressure 2048
        for _ in 0..<4 { record.append(le32(0)) }                // angles, flags, epa points, epa greys
        var block = Data(count: 52)                              // m_trailStatus, m_copy, uid, shift
        block.replaceSubrange(0..<4, with: le32(UInt32(bitPattern: status)))
        block.replaceSubrange(8..<12, with: le32(UInt32(bitPattern: id)))
        record.append(block)
        record.append(le32(0))                                   // controlNums
        record.append(Data(count: 10))                           // group block
        record.append(le32(0))                                   // no outline rings
        guard let style else { return record }
        record.append(le32(0))                                   // no 20-byte entries
        record.append(Data([0, 0, 0, 0, 0, 0, 0xF0, 0x3F]) + Data(count: 9))  // 1.0, zeros
        record.append(le32(1404))
        record.append(le32(1872))
        record.append(le32(style))
        record.append(0)
        let list = fields.isEmpty ? "none" : fields.map { Data($0.utf8).base64EncodedString() }.joined(separator: ",")
        record.append(le32(UInt32(list.utf8.count)))
        record.append(Data(list.utf8))
        return record
    }

    /// The same log in the compressed form: the marker, the count, both
    /// lengths, and the records as one raw LZ4 block.
    static func compressedStrokeLog(_ records: [Data]) -> Data {
        var payload = Data()
        for record in records {
            payload.append(le32(UInt32(record.count)))
            payload.append(record)
        }
        let packed = lz4(payload)
        var log = le32(0xFFFF_FFFF)
        log.append(le32(UInt32(records.count)))
        log.append(le32(UInt32(payload.count)))
        log.append(le32(UInt32(packed.count)))
        log.append(packed)
        return log
    }

    /// A stroke log of the given records.
    static func strokeLog(_ records: [Data]) -> Data {
        var log = le32(UInt32(records.count))
        for record in records {
            log.append(le32(UInt32(record.count)))
            log.append(record)
        }
        return log
    }
}

func lz4(_ data: Data) -> Data {
    let capacity = data.count + data.count / 255 + 64
    var output = Data(count: capacity)
    let written = output.withUnsafeMutableBytes { target in
        data.withUnsafeBytes { source in
            compression_encode_buffer(
                target.bindMemory(to: UInt8.self).baseAddress!,  // swiftlint:disable:this force_unwrapping
                capacity,
                source.bindMemory(to: UInt8.self).baseAddress!,  // swiftlint:disable:this force_unwrapping
                data.count,
                nil,
                COMPRESSION_LZ4_RAW
            )
        }
    }
    return output.prefix(written)
}

func le32(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
