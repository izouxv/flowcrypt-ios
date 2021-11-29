//
//  ThreadDetailsViewController.swift
//  FlowCrypt
//
//  Created by Anton Kharchevskyi on 12.10.2021
//  Copyright © 2017-present FlowCrypt a. s. All rights reserved.
//

import AsyncDisplayKit
import FlowCryptUI
import FlowCryptCommon
import Foundation
import UIKit

final class ThreadDetailsViewController: TableNodeViewController {
    private lazy var logger = Logger.nested(Self.self)

    class Input {
        var rawMessage: Message
        var isExpanded: Bool
        var processedMessage: ProcessedMessage?

        init(message: Message, isExpanded: Bool) {
            self.rawMessage = message
            self.isExpanded = isExpanded
        }
    }

    private enum Parts: Int, CaseIterable {
        case thread, message
    }

    private let messageService: MessageService
    private let messageOperationsProvider: MessageOperationsProvider
    private let threadOperationsProvider: MessagesThreadOperationsProvider
    private let thread: MessageThread
    private let filesManager: FilesManagerType
    private var input: [ThreadDetailsViewController.Input]

    let trashFolderProvider: TrashFolderProviderType
    var currentFolderPath: String {
        thread.path
    }
    private let onComplete: MessageActionCompletion

    private lazy var attachmentManager = AttachmentManager(
        controller: self,
        filesManager: filesManager
    )

    init(
        messageService: MessageService = MessageService(),
        trashFolderProvider: TrashFolderProviderType = TrashFolderProvider(),
        messageOperationsProvider: MessageOperationsProvider = MailProvider.shared.messageOperationsProvider,
        threadOperationsProvider: MessagesThreadOperationsProvider,
        thread: MessageThread,
        filesManager: FilesManagerType = FilesManager(),
        completion: @escaping MessageActionCompletion
    ) {
        self.messageService = messageService
        self.threadOperationsProvider = threadOperationsProvider
        self.messageOperationsProvider = messageOperationsProvider
        self.trashFolderProvider = trashFolderProvider
        self.thread = thread
        self.filesManager = filesManager
        self.onComplete = completion
        self.input = thread.messages
            .sorted(by: >)
            .map { Input(message: $0, isExpanded: false) }

        super.init(node: TableNode())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        node.delegate = self
        node.dataSource = self

        setupNavigationBar()
        expandThreadMessage()
    }
}

extension ThreadDetailsViewController {
    private func expandThreadMessage() {
        let indexOfSectionToExpand = thread.messages.firstIndex(where: { $0.isMessageRead == false }) ?? input.count - 1
        let indexPath = IndexPath(row: 0, section: indexOfSectionToExpand + 1)
        handleExpandTap(at: indexPath)
    }

    private func handleExpandTap(at indexPath: IndexPath) {
        guard let threadNode = node.nodeForRow(at: indexPath) as? ThreadMessageSenderCellNode else {
            logger.logError("Fail to handle tap at \(indexPath)")
            return
        }

        input[indexPath.section - 1].isExpanded.toggle()

        if input[indexPath.section-1].isExpanded {
            UIView.animate(
                withDuration: 0.3,
                animations: {
                    threadNode.expandNode.view.alpha = 0
                },
                completion: { [weak self] _ in
                    guard let self = self else { return }

                    if let processedMessage = self.input[indexPath.section-1].processedMessage {
                        self.handleReceived(message: processedMessage, at: indexPath)
                    } else {
                        self.fetchDecryptAndRenderMsg(at: indexPath)
                    }
                }
            )
        } else {
            UIView.animate(withDuration: 0.3) {
                self.node.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
            }
        }
    }

    private func handleReplyTap(at indexPath: IndexPath) {
        composeNewMessage(at: indexPath, quoteType: .reply)
    }

    private func handleMenuTap(at indexPath: IndexPath) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(
            UIAlertAction(
                title: "forward".localized,
                style: .default) { [weak self] _ in
                    self?.composeNewMessage(at: indexPath, quoteType: .forward)
                }
            )
        alert.addAction(UIAlertAction(title: "cancel".localized, style: .cancel))
        present(alert, animated: true, completion: nil)
    }

    private func composeNewMessage(at indexPath: IndexPath, quoteType: MessageQuoteType) {
        guard let email = DataService.shared.email,
              let input = input[safe: indexPath.section-1],
              let processedMessage = input.processedMessage
        else { return }

        let recipients = quoteType == .reply
            ? [input.rawMessage.sender].compactMap({ $0 })
            : []

        let attachments = quoteType == .forward
            ? input.processedMessage?.attachments ?? []
            : []

        let subject = input.rawMessage.subject ?? "(no subject)"
        let threadId = quoteType == .reply ? input.rawMessage.threadId : nil

        let replyInfo = ComposeMessageInput.MessageQuoteInfo(
            recipients: recipients,
            sender: input.rawMessage.sender,
            subject: "\(quoteType.subjectPrefix)\(subject)",
            mime: processedMessage.rawMimeData,
            sentDate: input.rawMessage.date,
            message: processedMessage.text,
            threadId: threadId,
            attachments: attachments
        )

        let composeInput = ComposeMessageInput(type: .quote(replyInfo))
        navigationController?.pushViewController(
            ComposeViewController(email: email, input: composeInput),
            animated: true
        )
    }

    private func markAsRead(at index: Int) {
        guard let message = input[safe: index]?.rawMessage else {
            return
        }

        Task {
            do {
                try await messageOperationsProvider.markAsRead(message: message, folder: currentFolderPath)
                let updatedMessage = input[index].rawMessage.markAsRead(true)
                input[index].rawMessage = updatedMessage
                node.reloadSections(IndexSet(integer: index), with: .fade)
            } catch {
                showToast("Could not mark message as read: \(error)")
            }
        }
    }
}

extension ThreadDetailsViewController {
    private func fetchDecryptAndRenderMsg(at indexPath: IndexPath) {
        let message = input[indexPath.section-1].rawMessage
        logger.logInfo("Start loading message")

        handleFetchProgress(state: .fetch)

        Task {
            do {
                var processedMessage = try await messageService.getAndProcessMessage(
                    with: message,
                    folder: thread.path,
                    onlyLocalKeys: true,
                    progressHandler: { [weak self] in self?.handleFetchProgress(state: $0) }
                )
                if case .missingPubkey = processedMessage.signature {
                    processedMessage.signature = .pending
                    retryVerifyingSignatureWithRemotelyFetchedKeys(message: message,
                                                                   folder: thread.path,
                                                                   indexPath: indexPath)
                }
                handleReceived(message: processedMessage, at: indexPath)
            } catch {
                handleError(error, at: indexPath)
            }
        }
    }

    private func handleReceived(message processedMessage: ProcessedMessage, at indexPath: IndexPath) {
        hideSpinner()

        let messageIndex = indexPath.section - 1
        let isAlreadyProcessed = input[messageIndex].processedMessage != nil

        if !isAlreadyProcessed {
            input[messageIndex].processedMessage = processedMessage
            input[messageIndex].isExpanded = true

            markAsRead(at: messageIndex)

            UIView.animate(
                withDuration: 0.2,
                animations: {
                    self.node.reloadSections(IndexSet(integer: indexPath.section), with: .fade)
                },
                completion: { [weak self] _ in
                    self?.node.scrollToRow(at: indexPath, at: .middle, animated: true)
                })
        } else {
            input[messageIndex].processedMessage?.signature = processedMessage.signature
            node.reloadSections(IndexSet(integer: indexPath.section), with: .fade)
        }
    }

    private func handleError(_ error: Error, at indexPath: IndexPath) {
        logger.logInfo("Error \(error)")
        hideSpinner()

        switch error as? MessageServiceError {
        case let .missingPassPhrase(rawMimeData):
            handleMissedPassPhrase(for: rawMimeData, at: indexPath)
        case let .wrongPassPhrase(rawMimeData, passPhrase):
            handleWrongPassPhrase(for: rawMimeData, with: passPhrase, at: indexPath)
        default:
            // TODO: - Ticket - Improve error handling for ThreadDetailsViewController
            if let someError = error as NSError?, someError.code == Imap.Err.fetch.rawValue {
                // todo - the missing msg should be removed from the list in inbox view
                // reproduce: 1) load inbox 2) move msg to trash on another email client 3) open trashed message in inbox
                showToast("Message not found in folder: \(thread.path)")
            } else {
                // todo - this should be a retry / cancel alert
                showAlert(error: error, message: "message_failed_open".localized + "\n\n\(error)")
            }
            navigationController?.popViewController(animated: true)
        }
    }

    private func handleMissedPassPhrase(for rawMimeData: Data, at indexPath: IndexPath) {
        let alert = AlertsFactory.makePassPhraseAlert(
            onCancel: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onCompletion: { [weak self] passPhrase in
                self?.handlePassPhraseEntry(rawMimeData: rawMimeData, with: passPhrase, at: indexPath)
            })

        present(alert, animated: true, completion: nil)
    }

    private func handleWrongPassPhrase(for rawMimeData: Data, with phrase: String, at indexPath: IndexPath) {
        let alert = AlertsFactory.makePassPhraseAlert(
            onCancel: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onCompletion: { [weak self] passPhrase in
                self?.handlePassPhraseEntry(rawMimeData: rawMimeData, with: passPhrase, at: indexPath)
            },
            title: "setup_wrong_pass_phrase_retry".localized
        )
        present(alert, animated: true, completion: nil)
    }

    private func handlePassPhraseEntry(rawMimeData: Data, with passPhrase: String, at indexPath: IndexPath) {
        handleFetchProgress(state: .decrypt)

        Task {
            do {
                let matched = try await messageService.checkAndPotentiallySaveEnteredPassPhrase(passPhrase)
                if matched {
                    let sender = input[indexPath.section-1].rawMessage.sender
                    let processedMessage = try await messageService.decryptAndProcessMessage(
                        mime: rawMimeData,
                        sender: sender,
                        onlyLocalKeys: false)
                    handleReceived(message: processedMessage, at: indexPath)
                } else {
                    handleWrongPassPhrase(for: rawMimeData, with: passPhrase, at: indexPath)
                }
            } catch {
                handleError(error, at: indexPath)
            }
        }
    }

    private func retryVerifyingSignatureWithRemotelyFetchedKeys(message: Message,
                                                                folder: String,
                                                                indexPath: IndexPath) {
        Task {
            do {
                let processedMessage = try await messageService.getAndProcessMessage(
                    with: message,
                    folder: thread.path,
                    onlyLocalKeys: false,
                    progressHandler: { _ in }
                )
                handleReceived(message: processedMessage, at: indexPath)
            } catch {
                let message = "message_signature_fail_reason".localizeWithArguments(error.errorMessage)
                input[indexPath.section-1].processedMessage?.signature = .error(message)
            }
        }
    }

    private func handleFetchProgress(state: MessageFetchState) {
        switch state {
        case .fetch:
            showSpinner("loading_title".localized, isUserInteractionEnabled: true)
        case .download(let progress):
            updateSpinner(label: "downloading_title".localized, progress: progress)
        case .decrypt:
            updateSpinner(label: "decrypting_title".localized)
        }
    }
}

extension ThreadDetailsViewController: MessageActionsHandler {
    private func handleSuccessfulMessage(action: MessageAction) {
        hideSpinner()
        onComplete(action, .init(thread: thread, folderPath: currentFolderPath))
        navigationController?.popViewController(animated: true)
    }

    private func handleMessageAction(error: Error) {
        logger.logError("Error mark as read \(error)")
        hideSpinner()
    }

    func permanentlyDelete() {
        logger.logInfo("permanently delete")
        handle(action: .permanentlyDelete)
    }

    func moveToTrash(with trashPath: String) {
        logger.logInfo("move to trash \(trashPath)")
        handle(action: .moveToTrash)
    }

    func handleArchiveTap() {
        handle(action: .archive)
    }

    func handleMarkUnreadTap() {
        let messages = input.filter { $0.isExpanded }.map(\.rawMessage)

        guard messages.isNotEmpty else { return }

        handle(action: .markAsRead(false))
    }

    func handle(action: MessageAction) {
        Task {
            do {
                showSpinner()

                switch action {
                case .archive:
                    try await threadOperationsProvider.archive(thread: thread, in: currentFolderPath)
                case .markAsRead(let isRead):
                    guard !isRead else { return }
                    try await threadOperationsProvider.mark(thread: thread, asRead: false, in: currentFolderPath)
                case .moveToTrash:
                    try await threadOperationsProvider.moveThreadToTrash(thread: thread)
                case .permanentlyDelete:
                    try await threadOperationsProvider.delete(thread: thread)
                }

                handleSuccessfulMessage(action: action)
            } catch {
                handleMessageAction(error: error)
            }
        }
    }
}

extension ThreadDetailsViewController: ASTableDelegate, ASTableDataSource {
    func numberOfSections(in tableNode: ASTableNode) -> Int {
        input.count + 1
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        guard section > 0, input[section-1].isExpanded else { return 1 }

        let attachmentsCount = input[section-1].processedMessage?.attachments.count ?? 0
        return Parts.allCases.count + attachmentsCount
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        return { [weak self] in
            guard let self = self else { return ASCellNode() }

            guard indexPath.section > 0 else {
                let subject = self.thread.subject ?? "no subject"
                return MessageSubjectNode(subject.attributed(.medium(18)))
            }

            let section = self.input[indexPath.section-1]

            if indexPath.row == 0 {
                return ThreadMessageSenderCellNode(
                    input: .init(threadMessage: section),
                    onReplyTap: { [weak self] _ in self?.handleReplyTap(at: indexPath) },
                    onMenuTap: { [weak self] _ in self?.handleMenuTap(at: indexPath) }
                )
            }

            if indexPath.row == 1, let message = section.processedMessage {
                return MessageTextSubjectNode(message.attributedMessage)
            }

            if indexPath.row > 1, let message = section.processedMessage {
                let attachment = message.attachments[indexPath.row - 2]
                return AttachmentNode(
                    input: .init(
                        msgAttachment: attachment,
                        index: indexPath.row - 2
                    ),
                    onDownloadTap: { [weak self] in self?.attachmentManager.open(attachment) }
                )
            }

            return ASCellNode()
        }
    }

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        guard tableNode.nodeForRow(at: indexPath) is ThreadMessageSenderCellNode else {
            return
        }
        handleExpandTap(at: indexPath)
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        dividerView()
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        section > 0 && section < input.count ? 1 / UIScreen.main.nativeScale : 0
    }

    private func dividerView() -> UIView {
        UIView().then {
            let frame = CGRect(x: 8, y: 0, width: view.frame.width - 16, height: 1 / UIScreen.main.nativeScale)
            let divider = UIView(frame: frame)
            $0.addSubview(divider)
            $0.backgroundColor = .clear
            divider.backgroundColor = .borderColor
        }
    }
}

extension ThreadDetailsViewController: NavigationChildController {
    func handleBackButtonTap() {
        let isRead = input.contains(where: { $0.rawMessage.isMessageRead })
        logger.logInfo("Back button. Are all messages read \(isRead) ")
        onComplete(MessageAction.markAsRead(isRead), .init(thread: thread, folderPath: currentFolderPath))
        navigationController?.popViewController(animated: true)
    }
}
