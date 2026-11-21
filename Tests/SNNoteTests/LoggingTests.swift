// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SNNote
import Synchronization
import Testing

// The diagnostics sink is process-wide, so these run one at a time and each
// leaves silence behind.
@Suite(.serialized)
struct LoggingTests {
    // Other suites can parse on other tasks while the process-wide sink is installed.
    @TaskLocal private static var recording = false

    @Test func aLostStrokeIsReportedAsAnError() throws {
        let lines = Mutex<[(SNNoteLog.Level, String)]>([])
        SNNoteLog.install { level, message in
            if Self.recording { lines.withLock { $0.append((level, message)) } }
        }
        defer { SNNoteLog.silence() }

        let bad = Data(count: 20)
        let good = NoteBuilder.strokeRecord(id: 7)
        let cases: [([Data], [Int32], Int)] = [
            ([bad], [], 1), ([bad, good], [7], 1), ([good, bad], [7], 1),
            ([bad, good, bad, NoteBuilder.strokeRecord(id: 9)], [7, 9], 2),
        ]
        for (records, ids, skipped) in cases {
            let log = NoteBuilder.strokeLog(records)
            let notebook = try Self.$recording.withValue(true) {
                try SNParser.parse(NoteBuilder.onePage(strokeLog: log))
            }
            let page = try #require(notebook.pages.first)
            #expect(page.skippedStrokes == skipped)
            #expect(page.strokes.map(\.id) == ids)
            let callbacks = lines.withLock { buffer in
                defer { buffer.removeAll() }
                return buffer
            }
            #expect(callbacks.map(\.0) == Array(repeating: .error, count: skipped))
            #expect(callbacks.map(\.1) == Array(repeating: "stroke record does not read", count: skipped))
        }
    }

    @Test func silenceIsTheDefault() throws {
        let lines = Mutex(0)
        SNNoteLog.install { _, _ in lines.withLock { $0 += 1 } }
        SNNoteLog.silence()
        _ = try SNParser.parse(NoteBuilder.onePage(strokeLog: NoteBuilder.strokeLog([Data(count: 20)])))
        #expect(lines.withLock { $0 } == 0)
    }

    /// The handwriting's text never reaches a sink: messages are counts,
    /// offsets and key names.
    @Test func recognisedTextIsNeverLogged() throws {
        let lines = Mutex<[String]>([])
        SNNoteLog.install { _, message in lines.withLock { $0.append(message) } }
        defer { SNNoteLog.silence() }
        _ = try Corpus.notebook("turkish-a6x-20230015-handwriting-erase.note")
        #expect(lines.withLock { $0 }.allSatisfy { !$0.contains("çıktım") })
    }
}
