//
//  IKuaiService.swift
//  爱快路由接口客户端，兼容两套协议：
//
//  A. 旧固件（3.x）本地 Web 接口
//     POST {base}/Action/login   {"username","passwd":<md5>,"pass":<md5>,"remember_password":""}
//     POST {base}/Action/call    {"func_name":"monitor_lanip","action":"show","param":{...}}
//     成功看 Result == 10000 / 30000，靠 cookie 维持会话。
//
//  B. 新固件（4.x）REST API
//     GET  {base}/api/v4.0/monitoring/clients?page=1&limit=100
//     Header: Authorization: Bearer <API Token>
//     Token 在 系统设置 → 安全设置 → API Token 里生成。
//

import Foundation
import CryptoKit
import Observation

// MARK: - 终端条目

struct IKuaiTerminal: Identifiable, Hashable {
    var id: String
    var ip: String
    var mac: String
    var host: String
    var up: String
    var down: String
    var connections: String
    var online: String
    var raw: [String: String] = [:]
}

// MARK: - 自签证书放行（爱快 web 用自签证书）

final class InsecureSession: NSObject, URLSessionDelegate {
    static let shared = InsecureSession()
    lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition,
                                                  URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

// MARK: - 服务

@MainActor
@Observable
final class IKuaiService {

    enum Status: Equatable {
        case idle, loading, ok, failed
    }

    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "ikuai.base") ?? "https://192.168.10.250:8443" }
        set { UserDefaults.standard.set(newValue, forKey: "ikuai.base") }
    }
    var username: String {
        get { UserDefaults.standard.string(forKey: "ikuai.user") ?? "admin" }
        set { UserDefaults.standard.set(newValue, forKey: "ikuai.user") }
    }
    var password: String {
        get { UserDefaults.standard.string(forKey: "ikuai.pass") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ikuai.pass") }
    }
    var token: String {
        get { UserDefaults.standard.string(forKey: "ikuai.token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ikuai.token") }
    }

    var terminals: [IKuaiTerminal] = []
    var status: Status = .idle
    var message: String = ""
    var lastUpdate: Date?
    var log: [String] = []
    var usedMode: String = ""

    var isConfigured: Bool {
        (!password.isEmpty || !token.isEmpty) && !baseURL.isEmpty
    }

    private var loggedInAt: Date?

    // MARK: 刷新（自动选协议）

    func refresh() async {
        guard isConfigured else {
            status = .failed
            message = "还没填账号密码或 API Token，点右上角齿轮设置"
            return
        }
        status = .loading
        message = ""
        log.removeAll()

        if !token.isEmpty {
            do {
                try await fetchV4()
                status = .ok
                return
            } catch {
                log.append("4.x 接口失败：\(describe(error))")
                if password.isEmpty {
                    status = .failed
                    message = describe(error)
                    return
                }
            }
        }

        do {
            try await fetchLegacy()
            status = .ok
        } catch {
            status = .failed
            message = describe(error)
        }
    }

    /// 诊断：两套协议都试一遍，把原始返回记到 log 里
    func diagnose() async {
        status = .loading
        log.removeAll()
        message = ""
        log.append("地址：\(baseURL)")

        if let url = URL(string: baseURL) {
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 10
                let (data, resp) = try await InsecureSession.shared.session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let server = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Server") ?? "-"
                log.append("\n[1] GET \(baseURL)\nHTTP \(code)  Server: \(server)")
                log.append("正文：\(preview(data))")
            } catch {
                log.append("\n[1] GET \(baseURL) 失败：\(error.localizedDescription)")
            }
        }

        do {
            let payload: [String: Any] = [
                "username": username,
                "passwd": Self.md5(password),
                "pass": Self.md5(password),
                "remember_password": ""
            ]
            let (code, data) = try await request("/Action/login", body: payload, bearer: nil,
                                                 label: "[2] POST /Action/login (pass=md5)")
            log.append("HTTP \(code)\n正文：\(preview(data))")
            log.append("Cookie：\(Self.cookieSummary())")
        } catch {
            log.append("\n[2] 登录失败：\(error.localizedDescription)")
        }

        do {
            let payload: [String: Any] = [
                "func_name": "monitor_lanip",
                "action": "show",
                "param": [
                    "ORDER": "",
                    "ORDER_BY": "ip_addr_int",
                    "TYPE": "data,total",
                    "limit": "0,300",
                    "orderType": "IP"
                ]
            ]
            let (code, data) = try await request("/Action/call", body: payload, bearer: nil,
                                                 label: "[3] POST /Action/call monitor_lanip")
            log.append("HTTP \(code)\n正文：\(preview(data))")
        } catch {
            log.append("\n[3] 取列表失败：\(error.localizedDescription)")
        }

        if token.isEmpty {
            log.append("\n[4] 未填 API Token，跳过 /api/v4.0")
            log.append("\n提示：若 [2]/[3] 都返回 Result=-1，多半是 4.x 固件，去 系统设置 → 安全设置 → API Token 生成一个填进来。")
        } else {
            do {
                let (code, data) = try await request("/api/v4.0/monitoring/clients?page=1&limit=100",
                                                     body: nil, bearer: token,
                                                     label: "[4] GET /api/v4.0/monitoring/clients")
                log.append("HTTP \(code)\n正文：\(preview(data))")
            } catch {
                log.append("\n[4] 新接口失败：\(error.localizedDescription)")
            }
        }

        status = .failed
        message = "诊断完成，把日志发我"
    }

    // MARK: 旧固件（3.x）

    private func fetchLegacy() async throws {
        if loggedInAt == nil || Date().timeIntervalSince(loggedInAt!) > 600 {
            try await loginLegacy()
        }
        do {
            terminals = try await callLegacy()
        } catch {
            if case IKuaiError.notLoggedIn = error {
                loggedInAt = nil
                try await loginLegacy()
                terminals = try await callLegacy()
            } else {
                throw error
            }
        }
        usedMode = "3.x 本地接口"
        lastUpdate = .now
    }

    private func loginLegacy() async throws {
        let md5 = Self.md5(password)
        let b64 = Data(password.utf8).base64EncodedString()

        if try await tryLogin(pass: md5) { loggedInAt = .now; return }
        if try await tryLogin(pass: b64) { loggedInAt = .now; return }
        throw IKuaiError.loginFailed
    }

    private func tryLogin(pass: String) async throws -> Bool {
        let payload: [String: Any] = [
            "username": username,
            "passwd": Self.md5(password),
            "pass": pass,
            "remember_password": ""
        ]
        let (_, data) = try await request("/Action/login", body: payload, bearer: nil, label: "login")
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = (json?["Result"] as? Int) ?? (json?["code"] as? Int) ?? -1
        log.append("登录返回 code=\(code)")
        return code == 10000 || code == 0
    }

    private func callLegacy() async throws -> [IKuaiTerminal] {
        let payload: [String: Any] = [
            "func_name": "monitor_lanip",
            "action": "show",
            "param": [
                "ORDER": "",
                "ORDER_BY": "ip_addr_int",
                "TYPE": "data,total",
                "limit": "0,300",
                "orderType": "IP"
            ]
        ]
        let (_, data) = try await request("/Action/call", body: payload, bearer: nil, label: "call monitor_lanip")

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw IKuaiError.badPayload("返回不是 JSON")
        }
        let result = (json["Result"] as? Int) ?? -1
        if result != 30000 && result != 10000 {
            let msg = (json["ErrMsg"] as? String) ?? ""
            throw IKuaiError.apiFailed(msg.isEmpty ? "Result=\(result)" : "Result=\(result) \(msg)")
        }
        let rows = Self.rows(from: json)
        return rows.map { Self.mapRow($0) }.sorted { ipOrder($0.ip) < ipOrder($1.ip) }
    }

    // MARK: 新固件（4.x REST）

    private func fetchV4() async throws {
        var lastErr: Error = IKuaiError.apiFailed("没有可用接口")
        for path in ["/api/v4.0/monitoring/clients?page=1&limit=100",
                     "/api/v4.0/monitoring/clients-online?page=1&limit=100",
                     "/api/v4.0/monitoring/lan-clients?page=1&limit=100"] {
            do {
                let (code, data) = try await request(path, body: nil, bearer: token, label: "v4 \(path)")
                if code == 401 || code == 403 { throw IKuaiError.loginFailed }
                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    throw IKuaiError.badPayload("返回不是 JSON")
                }
                let rows = Self.rows(from: json)
                if !rows.isEmpty || path.contains("clients?") {
                    terminals = rows.map { Self.mapRow($0) }
                        .sorted { ipOrder($0.ip) < ipOrder($1.ip) }
                    usedMode = "4.x API"
                    lastUpdate = .now
                    return
                }
                lastErr = IKuaiError.badPayload("列表为空")
            } catch {
                lastErr = error
            }
        }
        throw lastErr
    }

    // MARK: 统一请求

    private func request(_ path: String, body: [String: Any]?, bearer: String?,
                         label: String) async throws -> (Int, Data) {
        guard let base = URL(string: baseURL) else { throw IKuaiError.badURL }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path

        let finalURL: URL
        if let q = trimmed.firstIndex(of: "?") {
            let root = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
            let s = root + "/" + String(trimmed[..<q]) + String(trimmed[q...])
            guard let u = URL(string: s) else { throw IKuaiError.badURL }
            finalURL = u
        } else {
            finalURL = base.appendingPathComponent(trimmed)
        }

        var req = URLRequest(url: finalURL)
        req.httpMethod = body == nil ? "GET" : "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("YUNFENG/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if let bearer, !bearer.isEmpty {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, resp) = try await InsecureSession.shared.session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        log.append("\(label) → HTTP \(code)")
        return (code, data)
    }

    // MARK: 字段映射（不同固件字段名不同，做容错）

    nonisolated static func rows(from json: [String: Any]) -> [[String: Any]] {
        if let data = json["data"] as? [[String: Any]] { return data }
        if let data = json["Data"] as? [String: Any] {
            if let list = data["data"] as? [[String: Any]] { return list }
            if let list = data["list"] as? [[String: Any]] { return list }
        }
        if let data = json["Data"] as? [[String: Any]] { return data }
        if let list = json["results"] as? [[String: Any]] { return list }
        if let list = json["list"] as? [[String: Any]] { return list }
        return []
    }

    nonisolated static func mapRow(_ row: [String: Any]) -> IKuaiTerminal {
        func pick(_ keys: [String]) -> String {
            for k in keys {
                if let v = row[k] {
                    if let s = v as? String, !s.isEmpty { return s }
                    if let n = v as? NSNumber { return n.stringValue }
                }
            }
            return ""
        }

        let ip = pick(["ip_addr", "ip", "ip_address"])
        let mac = pick(["mac", "mac_addr", "mac_address"])
        let host = pick(["hostname", "host_name", "name", "comment", "client_name", "term_name", "device_name"])
        var fast = pick(["upload", "up", "up_speed", "upstream"])
        var down = pick(["download", "down", "down_speed", "downstream"])
        if fast.isEmpty { fast = "0" }
        if down.isEmpty { down = "0" }

        var raw: [String: String] = [:]
        for (k, v) in row {
            if let s = v as? String { raw[k] = s }
            else if let n = v as? NSNumber { raw[k] = n.stringValue }
        }

        return IKuaiTerminal(
            id: mac.isEmpty ? ip : mac,
            ip: ip, mac: mac, host: host,
            up: fast, down: down,
            connections: pick(["connect_num", "connect", "conn", "connections"]),
            online: pick(["uptime", "online_time", "connect_time", "online"]),
            raw: raw
        )
    }

    // MARK: 工具

    nonisolated static func md5(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func cookieSummary() -> String {
        let list = HTTPCookieStorage.shared.cookies ?? []
        if list.isEmpty { return "（没有 cookie）" }
        return list.map { "\($0.name)=\($0.value.prefix(6))…" }.joined(separator: " ")
    }

    private func preview(_ data: Data) -> String {
        guard let s = String(data: data, encoding: .utf8) else { return "（\(data.count) 字节，非文本）" }
        return s.count > 1200 ? String(s.prefix(1200)) + "…" : s
    }

    private func describe(_ error: Error) -> String {
        if let e = error as? IKuaiError { return e.text }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorCannotFindHost:
                return "连不上 \(baseURL)。这个地址只有在家（或连上回家的隧道）时才能访问。"
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
                return "证书被拒。检查地址是否 https，或者换个端口试试。"
            case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return "系统拦了明文 http，把地址写成 http:// 或改用 https。"
            default:
                return "网络错误：\(ns.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    private func ipOrder(_ ip: String) -> Int {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return .max }
        return parts.reduce(0) { $0 * 256 + $1 }
    }
}

enum IKuaiError: Error, Equatable {
    case badURL
    case loginFailed
    case notLoggedIn
    case apiFailed(String)
    case badPayload(String)

    var text: String {
        switch self {
        case .badURL:            return "路由器地址格式不对，要带协议和端口"
        case .loginFailed:       return "登录被拒：账号密码不对，或这台是 4.x 固件要填 API Token"
        case .notLoggedIn:       return "会话失效，需要重新登录"
        case .apiFailed(let m):
            if m.contains("-1") {
                return "接口返回 \(m)。会话没被认（可能是 4.x 固件）——填上 API Token 再试，或点「诊断」看原始返回。"
            }
            return "接口返回失败：\(m)"
        case .badPayload(let m): return "数据解析失败：\(m)"
        }
    }
}
