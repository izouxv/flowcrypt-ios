//
//  UIViewControllerExtension.swift
//  FlowCrypt
//
//  Created by Anton Kharchevskyi on 8/20/19.
//  Copyright © 2019 FlowCrypt Limited. All rights reserved.
//

import UIKit
import Toast
import RxSwift
import RxCocoa
import MBProgressHUD

enum ToastPosition: String {
    case bottom, top, center

    var value: String {
        switch self {
        case .bottom: return CSToastPositionBottom
        case .center: return CSToastPositionCenter
        case .top:    return CSToastPositionTop
        }
    }
}

typealias ShowToastCompletion = (Bool) -> Void

extension UIViewController {

    /// Showing toast on root controller
    ///
    /// - Parameters:
    ///   - message: Message to be shown
    ///   - title: Title for the toast
    ///   - duration: Toast presented duration. Default is 3.0
    ///   - position: Bottom by default. Can be top, center, bottom.
    ///   - completion: Notify when toast dissapeared
    func showToast(
        _ message: String,
        title: String? = nil,
        duration: TimeInterval = 3.0,
        position: ToastPosition = .bottom,
        completion: ShowToastCompletion? = nil
    ) {
        DispatchQueue.main.async {
            guard let view = UIApplication.shared.keyWindow?.rootViewController?.view else {
                assertionFailure("Key window hasn't rootViewController")
                return
            }
            view.hideAllToasts()

            view.makeToast(
                message,
                duration: duration,
                position: position.value,
                title: title,
                image: nil,
                style: CSToastStyle.init(defaultStyle: ()),
                completion: completion
            )

            CSToastManager.setTapToDismissEnabled(true)
        }
    }
}

extension UIViewController {
    /// Observable keyboard height from willShow and willHide notifications
    /// deliver signals on main queue.
    var keyboardHeight: Observable<CGFloat> {
        let willShowNotification = NotificationCenter.default.rx
            .notification(UIResponder.keyboardWillShowNotification)
            .map { notification in
                (notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue.height ?? 0
        }
        let willHideNotification = NotificationCenter.default.rx
            .notification(UIResponder.keyboardWillHideNotification)
            .map { _ in return CGFloat(0) }

        return Observable.from([willShowNotification, willHideNotification])
            .merge()
            .observeOn(MainScheduler.instance)
            .takeUntil(rx.deallocated)
    }
}

extension UIViewController {
    func showAlert(error: Error, message: String, onOk: (() -> Void)? = nil) {
        let message = "\(message)\n\n \(error)"
        showAlert(message: message, onOk: onOk)
    }

    func showAlert(message: String, onOk: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            self.view.hideAllToasts()
            self.hideSpinner()
            let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .destructive) { action in onOk?() })
            self.present(alert, animated: true, completion: nil)
        }
    }

    func showSpinner(_ message: String = Language.loading, isUserInteractionEnabled: Bool = false) {
        DispatchQueue.main.async {
            let spinner = MBProgressHUD.showAdded(to: self.view, animated: true)
            spinner.label.text = message
            spinner.isUserInteractionEnabled = isUserInteractionEnabled
        }
    }

    func hideSpinner() {
        DispatchQueue.main.async {
            self.view.subviews
                .compactMap { $0 as? MBProgressHUD }
                .forEach { $0.hide(animated: true) }
        }
    }
}
