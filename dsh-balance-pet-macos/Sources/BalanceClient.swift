import Foundation
import CoreFoundation

/// Balances retain their decimal representation until the final fen rounding.
/// Double values are exposed only for labels and diagnostic formatting.
struct BalanceReading {
    private let normal: Decimal?
    private let bonus: Decimal?
    private let spent: Decimal?
    let raw: String

    init(normalCny: Double, bonusCny: Double, spentCny: Double?, raw: String) {
        normal = Self.decimal(normalCny)
        bonus = Self.decimal(bonusCny)
        spent = spentCny.flatMap(Self.decimal)
        self.raw = raw
    }

    init(normal: Decimal, bonus: Decimal, spent: Decimal?, raw: String) {
        self.normal = normal
        self.bonus = bonus
        self.spent = spent
        self.raw = raw
    }

    var normalCny: Double { normal.map { NSDecimalNumber(decimal: $0).doubleValue } ?? .nan }
    var bonusCny: Double { bonus.map { NSDecimalNumber(decimal: $0).doubleValue } ?? .nan }
    var spentCny: Double? { spent.map { NSDecimalNumber(decimal: $0).doubleValue } }
    var totalCny: Double { total.map { NSDecimalNumber(decimal: $0).doubleValue } ?? .nan }

    private var total: Decimal? {
        guard var a = normal, var b = bonus else { return nil }
        var sum = Decimal()
        guard NSDecimalAdd(&sum, &a, &b, .plain) == .noError else { return nil }
        return sum
    }

    /// Invalid/overflowing synthetic readings are rejected by the model too.
    var totalCents: Int? {
        guard var amount = total else { return nil }
        var scale = Decimal(100), scaled = Decimal(), rounded = Decimal()
        guard NSDecimalMultiply(&scaled, &amount, &scale, .plain) == .noError else { return nil }
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard !rounded.isNaN, rounded >= Decimal(Int.min), rounded <= Decimal(Int.max) else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }

    private static func decimal(_ value: Double) -> Decimal? {
        value.isFinite ? Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) : nil
    }
}

enum FetchError: Error {
    case auth(String)
    case rateLimited(Double?)
    case http(Int, String)
    case transport(String)
    case parse(String)

    var describe: String {
        switch self {
        case .auth(let s): return "认证失败（\(s)）——请检查 API Key / 账号是否过期"
        case .rateLimited(let ra):
            let suffix = ra.flatMap { $0.isFinite && $0 >= 0 ? String(format: "，%.0fs 后重试", $0) : nil } ?? ""
            return "请求过于频繁（429）" + suffix
        case .http(let code, let message): return "HTTP \(code)\(message.isEmpty ? "" : " · " + message)"
        case .transport(let s): return "网络错误：\(s)"
        case .parse(let s): return "响应无法解析：\(s)"
        }
    }

    var retryAfter: Double? {
        if case .rateLimited(let ra) = self { return ra }
        return nil
    }
}

/// Refuse all redirects. In particular, URLSession must never forward the
/// platform's custom authentication header to another host or an HTTP URL.
final class BalanceSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class BalanceResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<(Int, Data, [String: String]), Error> = .failure(FetchError.transport("没有响应"))
    func set(_ value: Result<(Int, Data, [String: String]), Error>) {
        lock.lock()
        defer { lock.unlock() }
        result = value
    }
    func get() throws -> (Int, Data, [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        return try result.get()
    }
}

enum BalanceClient {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.timeoutIntervalForRequest = 20
        return URLSession(configuration: cfg, delegate: BalanceSessionDelegate(), delegateQueue: nil)
    }()

    static func fetch(_ cred: Credential, timeout: TimeInterval = 20) throws -> BalanceReading {
        guard CredentialStore.isSafeEndpoint(cred.endpoint), CredentialStore.isValidToken(cred.token) else {
            throw FetchError.auth("凭证或 HTTPS 地址无效")
        }
        let timeout = timeout.isFinite ? min(120, max(1, timeout)) : 20
        var req = URLRequest(url: cred.endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("DSHBalancePet/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        switch cred.mode {
        case .apiKey: req.setValue("Bearer \(cred.token)", forHTTPHeaderField: "Authorization")
        case .account: req.setValue(cred.token, forHTTPHeaderField: "x-dsh-auth-token")
        }
        let sem = DispatchSemaphore(value: 0)
        let box = BalanceResponseBox()
        let task = session.dataTask(with: req) { data, response, error in
            defer { sem.signal() }
            if error != nil {
                // URLSession errors can contain request URLs; keep the status file
                // and log free of arbitrary server content or credential material.
                box.set(.failure(FetchError.transport("请求未完成，请检查网络连接")))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                box.set(.failure(FetchError.transport("没有 HTTP 响应")))
                return
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key).lowercased()] = String(describing: value)
            }
            box.set(.success((http.statusCode, data ?? Data(), headers)))
        }
        task.resume()
        if sem.wait(timeout: .now() + timeout + 5) == .timedOut {
            task.cancel()
            throw FetchError.transport("超时")
        }
        let (status, data, headers) = try box.get()
        return try parseResponse(status: status, data: data, headers: headers, mode: cred.mode)
    }

    /// Shared by the live request and the offline fixture tests.
    static func parseResponse(status: Int, data: Data, headers: [String: String] = [:],
                              mode: AuthMode, now: Date = Date()) throws -> BalanceReading {
        if status == 401 || status == 403 { throw FetchError.auth("HTTP \(status)") }
        if status == 429 {
            let value = headers.first { $0.key.lowercased() == "retry-after" }?.value
            throw FetchError.rateLimited(retryDelay(value, now: now))
        }
        guard status == 200 else { throw FetchError.http(status, "") }
        guard data.count <= 1_048_576,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw FetchError.parse("需要有效的 JSON 对象")
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        switch mode {
        case .account: return try parseAccount(root, raw: body)
        case .apiKey: return try parseApiKey(root, raw: body)
        }
    }

    static func retryDelay(_ header: String?, now: Date = Date()) -> Double? {
        guard let raw = header?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.allSatisfy({ $0.isASCII && $0.isNumber }), let seconds = Double(raw), seconds.isFinite {
            return min(86_400, seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return min(86_400, max(0, date.timeIntervalSince(now))) }
        }
        return nil
    }

    private static func parseAccount(_ root: [String: Any], raw: String) throws -> BalanceReading {
        // Accept the documented platform envelope or an unwrapped wallet object.
        // Never search recursively: error/debug objects can carry stale balances.
        var payload = root
        if root["code"] != nil || root["data"] != nil {
            try checkCode(root["code"], label: "code")
            guard let data = root["data"] as? [String: Any] else { throw FetchError.parse("缺少 data 对象") }
            payload = data
        }
        if payload["biz_code"] != nil || payload["biz_data"] != nil {
            try checkCode(payload["biz_code"], label: "biz_code")
            guard let biz = payload["biz_data"] as? [String: Any] else { throw FetchError.parse("缺少 biz_data 对象") }
            payload = biz
        }
        let normal = try walletTotal(payload["normal_wallets"], required: true, label: "normal_wallets")
        let bonus = try walletTotal(payload["bonus_wallets"], required: false, label: "bonus_wallets")
        let spent = try payload["total_costs"].map {
            try walletTotal($0, required: false, label: "total_costs", amountKey: "amount")
        }
        return try checkedReading(normal: normal, bonus: bonus, spent: spent, raw: raw)
    }

    private static func checkCode(_ value: Any?, label: String) throws {
        guard let value = value, let decimal = decimalValue(value), decimal == decimal.roundedInteger else {
            throw FetchError.parse("\(label) 无效")
        }
        if decimal == 40003 { throw FetchError.auth("平台返回 code 40003") }
        guard decimal == 0 else { throw FetchError.parse("平台返回非成功 \(label)") }
    }

    private static func parseApiKey(_ root: [String: Any], raw: String) throws -> BalanceReading {
        let normal = try walletTotal(root["balance_infos"], required: true,
                                     label: "balance_infos", amountKey: "total_balance")
        return try checkedReading(normal: normal, bonus: 0, spent: nil, raw: raw)
    }

    private static func walletTotal(_ value: Any?, required: Bool, label: String,
                                    amountKey: String = "balance") throws -> Decimal {
        guard let value = value else {
            if !required { return 0 }
            throw FetchError.parse("找不到 \(label)")
        }
        guard let wallets = value as? [[String: Any]] else { throw FetchError.parse("\(label) 必须是钱包数组") }
        var total = Decimal(), cnyCount = 0
        for wallet in wallets {
            guard let currency = wallet["currency"] as? String, !currency.isEmpty else {
                throw FetchError.parse("\(label) 缺少货币类型")
            }
            // This UI is denominated in CNY. A USD amount must never be labelled ¥.
            guard currency == "CNY" else { continue }
            guard var amount = decimalValue(wallet[amountKey]) else {
                throw FetchError.parse("\(label) 的 CNY 金额无效")
            }
            var previous = total
            guard NSDecimalAdd(&total, &previous, &amount, .plain) == .noError else {
                throw FetchError.parse("\(label) 金额超出范围")
            }
            cnyCount += 1
        }
        if cnyCount == 0 && (required || !wallets.isEmpty) {
            throw FetchError.parse("\(label) 没有 CNY 钱包，暂不支持其他货币")
        }
        return total
    }

    private static func checkedReading(normal: Decimal, bonus: Decimal, spent: Decimal?, raw: String) throws -> BalanceReading {
        let reading = BalanceReading(normal: normal, bonus: bonus, spent: spent, raw: raw)
        guard reading.totalCents != nil else { throw FetchError.parse("余额超出可显示范围") }
        return reading
    }

    private static func decimalValue(_ value: Any?) -> Decimal? {
        let string: String
        if let s = value as? String { string = s.trimmingCharacters(in: .whitespacesAndNewlines) }
        else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { string = number.stringValue }
        else { return nil }
        // Decimal(string:) accepts partial strings; require the entire numeric scalar.
        guard string.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#,
                           options: .regularExpression) != nil,
              let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else { return nil }
        return value
    }
}

private extension Decimal {
    var roundedInteger: Decimal {
        var source = self, result = Decimal()
        NSDecimalRound(&result, &source, 0, .plain)
        return result
    }
}
