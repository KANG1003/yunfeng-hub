//
//  IKuaiService.swift
//  爱快路由本地接口：登录 → 拉取 LAN 终端列表
//
//  协议（爱快 3.x / 4.x 本地 Web API）：
//    POST {base}/Action/login   {"username":..,"passwd":<md5>,"pass":<md5>,"remember_password":""}
//    POST {base}/Action/call    {"func_name":"monitor_lanip","action":"show","param":{...}}
//  登录成功返回 Result == 10000，并把 cookie 写在响应里；后续请求带同一 session。
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
    var up: String        // 上行速率（KB/s 数值，原样展示）
    var down: String
    var connections: String
    var online: String    // 在线时长
    var raw: [String: String] = [:]
}

// MARK: - 自签证书放行（爱快 web 是 https 自签）

final class InsecureSession: NSObject, URLSessionDelegate {
    static let shared = InsecureSession()
    lazy var session: URLSession = URLSession(configuration: .ephemeral,
                                             delegate: self,
                                             delegateQueue: nil)

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

    var terminals: [IKuaiTerminal] = []
    var status: Status = .idle
    var message: String = ""
    var lastUpdate: Date?

    var isConfigured: Bool { !password.isEmpty && !baseURL.isEmpty }

    private var loggedInAt: Date?

    // MARK: 拉取

    func refresh() async {
        guard isConfigured else {
            status = .failed
            message = "还没填路由器账号密码，点右上角齿轮设置"
            return
        }
        status = .loading
        message = ""
        do {
            if loggedInAt == nil || Date().timeIntervalSince(loggedInAt!) > 600 {
                try await login()
            }
            let list = try await fetchTerminals()
            terminals = list.sorted { ipOrder($0.ip) < ipOrder($1.ip) }
            status = .ok
            lastUpdate = .now
        } catch {
            // session 过期时重登一次
            if (error as? IKuaiError) == .notLoggedIn {
                loggedInAt = nil
                do {
                    try await login()
                    let list = try await fetchTerminals()
                    terminals = list.sorted { ipOrder($0.ip) < ipOrder($1.ip) }
                    status = .ok
                    lastUpdate = .now
                    return
                } catch {
                    status = .failed
                    message = describe(error)
                    return
                }
            }
            status = .failed
            message = describe(error)
        }
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
            default:
                return "网络错误：\(ns.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    // MARK: 登录

    private func login() async throws {
        let md5 = Self.md5(password)
        let b64 = Data(password.utf8).base64EncodedString()

        // 不同固件对 pass 字段要求不同，先试 md5，再试 base64
        if try await sendLogin(pass: md5) { loggedInAt = .now; return }
        if try await sendLogin(pass: b64) { loggedInAt = .now; return }
        throw IKuaiError.loginFailed
    }

    private func sendLogin(pass: String) async throws -> Bool {
        let payload: [String: Any] = [
            "username": username,
            "passwd": Self.md5(password),
            "pass": pass,
            "remember_password": ""
        ]
        let data = try await post(path: "/Action/login", body: payload)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = (json?["Result"] as? Int) ?? (json?["code"] as? Int) ?? -1
        return code == 10000 || code == 0
    }

    // MARK: 终端列表

    private func fetchTerminals() async throws -> [IKuaiTerminal] {
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
        let data = try await post(path: "/Action/call", body: payload)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw IKuaiError.badPayload("返回不是 JSON")
        }
        let result = (json["Result"] as? Int) ?? -1
        if result != 30000 && result != 10000 {
            let msg = (json["ErrMsg"] as? String) ?? ""
            if msg.contains("登录") || msg.contains("login") || result == -2 {
                throw IKuaiError.notLoggedIn
            }
            throw IKuaiError.apiFailed(msg.isEmpty ? "Result=\(result)" : msg)
        }
        guard let inner = json["Data"] as? [String: Any],
              let rows = inner["data"] as? [[String: Any]] else {
            return []
        }
        return rows.map { Self.mapRow($0) }
    }

    private func post(path: String, body: [String: Any]) async throws -> Data {
        guard let base = URL(string: baseURL) else { throw IKuaiError.badURL }
        let url = base.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await InsecureSession.shared.session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
            throw IKuaiError.notLoggedIn
        }
        return data
    }

    // MARK: 字段映射（不同固件字段名不同，做容错）

    nonisolated static func mapRow(_ row: [String: Any]) -> IKuaiTerminal {
        func pick(_ keys: [String]) -> String {
            for k in keys {
                if let v = row[k] {
                    if let s = v as? String, !s.isEmpty { return s }
                    if let n = v as? NSNumber { return n.stringValue }
                    if let d = v as? Double { return String(format: "%.1f", d) }
                }
            }
            return ""
        }

        let ip = pick(["ip_addr", "ip", "ip_address"])
        let mac = pick(["mac", "mac_addr", "mac_address"])
        let host = pick(["hostname", "host_name", "name", "comment", "client_name", "term_name"])
        var fast = pick(["upload", "up", "up_speed"])
        var down = pick(["download", "down", "down_speed"])
        if fast.isEmpty { fast = "0" }
        if down.isEmpty { down = "0" }

        var raw: [String: String] = [:]
        for (k, v) in row {
            if let s = v as? String { raw[k] = s }
            else if let n = v as? NSNumber { raw[k] = n.stringValue }
        }

        return IKuaiTerminal(
            id: mac.isEmpty ? ip : mac,
            ip: ip,
            mac: mac,
            host: host,
            up: fast,
            down: down,
            connections: pick(["connect_num", "connect", "conn"]),
            online: pick(["uptime", "online_time", "connect_time", "online"]),
            raw: raw
        )
    }

    // MARK: 工具

    nonisolated static func md5(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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
        case .badURL:            return "路由器地址格式不对，要带 https:// 和端口"
        case .loginFailed:       return "登录被拒：账号或密码不对（也可能是没开本地 API）"
        case .notLoggedIn:       return "会话失效，需要重新登录"
        case .apiFailed(let m):  return "接口返回失败：\(m)"
        case .badPayload(let m): return "数据解析失败：\(m)"
        }
    }
}

// build-trigger 0927
