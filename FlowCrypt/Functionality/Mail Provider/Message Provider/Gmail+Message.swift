//
//  Gmail+Message.swift
//  FlowCrypt
//
//  Created by Anton Kharchevskyi on 29.11.2020.
//  Copyright © 2017-present FlowCrypt a. s. All rights reserved.
//

import GoogleAPIClientForREST_Gmail
import GTMSessionFetcherCore

extension GmailService: MessageProvider {
    func fetchMsg(message: Message,
                  folder: String,
                  progressHandler: ((MessageFetchState) -> Void)?) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            guard let identifier = message.identifier.stringId else {
                continuation.resume(throwing: GmailServiceError.missedMessageInfo("id"))
                return
            }

            Task {
                let messageSize = try await self.fetchMessageSize(identifier: identifier)

                let fetcher = self.createMessageFetcher(identifier: identifier)
                fetcher.receivedProgressBlock = { _, received in
                    let progress = min(Float(received)/messageSize, 1)
                    progressHandler?(.download(progress))
                }
                fetcher.beginFetch { data, error in
                    if let error = error {
                        continuation.resume(throwing: GmailServiceError.providerError(error))
                        return
                    }

                    guard let data = data,
                          let dictionary = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                          let raw = dictionary["raw"] as? String
                    else {
                        continuation.resume(throwing: GmailServiceError.missedMessageInfo("raw"))
                        return
                    }

                    progressHandler?(.decrypt)

                    guard let data = GTLRDecodeWebSafeBase64(raw) else {
                        continuation.resume(throwing: GmailServiceError.missedMessageInfo("data"))
                        return
                    }

                    continuation.resume(returning: data)
                }
            }
        }
    }

    private func fetchMessageSize(identifier: String) async throws -> Float {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Float, Error>) in
            let query = createMessageQuery(identifier: identifier, format: kGTLRGmailFormatMetadata)
            self.gmailService.executeQuery(query) { _, data, error in
                if let error = error {
                    continuation.resume(throwing: GmailServiceError.providerError(error))
                    return
                }

                guard let gmailMessage = data as? GTLRGmail_Message else {
                    continuation.resume(throwing: AppErr.cast("GTLRGmail_Message"))
                    return
                }

                guard let sizeEstimate = gmailMessage.sizeEstimate?.floatValue else {
                    continuation.resume(throwing: GmailServiceError.missedMessageInfo("sizeEstimate"))
                    return
                }

                // google returns smaller estimated size
                let totalSize = sizeEstimate * Float(1.3)
                continuation.resume(with: .success(totalSize))
            }
        }
    }

    private func createMessageFetcher(identifier: String) -> GTMSessionFetcher {
        let query = createMessageQuery(identifier: identifier, format: kGTLRGmailFormatRaw)
        let request = gmailService.request(for: query) as URLRequest
        return gmailService.fetcherService.fetcher(with: request)
    }

    private func createMessageQuery(identifier: String, format: String) -> GTLRGmailQuery_UsersMessagesGet {
        let query = GTLRGmailQuery_UsersMessagesGet.query(withUserId: .me, identifier: identifier)
        query.format = format
        return query
    }
}
