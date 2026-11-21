// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

internal import CSNNote
import Foundation

public enum SNParser {
    /// Parses a notebook and copies its contents into independent Swift values.
    public static func parse(_ data: Data) throws -> SNNotebook {
        var result: UnsafeMutablePointer<sn_notebook>?
        var error = sn_error()
        let status = data.withUnsafeBytes { bytes in
            var empty: UInt8 = 0
            if let pointer = bytes.bindMemory(to: UInt8.self).baseAddress {
                return sn_parse_notebook(pointer, bytes.count, &result, &error)
            }
            return sn_parse_notebook(&empty, 0, &result, &error)
        }
        if status == SN_ERR_UNSUPPORTED_FORMAT {
            let prefix = data.prefix(24).map { (0x20..<0x7F).contains($0) ? $0 : UInt8(ascii: "?") }
            throw SNParseError.unsupportedFormat(String(decoding: prefix, as: UTF8.self))
        }
        try check(status, &error)
        defer { sn_notebook_free(result) }
        guard let result else { throw SNParseError.malformed("missing notebook") }
        return try ModelCopy(inputSize: data.count).notebook(result.pointee)
    }
}

func check(_ status: sn_status, _ error: inout sn_error) throws {
    guard status != SN_OK else { return }
    if status == SN_ERR_UNEXPECTED_EOF { throw SNParseError.unexpectedEndOfData }
    let message = withUnsafeBytes(of: &error.message) { bytes in
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
    throw SNParseError.malformed(message)
}

private final class ModelCopy {
    private var remaining: Int

    init(inputSize: Int) {
        let floor = Int(SN_PARSE_BUDGET_FLOOR)
        let multiple = Int(SN_PARSE_BUDGET_MULTIPLE)
        remaining = inputSize > (Int.max - floor) / multiple ? Int.max : floor + multiple * inputSize
    }

    private func charge(_ count: Int, stride: Int = 1) throws {
        guard count >= 0, count <= remaining / stride else {
            throw SNParseError.malformed("Swift model copy allocation budget exceeded")
        }
        remaining -= count * stride
    }

    func array<C, Value>(_ pointer: UnsafePointer<C>?, _ count: Int,
                         _ copy: (C) throws -> Value) throws -> [Value] {
        try charge(count, stride: MemoryLayout<Value>.stride)
        guard count == 0 || pointer != nil else { throw SNParseError.malformed("missing model array") }
        return try UnsafeBufferPointer(start: pointer, count: count).map(copy)
    }

    func string(_ value: sn_string) throws -> String? {
        guard let pointer = value.data else { return nil }
        try charge(value.length)
        let bytes = UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self)
        return String(decoding: UnsafeBufferPointer(start: bytes, count: value.length), as: UTF8.self)
    }

    func bytes(_ value: sn_bytes) throws -> Data? {
        guard let pointer = value.data else { return nil }
        try charge(value.size)
        return Data(bytes: pointer, count: value.size)
    }

    func metadata(_ value: sn_metadata) throws -> SNMetadata {
        try SNMetadata(entries: array(value.entries, value.count) {
            try SNMetadata.Entry(key: string($0.key) ?? "", value: string($0.value) ?? "")
        })
    }

    func bitmap(_ value: sn_bitmap) throws -> SNBitmap {
        let encoding: SNBitmap.Encoding = switch value.encoding {
        case SN_ENCODING_RATTA_RLE: .rattaRLE
        case SN_ENCODING_PNG: .png
        case SN_ENCODING_JPEG: .jpeg
        default: .other(try string(value.name) ?? "")
        }
        return try SNBitmap(encoding: encoding, data: bytes(value.bytes) ?? Data())
    }

    func notebook(_ value: sn_notebook) throws -> SNNotebook {
        try charge(1, stride: MemoryLayout<SNNotebook>.stride)
        try charge(256, stride: MemoryLayout<SNPalette.Ink>.stride)
        let palette = SNPalette(value.palette)
        var templates: [String: SNBitmap] = [:]
        try charge(value.template_count, stride: MemoryLayout<(String, SNBitmap)>.stride)
        guard value.template_count == 0 || value.templates != nil
        else { throw SNParseError.malformed("missing model array") }
        for entry in UnsafeBufferPointer(start: value.templates, count: value.template_count) {
            templates[try string(entry.name) ?? ""] = try bitmap(entry.bitmap)
        }
        return try SNNotebook(
            kind: value.kind == SN_KIND_MARK ? .mark : .note, formatVersion: Int(value.format_version),
            equipment: SNEquipment(rawValue: string(value.equipment_raw) ?? ""), fileID: string(value.file_id),
            sheet: CGSize(width: value.sheet.width, height: value.sheet.height),
            pages: array(value.pages, value.page_count) { try page($0, palette) },
            titles: array(value.titles, value.title_count, title),
            keywords: array(value.keywords, value.keyword_count) {
                try SNKeyword(pageNumber: Int($0.page_number), rect: rect($0.rect),
                              originalRect: rect($0.original_rect),
                              text: string($0.text) ?? "", metadata: metadata($0.metadata))
            },
            links: array(value.links, value.link_count, link),
            highlights: array(value.highlights, value.highlight_count) {
                try SNHighlight(pageNumber: Int($0.page_number), kind: Int($0.kind), colorType: Int($0.color_type),
                                comment: string($0.comment), rects: array($0.rects, $0.rect_count, rect),
                                documentRects: array($0.document_rects, $0.document_rect_count, rect),
                                date: $0.has_date ? Date(timeIntervalSince1970: $0.date) : nil)
            },
            templates: templates, cover: value.cover.map { try bitmap($0.pointee) }, coverType: Int(value.cover_type),
            skippedPages: value.skipped_pages, header: metadata(value.header), footer: metadata(value.footer)
        )
    }

    func rect(_ value: sn_rect) -> CGRect {
        value.is_null ? .null : CGRect(x: value.x, y: value.y, width: value.width, height: value.height)
    }

    func title(_ value: sn_title) throws -> SNTitle {
        try SNTitle(pageNumber: Int(value.page_number), level: Int(value.level), rect: rect(value.rect),
                    originalRect: rect(value.original_rect), bitmap: value.bitmap.map { try bitmap($0.pointee) },
                    style: .init(rawValue: Int(value.style)), metadata: metadata(value.metadata))
    }

    func link(_ value: sn_link) throws -> SNLink {
        try SNLink(pageNumber: Int(value.page_number), rect: rect(value.rect), kind: Int(value.kind),
                   direction: Int(value.direction), targetPath: string(value.target_path),
                   targetFileID: string(value.target_file_id), targetPageID: string(value.target_page_id),
                   targetPageNumber: value.has_target_page_number ? Int(value.target_page_number) : nil,
                   style: Int(value.style), timestamp: string(value.timestamp), text: string(value.text),
                   bitmap: value.bitmap.map { try bitmap($0.pointee) }, metadata: metadata(value.metadata))
    }

    func page(_ value: sn_page, _ palette: SNPalette) throws -> SNPage {
        try SNPage(
            number: Int(value.number), id: string(value.id), template: string(value.template_name),
            orientation: SNOrientation(rawValue: Int(value.orientation_raw)),
            size: CGSize(width: value.size.width, height: value.size.height),
            layers: array(value.layers, value.layer_count, layer),
            layerInfo: array(value.layer_info, value.layer_info_count, info),
            strokes: array(value.strokes, value.stroke_count, stroke), skippedStrokes: value.skipped_strokes,
            recognition: value.recognition.map { try recognition($0.pointee) },
            recognitionArchive: bytes(value.recognition_archive),
            disabledAreas: array(value.disabled_areas, value.disabled_area_count, rect),
            metadata: metadata(value.metadata), palette: palette,
            textBoxes: array(value.text_boxes, value.text_box_count) {
                try SNTextBox(id: $0.id, rect: rect($0.rect), text: string($0.text) ?? "",
                              fontSize: $0.has_font_size ? $0.font_size : nil, fontPath: string($0.font_path),
                              timestamp: string($0.timestamp),
                              attributes: array($0.attributes, $0.attribute_count) { try string($0) ?? "" })
            }
        )
    }

    func info(_ value: sn_layer_info) throws -> SNLayerInfo {
        try SNLayerInfo(layerID: Int(value.layer_id), name: string(value.name) ?? "", isBackground: value.is_background,
                        isVisible: value.is_visible, isDeleted: value.is_deleted, isCurrent: value.is_current)
    }

    func layer(_ value: sn_layer) throws -> SNLayer {
        guard let key = sn_layer_name_key(value.name), let name = SNLayer.Name(key: String(cString: key)) else {
            throw SNParseError.malformed("unknown layer name")
        }
        return try SNLayer(name: name, bitmap: value.bitmap.map { try bitmap($0.pointee) },
                           info: value.info.map { try info($0.pointee) }, metadata: metadata(value.metadata),
                           isStacked: value.is_stacked)
    }

    func category(_ value: sn_stroke) -> SNStroke.Category {
        switch value.category {
        case SN_CATEGORY_ORDINARY: .ordinary
        case SN_CATEGORY_HEADING: .heading
        case SN_CATEGORY_TEXT_BOX: .textBox
        case SN_CATEGORY_PICTURE_LINK: .pictureLink
        case SN_CATEGORY_TEXT_LINK: .textLink
        case SN_CATEGORY_LINK: .link
        default: .other(value.style)
        }
    }

    func stroke(_ value: sn_stroke) throws -> SNStroke {
        try SNStroke(id: value.id, pen: .init(rawValue: value.pen), color: .init(rawValue: value.color),
                     thickness: value.thickness, kind: .init(name: string(value.kind_name) ?? ""),
                     role: .init(rawValue: value.role_raw), status: .init(rawValue: value.status_raw),
                     operation: value.operation, layer: Int(value.layer), pageNumber: Int(value.page_number),
                     points: array(value.points, value.point_count) {
                         SNStrokePoint(position: CGPoint(x: $0.position.x, y: $0.position.y), pressure: $0.pressure)
                     },
                     contour: array(value.contours, value.contour_count) {
                         try array($0.points, $0.count) { CGPoint(x: $0.x, y: $0.y) }
                     },
                     bounds: rect(value.bounds), style: value.has_style ? value.style : nil,
                     attributes: array(value.attributes, value.attribute_count) { try string($0) ?? "" },
                     category: category(value), isDrawn: value.is_drawn)
    }

    func recognition(_ value: sn_recognition) throws -> SNRecognition {
        try SNRecognition(elements: array(value.elements, value.element_count) { element in
            try .init(kind: string(element.kind) ?? "", label: string(element.label),
                      words: array(element.words, element.word_count) {
                          try .init(label: string($0.label) ?? "", box: $0.box.is_null ? nil : rect($0.box))
                      })
        })
    }
}
