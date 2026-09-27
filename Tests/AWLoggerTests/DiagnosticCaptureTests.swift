import Foundation
import XCTest
@testable import AWLogger

final class DiagnosticCaptureTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testBoundedRotationAndImmutableSnapshot() throws {
        let capture = DiagnosticCapture(file: root.appendingPathComponent("capture.jsonl"), maximumBytes: 120, retainedFiles: 2)
        for index in 0..<12 { capture.append(Data("{\"event\":\(index),\"padding\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}".utf8)) }
        let snapshot = try capture.snapshot()
        defer { try? FileManager.default.removeItem(at: snapshot) }
        let files = try FileManager.default.contentsOfDirectory(at: snapshot, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("capture.jsonl") }
        XCTAssertEqual(files.count, 2)
        let contents = try files.map { try Data(contentsOf: $0) }
        XCTAssertTrue(contents.allSatisfy { $0.count <= 120 })
        XCTAssertTrue(contents.contains { String(decoding: $0, as: UTF8.self).contains("\"event\":11") })
        for _ in 0..<10 { capture.append(Data("{\"later\":true}".utf8)) }
        XCTAssertTrue(capture.flush(timeout: 5))
        XCTAssertEqual(try files.map { try Data(contentsOf: $0) }, contents)
    }

    func testOversizedEntryIsDroppedAndCounted() throws {
        let capture = DiagnosticCapture(file: root.appendingPathComponent("capture.jsonl"), maximumBytes: 64)
        capture.append(Data(repeating: 65, count: 100))
        XCTAssertEqual(capture.health["droppedMessages"], 1)
        capture.append(Data("{\"ok\":true}".utf8))
        XCTAssertTrue(capture.flush(timeout: 5))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("capture.jsonl"), encoding: .utf8), "{\"ok\":true}\n")
    }

    func testWriteFailureDoesNotEscapeAndIsCounted() throws {
        let obstacle = root.appendingPathComponent("file")
        try Data().write(to: obstacle)
        let capture = DiagnosticCapture(file: obstacle.appendingPathComponent("capture.jsonl"))
        capture.append(Data("{\"event\":1}".utf8))
        XCTAssertTrue(capture.flush(timeout: 5))
        XCTAssertEqual(capture.health["writeFailures"], 1)
    }

    func testRedactionRemovesCredentialsAndAccountIdentifiers() {
        let value = DiagnosticRedaction.redact("url?token=secret&api_key=other Authorization: Bearer abc.def uid=person user@example.com")
        for secret in ["secret", "other", "abc.def", "person", "user@example.com"] { XCTAssertFalse(value.contains(secret)) }
    }
}
