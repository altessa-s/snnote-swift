// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

internal import CSNNote
import Synchronization

/// Where the parser's diagnostics go.
///
/// This package reads bytes and does nothing else: no logger of its own, no
/// opinion about files or the system log, and no dependency on the host that
/// hands it a notebook. What it does have is a handful of lines worth saying
/// out loud — a stroke record it could not walk, a layer whose bitmap is in a
/// protocol it does not know, a page whose block points past the end of the
/// file. Each one is a piece of a notebook that will not be shown, and the
/// kind of thing found months later because nothing ever said it.
///
/// So the lines go to whatever the host installed, and to nothing at all until
/// it does. Silence is the supported default — a test wants no log —
/// rather than `print`, because a library that writes to a terminal nobody is
/// watching is a library that has to be worked around.
///
/// Nothing here is ever a secret: every value in every message is a count, an
/// offset, a key name or a raw number. The handwriting, the recognised text and
/// the file names never reach a sink, so a host is free to install one that
/// writes a file and keep it.
public enum SNNoteLog {
    /// How much the line matters. Two levels and not five: a piece of the
    /// notebook was lost (`error`), or the file held something this parser
    /// does not know and read past (`debug`).
    ///
    /// Frozen: an exhaustive `switch` over these cases in a consumer is the
    /// point. A new case must break its build, not fall into an
    /// `@unknown default`.
    @frozen
    public enum Level: Sendable {
        case debug
        case error
    }

    /// What a host installs. Called on whichever thread parsed the notebook,
    /// and a sink that touches shared state must say so itself.
    public typealias Sink = @Sendable (Level, String) -> Void

    /// Name the sink for this process. Once, at its start, from the
    /// composition root; a later call replaces the earlier one.
    public static func install(_ sink: @escaping Sink) {
        installed.withLock {
            $0 = sink
            sn_log_install({ level, message, _ in
                guard let message, let sink = SNNoteLog.installed.withLock({ $0 }) else { return }
                sink(level == SN_LOG_ERROR ? .error : .debug, String(cString: message))
            }, nil)
        }
    }

    /// Go back to silence. For a test that installed a sink and must not leave
    /// it behind for the next one.
    public static func silence() {
        installed.withLock {
            sn_log_silence()
            $0 = nil
        }
    }

    private static let installed = Mutex<Sink?>(nil)
}
