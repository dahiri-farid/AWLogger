import Foundation

/// Bounded JSONL recording for optional diagnostics. All file operations run on one queue.
public final class DiagnosticCapture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "awlogger.diagnostic-capture", qos: .utility)
    private let lock = NSLock()
    private let file: URL
    private let maximumBytes: Int
    private let retainedFiles: Int
    private let pendingLimit: Int
    private var pending = 0
    private var dropped = 0
    private var failures = 0
    private var handle: FileHandle?
    private var size = 0

    public init(file: URL, maximumBytes: Int = 2 * 1024 * 1024, retainedFiles: Int = 2, pendingLimit: Int = 128) {
        precondition(maximumBytes > 0 && retainedFiles > 0 && pendingLimit > 0)
        self.file = file
        self.maximumBytes = maximumBytes
        self.retainedFiles = retainedFiles
        self.pendingLimit = pendingLimit
    }

    public func append(_ data: Data) {
        lock.lock()
        guard pending < pendingLimit, data.count + 1 <= min(maximumBytes, 32 * 1024) else {
            dropped += 1
            lock.unlock()
            return
        }
        pending += 1
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); pending -= 1; lock.unlock() }
            do {
                try open()
                if size > 0 && size + data.count + 1 > maximumBytes { try rotate() }
                try handle?.write(contentsOf: data + Data([10]))
                size += data.count + 1
            } catch {
                lock.lock(); failures += 1; lock.unlock()
                try? handle?.close()
                handle = nil
            }
        }
    }

    public var health: [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return ["pendingMessages": pending, "droppedMessages": dropped, "writeFailures": failures,
                "maximumFileBytes": maximumBytes, "retainedFiles": retainedFiles]
    }

    @discardableResult public func flush(timeout: TimeInterval = 0.5) -> Bool {
        let done = DispatchSemaphore(value: 0)
        queue.async { [self] in
            do { try handle?.synchronize() }
            catch { lock.lock(); failures += 1; lock.unlock() }
            done.signal()
        }
        return done.wait(timeout: .now() + timeout) == .success
    }

    /// Caller owns the directory. Call off the main thread; copies cannot race rotation.
    public func snapshot() throws -> URL {
        try queue.sync {
            try handle?.synchronize()
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("sensor-capture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            do {
                for index in (0..<retainedFiles).reversed() {
                    let source = segment(index)
                    if FileManager.default.fileExists(atPath: source.path) {
                        try FileManager.default.copyItem(at: source, to: destination.appendingPathComponent(source.lastPathComponent))
                    }
                }
                let metadata = try JSONSerialization.data(withJSONObject: health, options: .sortedKeys)
                try metadata.write(to: destination.appendingPathComponent("capture-health.json"))
                return destination
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }
    }

    private func segment(_ index: Int) -> URL {
        index == 0 ? file : file.appendingPathExtension(String(index))
    }

    private func open() throws {
        guard handle == nil else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: file.path) {
            guard fm.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        }
        let opened = try FileHandle(forWritingTo: file)
        size = Int(try opened.seekToEnd())
        handle = opened
    }

    private func rotate() throws {
        try handle?.close()
        handle = nil
        let fm = FileManager.default
        let oldest = segment(retainedFiles - 1)
        if fm.fileExists(atPath: oldest.path) { try fm.removeItem(at: oldest) }
        if retainedFiles > 1 {
            for index in stride(from: retainedFiles - 2, through: 0, by: -1) {
                if fm.fileExists(atPath: segment(index).path) { try fm.moveItem(at: segment(index), to: segment(index + 1)) }
            }
        }
        try open()
    }

    deinit { try? handle?.close() }
}

public enum DiagnosticRedaction {
    public static func redact(_ message: String) -> String {
        var result = message
        for (pattern, replacement) in [
            (#"(?i)(\b(?:access_token|api[_-]?key|token|authorization|password|user[_-]?id|uid)\b["']?\s*[:=]\s*["']?)(?:Bearer\s+)?[^\s,;&"']+"#, "$1<redacted>"),
            (#"(?i)Bearer\s+[A-Za-z0-9._~+/-]+"#, "Bearer <redacted>"),
            (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "<email>")
        ] {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result
    }
}
