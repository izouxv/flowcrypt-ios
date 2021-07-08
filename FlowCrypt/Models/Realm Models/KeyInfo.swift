//
// © 2017-2019 FlowCrypt Limited. All rights reserved.
//

import RealmSwift

enum KeySource: String {
    case backup
    case generated
    case imported
}

enum KeyInfoError: Error {
    case missedPrivateKey(String)
    case notEncrypted(String)
}

final class KeyInfo: Object {
    @objc dynamic var `private`: String = ""
    @objc dynamic var `public`: String = ""
    @objc dynamic var longid: String = ""
    @objc dynamic var source: String = ""
    @objc dynamic var user: UserObject!

    convenience init(_ keyDetails: KeyDetails, source: KeySource, user: UserObject) throws {
        self.init()

        guard let privateKey = keyDetails.private else {
            assertionFailure("storing pubkey as private") // crash tests
            throw KeyInfoError.missedPrivateKey("storing pubkey as private")
        }
        guard keyDetails.isFullyEncrypted! else { // already checked private above, must be set, else crash
            assertionFailure("Will not store Private Key that is not fully encrypted") // crash tests
            throw KeyInfoError.notEncrypted("Will not store Private Key that is not fully encrypted")
        }
        self.`private` = privateKey
        self.`public` = keyDetails.public
        self.longid = keyDetails.longid
        self.source = source.rawValue
        self.user = user
    }

    override class func primaryKey() -> String? {
        "private"
    }

    override var description: String {
        "account = \(user?.email ?? "N/A") ####### longid = \(longid)"
    }
}

extension KeyInfo {
    /// associated user email
    var account: String {
        user.email
    }
}
