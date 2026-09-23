import Foundation
import XCTest
@testable import AWLogger

final class LoggerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AWLogger-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        SwiftyBeaver.removeAllDestinations()
    }

    override func tearDownWithError() throws {
        _ = SwiftyBeaver.flush(secondTimeout: 5)
        SwiftyBeaver.removeAllDestinations()
        try FileManager.default.removeItem(at: directory)
    }

    private func makeDestinations(maximumFileSize: Int = LogDestinations.maximumFileSize) -> LogDestinations {
        let destinations = LogDestinations(
            logFileURL: directory.appendingPathComponent("smartCHECK.log"),
            appName: "smartCHECK", version: "1.2.3", build: "456",
            maximumFileSize: maximumFileSize
        )
        SwiftyBeaver.removeDestination(destinations.console)
        return destinations
    }

    func testPublicInitializerRegistersDestinationsOnlyOnceUnderConcurrency() throws {
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "logfile"
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let defaultLogURL = cacheDirectory.appendingPathComponent(appName + ".log")
        let logAlreadyExisted = FileManager.default.fileExists(atPath: defaultLogURL.path)
        defer {
            _ = SwiftyBeaver.flush(secondTimeout: 5)
            if !logAlreadyExisted { try? FileManager.default.removeItem(at: defaultLogURL) }
        }

        DispatchQueue.concurrentPerform(iterations: 40) { _ in
            _ = Logger()
        }
        XCTAssertEqual(SwiftyBeaver.countDestinations(), 2)
        XCTAssertEqual(Logger().logFileURL, defaultLogURL)
        XCTAssertEqual(SwiftyBeaver.countDestinations(), 2)
    }

    func testSharedDestinationsLogEachMessageOnceAcrossConcurrentLoggerInstances() throws {
        let destinations = makeDestinations()
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            Logger(destinations: destinations).info("unique-entry-\(index)-end")
        }
        let logger = Logger(destinations: destinations)
        let snapshot = try logger.makeLogSnapshot()
        defer { try? FileManager.default.removeItem(at: snapshot) }

        XCTAssertEqual(SwiftyBeaver.countDestinations(), 1)
        XCTAssertEqual(destinations.file.logFileMaxSize, 20 * 1024 * 1024)
        XCTAssertEqual(destinations.file.logFileAmount, 5)
        let text = try String(contentsOf: snapshot.appendingPathComponent("smartCHECK.log"), encoding: .utf8)
        for index in 0..<40 {
            XCTAssertEqual(text.components(separatedBy: "unique-entry-\(index)-end").count - 1, 1)
        }
        XCTAssertEqual(text.components(separatedBy: "Logging session started:").count - 1, 1)
        XCTAssertTrue(text.contains("app=smartCHECK version=1.2.3 build=456"))
        XCTAssertTrue(logger.flush(secondTimeout: 5))
    }

    func testEveryEntryHasDateTimeZoneAndSessionIdentity() throws {
        let destinations = makeDestinations()
        Logger(destinations: destinations).info("dated-entry")
        let snapshot = try destinations.makeSnapshot()
        defer { try? FileManager.default.removeItem(at: snapshot) }
        let text = try String(contentsOf: snapshot.appendingPathComponent("smartCHECK.log"), encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(?:Z|[+-]\d{2}:\d{2}) \[session=[A-F0-9-]{36} pid=\d+\] INFO "#
        )
        for line in text.split(separator: "\n") {
            XCTAssertNotNil(expression.firstMatch(in: String(line), range: NSRange(line.startIndex..., in: line)))
            XCTAssertTrue(line.contains("session=\(destinations.sessionID)"))
        }
    }

    func testSnapshotIncludesFiveSegmentsAndStaysStableAfterFurtherRotation() throws {
        let destinations = makeDestinations(maximumFileSize: 500)
        let logger = Logger(destinations: destinations)
        for index in 0..<20 { logger.info(rotationMessage(index)) }
        let snapshot = try logger.makeLogSnapshot()
        defer { try? FileManager.default.removeItem(at: snapshot) }

        let names = try FileManager.default.contentsOfDirectory(atPath: snapshot.path).sorted()
        XCTAssertEqual(names, ["smartCHECK.1.log", "smartCHECK.2.log", "smartCHECK.3.log", "smartCHECK.4.log", "smartCHECK.log"])
        XCTAssertEqual(try rotationEntries(in: snapshot), Array(15..<20))
        let originalData = try names.map { try Data(contentsOf: snapshot.appendingPathComponent($0)) }

        for index in 20..<40 { logger.info(rotationMessage(index)) }
        let laterSnapshot = try logger.makeLogSnapshot()
        defer { try? FileManager.default.removeItem(at: laterSnapshot) }
        XCTAssertNotEqual(snapshot, laterSnapshot)
        XCTAssertEqual(try rotationEntries(in: laterSnapshot), Array(35..<40))
        XCTAssertEqual(try names.map { try Data(contentsOf: snapshot.appendingPathComponent($0)) }, originalData)
    }

    func testConcurrentRotationProducesConsistentSnapshotsWithoutMissingEntries() throws {
        let destinations = makeDestinations(maximumFileSize: 500)
        let worker = DispatchGroup()
        worker.enter()
        DispatchQueue.global().async {
            let logger = Logger(destinations: destinations)
            for index in 0..<100 { logger.info(Self.message(index)) }
            worker.leave()
        }
        for _ in 0..<12 {
            let snapshot = try destinations.makeSnapshot()
            defer { try? FileManager.default.removeItem(at: snapshot) }
            let entries = try rotationEntries(in: snapshot)
            if let first = entries.first, let last = entries.last {
                XCTAssertEqual(entries, Array(first...last))
                XCTAssertLessThanOrEqual(entries.count, 5)
            }
        }
        XCTAssertEqual(worker.wait(timeout: .now() + 10), .success)
        let finalSnapshot = try destinations.makeSnapshot()
        defer { try? FileManager.default.removeItem(at: finalSnapshot) }
        XCTAssertEqual(try rotationEntries(in: finalSnapshot), Array(95..<100))
    }

    func testSnapshotExcludesUnrelatedAndUnretainedFiles() throws {
        let destinations = makeDestinations()
        try Data("unrelated".utf8).write(to: directory.appendingPathComponent("other.log"))
        try Data("expired".utf8).write(to: directory.appendingPathComponent("smartCHECK.9.log"))
        let snapshot = try destinations.makeSnapshot()
        defer { try? FileManager.default.removeItem(at: snapshot) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: snapshot.path), ["smartCHECK.log"])
    }

    func testMissingLogsThrowsAndCleansPartialSnapshot() throws {
        let destinations = makeDestinations()
        try destinations.file.executeSynchronously {
            try FileManager.default.removeItem(at: self.directory.appendingPathComponent("smartCHECK.log"))
        }
        let before = try snapshotDirectoryNames()
        XCTAssertThrowsError(try destinations.makeSnapshot())
        XCTAssertEqual(try snapshotDirectoryNames(), before)
    }

    private func snapshotDirectoryNames() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("AWLogger-snapshot-") })
    }

    private func rotationMessage(_ index: Int) -> String { Self.message(index) }

    private static func message(_ index: Int) -> String {
        "rotation-entry-\(String(format: "%04d", index)) " + String(repeating: "x", count: 600)
    }

    private func rotationEntries(in snapshot: URL) throws -> [Int] {
        let orderedNames = (1...4).reversed().map { "smartCHECK.\($0).log" } + ["smartCHECK.log"]
        let expression = try NSRegularExpression(pattern: #"rotation-entry-(\d{4})"#)
        return try orderedNames.flatMap { name -> [Int] in
            let fileURL = snapshot.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            return expression.matches(in: content, range: NSRange(content.startIndex..., in: content)).compactMap {
                Range($0.range(at: 1), in: content).flatMap { Int(content[$0]) }
            }
        }
    }
}
