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
    var isOnline: Bool = true
    /// 离线设备用：最后一次在线时间，形如「11-22 18:12」
    var lastSeen: String = ""
    var totalUp: Double = 0
    var totalDown: Double = 0
}

// MARK: - 路由器状态（/api/v4.0/monitoring/system）

struct IKuaiSystem: Equatable {
    var cpuPercent: Double = 0
    var cpuTemp: Double = 0
    var memPercent: String = ""
    var onlineCount: Int = 0
    var wanUp: Double = 0      // bytes/s
    var wanDown: Double = 0    // bytes/s
    var connNum: Int = 0
    var uptime: String = ""
    var version: String = ""
}

// MARK: - 单台终端流量采样（/api/v4.0/monitoring/clients-traffic-load）

struct IKuaiTrafficPoint: Identifiable, Equatable {
    var id: Int          // timestamp
    var timestamp: Int
    var up: Double       // bytes/s
    var down: Double     // bytes/s
    var conns: Int
}

struct IKuaiProtoItem: Identifiable, Equatable {
    var id: String
    var name: String
    var total: Double    // bytes
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
    var offlineTerminals: [IKuaiTerminal] = []
    var sys: IKuaiSystem?
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

    /// 静默刷新：只更新在线列表和路由状态，不动离线表，也不改 status
    func refreshLive() async {
        guard !token.isEmpty else { return }
        if let online = try? await fetchClients(offline: false) {
            terminals = online.sorted { ipOrder($0.ip) < ipOrder($1.ip) }
        }
        if let s = try? await fetchSystem() { sys = s }
        usedMode = "4.x API"
        lastUpdate = .now
        if log.count > 160 { log.removeFirst(log.count - 160) }
    }

    /// 静默刷新离线表（频率低一些，它不会几秒一变）
    func refreshOffline() async {
        guard !token.isEmpty else { return }
        if let off = try? await fetchClients(offline: true) {
            offlineTerminals = off.sorted { ipOrder($0.ip) < ipOrder($1.ip) }
        }
        if log.count > 160 { log.removeFirst(log.count - 160) }
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
                let (code, data) = try await request("/api/v4.0/monitoring/clients-online?page=1&limit=100",
                                                     body: nil, bearer: token,
                                                     label: "[4] GET /api/v4.0/monitoring/clients-online")
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

    // MARK: 新固件（4.x REST，实测可用）
    // GET /api/v4.0/monitoring/clients-online?page=1&limit=200
    // → {"code":0,"message":"Success","results":{"data":[…],"total":N}}

    private func fetchV4() async throws {
        terminals = try await fetchClients(offline: false)
            .sorted { ipOrder($0.ip) < ipOrder($1.ip) }
        offlineTerminals = ((try? await fetchClients(offline: true)) ?? [])
            .sorted { ipOrder($0.ip) < ipOrder($1.ip) }
        sys = try? await fetchSystem()
        usedMode = "4.x API"
        lastUpdate = .now
    }

    /// 在线 / 离线终端列表
    private func fetchClients(offline: Bool) async throws -> [IKuaiTerminal] {
        let path = offline
            ? "/api/v4.0/monitoring/clients-offline?page=1&limit=200"
            : "/api/v4.0/monitoring/clients-online?page=1&limit=200"
        let (httpCode, data) = try await request(path, body: nil, bearer: token,
                                                 label: offline ? "v4 clients-offline" : "v4 clients-online")
        if httpCode == 401 || httpCode == 403 { throw IKuaiError.loginFailed }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw IKuaiError.badPayload("返回不是 JSON")
        }
        let code = (json["code"] as? Int) ?? 0
        if code != 0 {
            throw IKuaiError.apiFailed((json["message"] as? String) ?? "code=\(code)")
        }

        let inner = json["results"] as? [String: Any]
        let rows = (inner?["data"] as? [[String: Any]])
            ?? (inner?["offline_data"] as? [[String: Any]])
            ?? (inner?["list"] as? [[String: Any]])
            ?? (json["data"] as? [[String: Any]])
            ?? []
        return rows.map { Self.mapV4Row($0, online: !offline) }
    }

    /// 路由状态：CPU / 内存 / WAN 实时速率 / 在线数 / 连接数
    private func fetchSystem() async throws -> IKuaiSystem {
        let (httpCode, data) = try await request("/api/v4.0/monitoring/system", body: nil,
                                                 bearer: token, label: "v4 system")
        if httpCode == 401 || httpCode == 403 { throw IKuaiError.loginFailed }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let inner = json["results"] as? [String: Any],
              let info = inner["sysinfo"] as? [String: Any] else {
            throw IKuaiError.badPayload("system 返回结构不符")
        }

        var s = IKuaiSystem()

        // cpu: ["5.75%","5.00%",…] 取各核平均
        if let cores = info["cpu"] as? [Any], !cores.isEmpty {
            let values = cores.map { Self.percent($0) }
            if !values.isEmpty { s.cpuPercent = values.reduce(0, +) / Double(values.count) }
        }
        if let temps = info["cputemp"] as? [Any], let first = temps.first {
            s.cpuTemp = Self.dbl(first)
        }
        if let mem = info["memory"] as? [String: Any] {
            if let used = mem["used"] as? String { s.memPercent = used }
            else if let used = mem["used"] as? NSNumber { s.memPercent = "\(used.intValue)%" }
        }
        if let ou = info["online_user"] as? [String: Any] {
            s.onlineCount = Int(Self.dbl(ou["count"]))
        }
        if let stream = info["stream"] as? [String: Any] {
            s.wanUp = Self.dbl(stream["upload"])
            s.wanDown = Self.dbl(stream["download"])
            s.connNum = Int(Self.dbl(stream["connect_num"]))
        }
        s.uptime = Self.duration(Int(Self.dbl(info["uptime"])))
        if let ver = info["verinfo"] as? [String: Any], let v = ver["version"] as? String {
            s.version = v
        }
        return s
    }

    /// 单台设备的近 5 分钟流量（路由器每 5 秒一个点，共 60 点）
    func fetchTraffic(ip: String, mac: String) async throws -> [IKuaiTrafficPoint] {
        guard !token.isEmpty, !ip.isEmpty else { return [] }
        let path = "/api/v4.0/monitoring/clients-traffic-load?ip=\(ip)&mac=\(mac)"
        let (httpCode, data) = try await request(path, body: nil, bearer: token, label: "v4 traffic-load")
        if httpCode == 401 || httpCode == 403 { throw IKuaiError.loginFailed }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let inner = json["results"] as? [String: Any] else { return [] }
        let rows = (inner["terminal_stream_collect"] as? [[String: Any]])
            ?? (inner["data"] as? [[String: Any]])
            ?? []
        return rows.compactMap { r in
            let ts = Int(Self.dbl(r["timestamp"]))
            guard ts > 0 else { return nil }
            return IKuaiTrafficPoint(id: ts, timestamp: ts,
                                     up: Self.dbl(r["upload"]),
                                     down: Self.dbl(r["download"]),
                                     conns: Int(Self.dbl(r["conn_num"])))
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    /// 单台设备的应用协议占比
    func fetchProtocols(ip: String, mac: String) async throws -> [IKuaiProtoItem] {
        guard !token.isEmpty, !ip.isEmpty else { return [] }
        let path = "/api/v4.0/monitoring/clients/protocols?ip=\(ip)&mac=\(mac)"
        let (httpCode, data) = try await request(path, body: nil, bearer: token, label: "v4 protocols")
        if httpCode == 401 || httpCode == 403 { throw IKuaiError.loginFailed }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let inner = json["results"] as? [String: Any],
              let rows = inner["data"] as? [[String: Any]] else { return [] }
        return rows.compactMap { r in
            guard let name = r["proto_name"] as? String, !name.isEmpty else { return nil }
            return IKuaiProtoItem(id: name, name: name, total: Self.dbl(r["total"]))
        }
        .sorted { $0.total > $1.total }
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
        if log.count > 160 { log.removeFirst(log.count - 160) }
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

    // MARK: 4.x 字段映射（字段名来自实测返回）

    nonisolated static func mapV4Row(_ row: [String: Any], online: Bool = true) -> IKuaiTerminal {
        func str(_ keys: [String]) -> String {
            for k in keys {
                if let s = row[k] as? String, !s.isEmpty { return s }
                if let n = row[k] as? NSNumber { return n.stringValue }
            }
            return ""
        }

        let ip = str(["ip_addr", "ipv4_addr", "ip"])
        let mac = str(["mac"])
        var name = str(["hostname", "termname", "comment"])
        if name.isEmpty { name = str(["client_model"]) }
        if name.isEmpty { name = str(["client_vendor"]) }
        if name.isEmpty { name = "未知设备" }

        let up = dbl(row["upload"])
        let down = dbl(row["download"])

        var raw: [String: String] = [:]
        for (k, v) in row {
            if let s = v as? String { raw[k] = s }
            else if let n = v as? NSNumber { raw[k] = n.stringValue }
        }

        return IKuaiTerminal(
            id: mac.isEmpty ? ip : mac,
            ip: ip, mac: mac, host: name,
            up: online ? kb(up) : "—",
            down: online ? kb(down) : "—",
            connections: str(["connect_num"]),
            online: online ? dur(from: str(["uptime"])) : "",
            raw: raw,
            isOnline: online,
            lastSeen: online ? "" : shortTime(dbl(row["logout_time"])),
            totalUp: dbl(row["total_up"]),
            totalDown: dbl(row["total_down"])
        )
    }

    /// unix 秒 → "11-22 18:12"
    nonisolated static func shortTime(_ ts: Double) -> String {
        guard ts > 1_000_000_000 else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    /// 累计字节 → "11.1M"
    nonisolated static func bytes(_ v: Double) -> String {
        if v >= 1024 * 1024 * 1024 { return String(format: "%.2fG", v / 1073741824) }
        if v >= 1024 * 1024 { return String(format: "%.1fM", v / 1048576) }
        if v >= 1024 { return String(format: "%.0fK", v / 1024) }
        return String(format: "%.0f", v)
    }

    /// 秒数 → "12天3时"
    nonisolated static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let day = seconds / 86400, hour = (seconds % 86400) / 3600, minute = (seconds % 3600) / 60
        if day > 0 { return "\(day)天\(hour)时" }
        if hour > 0 { return "\(hour)时\(minute)分" }
        return "\(minute)分"
    }

    /// "5.75%" / 5.75 / NSNumber → 5.75
    nonisolated static func percent(_ v: Any?) -> Double {
        if let s = v as? String {
            return Double(s.replacingOccurrences(of: "%", with: "")) ?? 0
        }
        return dbl(v)
    }

    /// 字节/秒 → 易读速率（iKuai 返回值就是 bytes/s）
    nonisolated static func kb(_ v: Double) -> String {
        if v >= 1024 * 1024 { return String(format: "%.1fM", v / 1048576) }
        if v >= 1024 { return String(format: "%.0fK", v / 1024) }
        return String(format: "%.0f", v)
    }

    /// "2026-11-21 21:33:48" → "3天22时"
    nonisolated static func dur(from start: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let d = f.date(from: start) else { return "" }
        let s = Int(Date().timeIntervalSince(d))
        guard s > 0 else { return "" }
        let day = s / 86400, hour = (s % 86400) / 3600, minute = (s % 3600) / 60
        if day > 0 { return "\(day)天\(hour)时" }
        if hour > 0 { return "\(hour)时\(minute)分" }
        return "\(minute)分"
    }

    nonisolated static func dbl(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
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
