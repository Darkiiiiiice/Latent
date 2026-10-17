import Foundation

/// 网络层错误分类（设计文档第 4 节「节流、重试与错误」）。
///
/// UI 侧对每个 case 有明确动作；`errorDescription` 只写面向用户的中文文案。
enum APIError: Error, Equatable, Sendable {
    /// 未配置 Token（引导页）。
    case missingToken
    /// 401：Token 无效或已失效（引导页 + 提示）。
    case unauthorized
    /// 404：资源不存在（详情页内联提示）。
    case notFound
    /// 429：被限流；`retryAfter` 来自 Retry-After 头（秒）。
    case rateLimited(retryAfter: Int?)
    /// 5xx 或不可预期的状态码。
    case serverError(status: Int)
    /// 断网 / 超时等传输失败。
    case offline
    /// 请求超时。
    case timedOut
    /// JSON 解码失败。
    case decodingFailed(String)

    var errorDescription: String {
        switch self {
        case .missingToken:
            return "尚未配置 TMDB Token"
        case .unauthorized:
            return "Token 无效或已失效，请在设置中重新填写"
        case .notFound:
            return "资源不存在或已下架"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "请求太频繁，请约 \(retryAfter) 秒后重试"
            }
            return "请求太频繁，请稍后重试"
        case .serverError(let status):
            return "TMDB 服务异常（\(status)），请稍后重试"
        case .offline:
            return "网络不可用，请检查连接"
        case .timedOut:
            return "请求超时，请重试"
        case .decodingFailed:
            return "数据格式异常"
        }
    }

    /// 是否值得重试（超时 / 断网 / 5xx；429 由 Retry-After 单独处理）。
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut:
            return true
        case .serverError(let status):
            return status >= 500
        case .rateLimited:
            return true
        default:
            return false
        }
    }
}

/// 把 URLSession 的失败映射为 APIError。
extension APIError {
    init(transportError error: any Error) {
        let urlError = error as? URLError
        switch urlError?.code {
        case .some(.timedOut):
            self = .timedOut
        case .some(.notConnectedToInternet), .some(.networkConnectionLost), .some(.cannotConnectToHost),
             .some(.cannotFindHost), .some(.dnsLookupFailed), .some(.secureConnectionFailed),
             .some(.dataNotAllowed), .some(.internationalRoamingOff):
            self = .offline
        default:
            self = .offline
        }
    }
}
