//
//  AppBundle.swift
//  FlowCrypt
//
//  Created by Tom on 03.12.2021
//  Copyright © 2017-present FlowCrypt a. s. All rights reserved.
//

import Foundation

public enum FlowCryptBundleType: String {
    case debug = "com.flowcrypt.as.ios.debug"
    case consumer = "com.flowcrypt.as.ios.consumer"
    case enterprise = "com.flowcrypt.as.ios.enterprise"
}

extension Bundle {

    static var flowCryptBundleType: FlowCryptBundleType {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return .debug }
        return FlowCryptBundleType(rawValue: bundleIdentifier) ?? .debug
    }

    static func isDebugBundleWithArgument(_ argument: String) -> Bool {
        guard Bundle.flowCryptBundleType == .debug else { return false }
        return CommandLine.arguments.contains(argument)
    }

    public static var shouldUseMockGmailApi: Bool {
        isDebugBundleWithArgument("--mock-gmail-api")
    }

    public static var shouldUseMockFesApi: Bool {
        isDebugBundleWithArgument("--mock-fes-api")
    }

    public static var shouldUseMockAttesterApi: Bool {
        isDebugBundleWithArgument("--mock-attester-api")
    }

    public static var isEnterprise: Bool {
        if flowCryptBundleType == .enterprise {
            return true // for production
        }
        if isDebugBundleWithArgument("--enterprise") {
            return true // for ui tests of enterprise functionality
        }
        return false
    }
}
