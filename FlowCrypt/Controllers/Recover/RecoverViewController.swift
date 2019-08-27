//
// © 2017-2019 FlowCrypt Limited. All rights reserved.
//

import UIKit
import MBProgressHUD
import RealmSwift
import Promises

final class RecoverViewController: UIViewController {
    private enum Constants {
        static let noBackups = "No backups found on this account"
        static let actionFailed = "Action failed"
        static let useOtherAccount = "Use other account"
        static let enterPassPhrase = "Enter pass phrase"
        static let wrongPassPhraseRetry = "Wrong pass phrase, please try again"
    }
    // TODO: Inject as a dependency
    private let imap = Imap.instance
    private let googleApi = GoogleApi.shared

    @IBOutlet weak var passPhaseTextField: UITextField!
    @IBOutlet weak var btnLoadAccount: UIButton!
    @IBOutlet weak var scrollView: UIScrollView!
    
    private var encryptedBackups: [KeyDetails] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        fetchBackups()

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        btnLoadAccount.layer.cornerRadius = 5
    }
}

extension RecoverViewController {
    private func observeKeyboardNotifications() {
        _ = keyboardHeight
            .map { UIEdgeInsets(top: 0, left: 0, bottom: $0 + 5, right: 0) }
            .subscribe(onNext: { [weak self] inset in
                self?.scrollView.contentInset = inset
                self?.scrollView.scrollIndicatorInsets = inset
            })
    }

    private func setupUI() {
        UITapGestureRecognizer(target: self, action: #selector(endEditing)).do {
            $0.cancelsTouchesInView = false
            self.view.addGestureRecognizer($0)
        }
        passPhaseTextField.delegate = self

        observeKeyboardNotifications()
    }

    private func fetchBackups() {
        showSpinner()

        imap.searchBackups(email: googleApi.getEmail())
            .then { data -> [KeyDetails] in
                let keyDetailsRes = try Core.parseKeys(armoredOrBinary: data)
                return keyDetailsRes.keyDetails
            }
            .then(on: .main) { [weak self] keyDetails in
                guard let self = self else { return }
                self.hideSpinner()
                let encryptedBackups = keyDetails.filter { $0.private != nil }
                self.encryptedBackups = encryptedBackups
                if encryptedBackups.isEmpty {
                    self.showRetryFetchBackupsOrChangeAcctAlert(msg: Constants.noBackups)
                }
            }
            .catch(on: .main) { [weak self] in
                let message = "\(Constants.actionFailed)\n\n\($0)"
                self?.showRetryFetchBackupsOrChangeAcctAlert(msg: message)
            }
    }

    private func showRetryFetchBackupsOrChangeAcctAlert(msg: String) {
        let alert = UIAlertController(title: "Notice", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in self.fetchBackups() })
        alert.addAction(UIAlertAction(title: Constants.useOtherAccount, style: .default) { [weak self] _ in
            self?.handleForOtherAccount()
        })
        present(alert, animated: true, completion: nil)
    }

    private func handleForOtherAccount() {
        googleApi.signOut()
            .then(on: .main) { [weak self] _ in
                let signInVc = UIStoryboard.main.instantiate(SignInViewController.self)
                self?.navigationController?.pushViewController(signInVc, animated: true)
            }
            .catch {
                self.showAlert(error: $0, message: "")
            }
    }
}

extension RecoverViewController {
    @objc private func endEditing() {
        view.endEditing(true)
    }

    @IBAction func loadAccountButtonPressed(_ sender: Any) {
        guard let passPrase = passPhaseTextField.text, passPrase.isEmpty else {
            showAlert(message: Constants.enterPassPhrase)
            return
        }

        showSpinner()


        let matchingBackups: [KeyDetails] = encryptedBackups
            .compactMap { (key) -> KeyDetails? in
                guard let privateKey = key.private else { return nil }
                do {
                    let decryptRes = try Core.decryptKey(armoredPrv: privateKey, passphrase: passPrase)
                    if decryptRes.decryptedKey != nil {
                        return key
                    }
                    return nil
                } catch {
                    return nil
                }
            }

        guard matchingBackups.count > 0 else {
            showAlert(message: Constants.wrongPassPhraseRetry)
            return
        }

        // TODO: - Refactor with realm service
        let realm = try! Realm()
        try! realm.write {
            for k in matchingBackups {
                realm.add(try! KeyInfo(k, passphrase: Constants.enterPassPhrase, source: .backup))
            }
        }

        performSegue(withIdentifier: "InboxSegue", sender: nil)
    }
}

extension RecoverViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        view.endEditing(true)
        return true
    }
}
