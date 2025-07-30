//
//  Logger.swift
//  iEFIS Pro Beta
//
//  Created by Farid Dahiri on 05.03.2025.
//  Copyright © 2025 FU-airWORK. All rights reserved.
//

import Foundation
import SwiftyBeaver

@objc
public class Logger: NSObject, Logging {
    public var logFileURL: URL? {
        baseURL?.appendingPathComponent(logFilename, isDirectory: false)
    }
    let baseURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    private let logger = SwiftyBeaver.self
    let logFilename: String = {
        let name: String
        if let displayName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String {
            name = displayName
        } else if let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String {
            name = bundleName
        } else {
            name = "logfile"
        }
        
        // e.g. "MyApp.log"
        let filename = name + ".log"
        
        return filename
    }()
    public override init() {
        // add log destinations. at least one is needed!
        let console = ConsoleDestination() // log to Xcode Console
        
        // In Xcode 15, specifying the logging method as .logger to display color, subsystem, and category information in the console.(Relies on the OSLog API)
        console.logPrintWay = .logger(subsystem: "Main", category: "UI")
        // If you prefer not to use the OSLog API, you can use print instead.
        // console.logPrintWay = .print
        
        // iOS, watchOS, etc. are using the caches directory

        
        let file = FileDestination(
            logFileURL: baseURL?.appendingPathComponent(logFilename, isDirectory: false)
        )
        file.logFileAmount = 2
        
        // add the destinations to SwiftyBeaver
        logger.addDestination(console)
        logger.addDestination(file)
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

