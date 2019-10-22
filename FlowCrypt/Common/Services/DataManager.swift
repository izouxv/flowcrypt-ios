//
//  DataManager.swift
//  FlowCrypt
//
//  Created by Anton Kharchevskyi on 8/28/19.
//  Copyright © 2019 FlowCrypt Limited. All rights reserved.
//

import Foundation

protocol DataManagerType {
    func saveToken(with string: String)
    func currentToken() -> String?
    func saveCurrent(user: User) -> Bool
    func currentUser() -> User?
    func logOut()
}

struct DataManager: DataManagerType {
    // TODO: - safe in keychain
    static let shared = DataManager()

    private enum Constants {
        static let userKey = "keyCurrentUser"
        static let tokenKey = "keyCurrentToken"
    }

    private let userDefaults: UserDefaults

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func saveToken(with string: String) {
        userDefaults.set(string, forKey: Constants.tokenKey)
    }

    func currentToken() -> String? {
        return userDefaults.string(forKey: Constants.tokenKey)
    }

    func saveCurrent(user: User) -> Bool {
        do {
            let encodedData = try PropertyListEncoder().encode(user)
            userDefaults.set(encodedData, forKey: Constants.userKey)
            return true
        } catch {
            print(error)
            return false
        }
    }

    func currentUser() -> User? {
        guard let data = userDefaults.object(forKey: Constants.userKey) as? Data else { return nil }
        return try? PropertyListDecoder().decode(User.self, from: data)
    }

    func logOut() {
        [Constants.tokenKey, Constants.userKey]
            .forEach { userDefaults.removeObject(forKey: $0) }
    }
}
