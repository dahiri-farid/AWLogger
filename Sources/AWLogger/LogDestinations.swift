import Foundation
import SwiftyBeaver

/// Configuration is immutable after initialization. File writes and snapshots are serialized
/// by FileDestination's queue; SwiftyBeaver synchronizes its process-wide destination registry.
internal final class LogDestinations: @unchecked Sendable {
    static let maximumFileSize = 20 * 1024 * 1024
    static let retainedFileCount = 5

    let file: FileDestination
    let console: ConsoleDestination
    let sessionID: String

    convenience init() {
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "logfile"
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.init(
            logFileURL: directory.appendingPathComponent(appName + ".log"),
            appName: appName,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        )
    }

    init(
        logFileURL: URL,
        appName: String,
        version: String,
        build: String,
        maximumFileSize: Int = LogDestinations.maximumFileSize,
        retainedFileCount: Int = LogDestinations.retainedFileCount
    ) {
        sessionID = UUID().uuidString
        let format = "$Dyyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ$d [session=\(sessionID) pid=\(ProcessInfo.processInfo.processIdentifier)] $L $N.$F:$l - $M"
        console = ConsoleDestination()
        console.logPrintWay = .logger(subsystem: "Main", category: "UI")
        console.format = format

        file = FileDestination(logFileURL: logFileURL)
        file.logFileMaxSize = maximumFileSize
        file.logFileAmount = retainedFileCount
        file.format = format

        SwiftyBeaver.addDestination(console)
        SwiftyBeaver.addDestination(file)
        SwiftyBeaver.info("Logging session started: app=\(appName) version=\(version) build=\(build)")
    }

    func makeSnapshot() throws -> URL {
        try file.executeSynchronously { [self] in
            guard let logFileURL = file.logFileURL else {
                throw CocoaError(.fileNoSuchFile)
            }
            let manager = FileManager.default
            let snapshot = manager.temporaryDirectory
                .appendingPathComponent("AWLogger-snapshot-\(UUID().uuidString)", isDirectory: true)
            try manager.createDirectory(at: snapshot, withIntermediateDirectories: false)
            do {
                // The highest rotation index is the oldest. Keep the original names in the
                // snapshot so exporters can preserve that order without reading file contents.
                var segments: [URL] = []
                if file.logFileAmount > 1 {
                    for index in stride(from: file.logFileAmount - 1, through: 1, by: -1) {
                        segments.append(logFileURL.deletingPathExtension()
                            .appendingPathExtension("\(index).\(logFileURL.pathExtension)"))
                    }
                }
                segments.append(logFileURL)
                var copiedCount = 0
                for segment in segments where manager.fileExists(atPath: segment.path) {
                    try manager.copyItem(at: segment, to: snapshot.appendingPathComponent(segment.lastPathComponent))
                    copiedCount += 1
                }
                guard copiedCount > 0 else { throw CocoaError(.fileNoSuchFile) }
                return snapshot
            } catch {
                try? manager.removeItem(at: snapshot)
                throw error
            }
        }
    }
}
