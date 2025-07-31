//
//  Logging.swift
//  I_EFIS
//
//  Created by Farid Dahiri on 28.02.2025.
//  Copyright © 2025 FU-airWORK. All rights reserved.
//

import Foundation

@objc
public protocol Logging: AnyObject {
    @objc
    var logFileURL: URL? { get }
    
    @objc
    func verbose(_ message: Any, file: String, function: String, line: Int)
    @objc
    func debug(_ message: Any, file: String, function: String, line: Int)
    @objc
    func info(_ message: Any, file: String, function: String, line: Int)
    @objc
    func warning(_ message: Any, file: String, function: String, line: Int)
    @objc
    func error(_ message: Any, file: String, function: String, line: Int)
}
