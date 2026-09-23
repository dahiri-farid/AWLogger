//
//  Logger.swift
//  iEFIS Pro Beta
//
//  Created by Farid Dahiri on 05.03.2025.
//  Copyright © 2025 FU-airWORK. All rights reserved.
//

import Foundation
@_exported import SwiftyBeaver

@objc
public class Logger: NSObject, Logging {
    // Swift initializes a static let once, including when callers arrive on different threads.
    private static let sharedDestinations = LogDestinations()
    private let destinations: LogDestinations
    private let logger = SwiftyBeaver.self

    public var logFileURL: URL? { destinations.file.logFileURL }

    public override init() {
        destinations = Self.sharedDestinations
        super.init()
    }

    internal init(destinations: LogDestinations) {
        self.destinations = destinations
        super.init()
    }

    /// Copies every retained segment into a unique temporary directory.
    ///
    /// The caller owns the returned directory and must remove it after exporting. The copies
    /// are made on the logging queue, after preceding writes and without concurrent rotation.
    /// Call this off the main thread because copying retained logs can take time.
    public func makeLogSnapshot() throws -> URL {
        try destinations.makeSnapshot()
    }

    /// Waits for queued writes before suspension or termination, up to the supplied timeout.
    @discardableResult
    public func flush(secondTimeout: Int64 = 1) -> Bool {
        logger.flush(secondTimeout: secondTimeout)
    }
    
    public func verbose(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
        logger.verbose(message, file: file, function: function, line: line)
    }
    
    public func debug(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
        logger.debug(message, file: file, function: function, line: line)
    }
    
    public func info(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
        logger.info(message, file: file, function: function, line: line)
    }
    
    public func warning(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
        logger.warning(message, file: file, function: function, line: line)
    }
    
    public func error(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
        logger.error(message, file: file, function: function, line: line)
    }
}
