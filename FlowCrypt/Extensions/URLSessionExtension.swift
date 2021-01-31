//
// © 2017-2019 FlowCrypt Limited. All rights reserved.
//

import FlowCryptCommon
import Foundation
import Promises

struct HttpRes {
    let status: Int
    let data: Data
}

struct HttpErr: Error {
    let status: Int
    let data: Data?
    let error: Error?
}

extension URLSession {
    func call(_ urlRequest: URLRequest, tolerateStatus: [Int]? = nil) -> Promise<HttpRes> {
        return Promise { resolve, reject in
            let start = DispatchTime.now()
            self.dataTask(with: urlRequest) { data, response, error in
                let res = response as? HTTPURLResponse
                let status = res?.statusCode ?? GeneralConstants.Global.generalError
                let urlMethod = urlRequest.httpMethod ?? "GET"
                let urlString = urlRequest.url?.absoluteString ?? "??"
                let message = "URLSession.call status:\(status) ms:\(start.millisecondsSince) \(urlMethod) \(urlString)"
                debugPrint(message)
                let validStatusCode = 200 ... 299
                let isInToleranceStatusCodes = (tolerateStatus?.contains(status) ?? false)
                let isCodeValid = validStatusCode ~= status || isInToleranceStatusCodes
                let isValidResponse = error == nil && isCodeValid
                if let data = data, isValidResponse {
                    resolve(HttpRes(status: status, data: data))
                } else {
                    reject(HttpErr(status: status, data: data, error: error))
                }
            }.resume()
        }
    }

    func call(_ urlStr: String, tolerateStatus: [Int]? = nil) -> Promise<HttpRes> {
        return Promise { () -> HttpRes in
            let url = URL(string: urlStr)
            guard url != nil else {
                throw HttpErr(status: -2, data: Data(), error: AppErr.unexpected("Invalid url: \(urlStr)"))
            }
            return try await(self.call(URLRequest(url: url!), tolerateStatus: tolerateStatus))
        }
    }
}

enum HTTPMetod: String {
    case put = "PUT"
    case get = "GET"
    case post = "POST"
}

struct URLHeader {
    let value: String
    let httpHeaderField: String
}

extension URLRequest {
    static func urlRequest(
        with urlString: String,
        method: HTTPMetod,
        body: Data?,
        headers: [URLHeader] = []
    ) -> URLRequest {
        guard let url = URL(string: urlString) else {
            fatalError("can't create URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        headers.forEach {
            request.addValue($0.value, forHTTPHeaderField: $0.httpHeaderField)
        }
        return request
    }
}
