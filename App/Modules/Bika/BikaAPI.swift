import CryptoKit
import Foundation

/// 哔咔接口的固定参数和请求签名。
///
/// 全部照搬上游客户端（upstream/Pica 的 `PCRequest.m`），它用的是官方安卓客户端的那一套参数。
/// 调试构建里有一项自检，拿上游的实现和这里的实现对同一组输入算签名，确认结果一字不差（见 `BikaProbe`）。
nonisolated enum BikaAPI {
    static let baseURL = "https://picaapi.picacomic.com/"
    static let apiKey = "C69BAF41DA5ABD1FFEDC6D2FEA56B"
    /// 签名用的密钥。里面有一个反斜杠，所以用不转义的写法。
    static let secret = #"~d}$Q7$eIni=V)9\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn"#
    static let appVersion = "2.2.1.3.3.4"
    static let buildVersion = "45"
    static let platform = "android"
    static let userAgent = "okhttp/3.8.1"
    static let accept = "application/vnd.picacomic.com.v1+json"

    /// 设备标识。和上游一样：每次启动重新生成，不保存。
    static let appUUID = UUID().uuidString.lowercased()

    /// 分流：只是请求头里的一个数字，不换服务器地址。
    static let channels = ["1", "2", "3"]
    /// 图片质量：请求头里的一个词，决定接口给出哪一档的图片地址。上游固定用原图。
    static let imageQualities = ["original", "high", "medium", "low"]

    /// 请求头里的时间：秒，四舍五入成整数。
    static func timestamp(_ date: Date) -> String {
        String(format: "%.0f", date.timeIntervalSince1970)
    }

    /// 每个请求一个的随机串：去掉横线的小写 UUID。
    static func makeNonce() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// 请求签名：路径（带查询串，不带开头的斜杠）、时间、随机串、方法名、api-key 依次拼起来，整体转成小写，
    /// 用密钥做 HMAC-SHA256，结果写成小写的十六进制。
    static func signature(path: String, time: String, nonce: String, method: String) -> String {
        let raw = (path + time + nonce + method + apiKey).lowercased()
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(raw.utf8), using: key)
        return code.map { String(format: "%02x", $0) }.joined()
    }

    /// 一个请求要带的全部请求头。名字的大小写和上游保持一样。
    static func headers(
        path: String, method: String, time: Date, nonce: String,
        channel: String, imageQuality: String, token: String?
    ) -> [String: String] {
        let timeText = timestamp(time)
        var headers = [
            "api-key": apiKey,
            "accept": accept,
            "app-channel": channel,
            "time": timeText,
            "nonce": nonce,
            "signature": signature(path: path, time: timeText, nonce: nonce, method: method),
            "app-version": appVersion,
            "app-uuid": appUUID,
            "app-platform": platform,
            "app-build-version": buildVersion,
            "Content-Type": "application/json; charset=UTF-8",
            "User-Agent": userAgent,
            "image-quality": imageQuality,
            "accept-encoding": "gzip",
        ]
        // 登录令牌原样放进去，前面不加别的词。
        if let token, !token.isEmpty {
            headers["authorization"] = token
        }
        return headers
    }

    /// 把一段文字编码成能放进路径或查询串里的样子（分类名、标签、搜索词里什么字符都可能有）。
    /// 只留下字母、数字和 `-._~`，其余都写成 %XX。签名用的就是编码之后的路径，两边必须是同一个串。
    static func encode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // CharacterSet.alphanumerics 里还有各国文字，这里只认 ASCII。
        let encoded = text.unicodeScalars.map { scalar -> String in
            if scalar.isASCII, allowed.contains(scalar) {
                return String(scalar)
            }
            return String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
        }
        return encoded.joined()
    }
}

/// 请求没成功时给出的原因。
nonisolated enum BikaError: LocalizedError {
    /// 请求本身拼不出来（不该发生）。
    case invalidRequest
    /// 没连上：断网、超时、被拦。
    case network(String)
    /// 登录令牌失效，要重新登录。
    case unauthorized
    /// 服务器明确拒绝了。`code` 是它自己的错误编号。
    case server(status: Int, code: String?, message: String?, detail: String?)
    /// 服务器回了东西，但不是预期的样子。
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "请求的地址拼不出来"
        case .network(let reason):
            return "没有连上哔咔的服务器：\(reason)"
        case .unauthorized:
            return "登录已经失效，请重新登录"
        case .server(let status, let code, let message, let detail):
            if code == "1004" {
                return "账号或密码不对"
            }
            let parts = [message, detail].compactMap { $0 }.filter { !$0.isEmpty }
            let reason = parts.isEmpty ? "没有给出原因" : parts.joined(separator: "，")
            var label = "\(status)"
            if let code, !code.isEmpty {
                label += "，编号 \(code)"
            }
            return "服务器拒绝了这次请求（\(label)）：\(reason)"
        case .decoding(let reason):
            return "服务器返回的内容不是预期的样子：\(reason)"
        }
    }
}

/// 发请求的地方。只管把请求发出去、把结果解出来，各个接口的写法在 `BikaLiveService` 里。
final class BikaClient {
    static let shared = BikaClient()

    private let session: URLSession

    private init() {
        // 用一个独立的、不留痕迹的会话：不和另外两个应用共用缓存和 Cookie。
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    /// 发一个请求，把响应里 `data` 那一段解成 `Response`。
    ///
    /// - Parameters:
    ///   - method: `GET`、`POST`、`PUT`，大写。
    ///   - path: 相对路径，带查询串，不带开头的斜杠。里面的文字要先用 `BikaAPI.encode` 编码。
    ///   - body: 请求体，会写成 JSON。没有请求体的传 nil。
    func send<Response: Decodable>(
        _ method: String, _ path: String, body: [String: String]? = nil, as type: Response.Type
    ) async throws -> Response {
        guard let url = URL(string: BikaAPI.baseURL + path) else {
            throw BikaError.invalidRequest
        }
        let state = BikaSession.shared
        var request = URLRequest(url: url)
        request.httpMethod = method
        let headers = BikaAPI.headers(
            path: path, method: method, time: Date(), nonce: BikaAPI.makeNonce(),
            channel: state.channel, imageQuality: state.imageQuality, token: state.token
        )
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // 页面离开时请求被取消：按取消处理，不当成出错。
            throw CancellationError()
        } catch {
            throw BikaError.network(error.localizedDescription)
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else {
            throw BikaError.network("收到的不是 HTTP 响应")
        }

        guard (200...299).contains(http.statusCode) else {
            let failure = try? JSONDecoder().decode(BikaFailure.self, from: data)
            // 上游认的是「编号 1005、原因 unauthorized、状态 401」三样齐全；这里只要状态是 401 或编号是 1005 就算。
            if http.statusCode == 401 || failure?.error == "1005" {
                state.sessionExpired()
                throw BikaError.unauthorized
            }
            throw BikaError.server(
                status: http.statusCode, code: failure?.error, message: failure?.message, detail: failure?.detail
            )
        }

        do {
            let envelope = try JSONDecoder().decode(BikaEnvelope<Response>.self, from: data)
            guard let value = envelope.data else {
                throw BikaError.decoding("没有 data 这一段")
            }
            return value
        } catch let error as DecodingError {
            throw BikaError.decoding(Self.describe(error))
        }
    }

    /// 把解码出错的位置说清楚：接口没法在云端实测，出了问题要靠这句话定位。
    private static func describe(_ error: DecodingError) -> String {
        func location(_ context: DecodingError.Context) -> String {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? "最外层" : path
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "\(location(context)) 里缺少 \(key.stringValue)"
        case .valueNotFound(_, let context):
            return "\(location(context)) 是空的"
        case .typeMismatch(_, let context):
            return "\(location(context)) 的类型不对"
        case .dataCorrupted(let context):
            return "\(location(context)) 读不出来"
        @unknown default:
            return "读不出来"
        }
    }
}

/// 成功的响应：`{"code": 200, "message": "success", "data": {…}}`。
nonisolated struct BikaEnvelope<Payload: Decodable>: Decodable {
    let data: Payload?
}

/// 失败的响应：`{"code": 400, "error": "1004", "message": "…", "detail": "…"}`。
nonisolated struct BikaFailure: Decodable {
    let error: String?
    let message: String?
    let detail: String?
}
