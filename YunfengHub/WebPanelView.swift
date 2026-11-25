//
//  WebPanelView.swift
//  通用内嵌网页：直接打开自建站点，支持 HTTP Basic 登录（401）
//

import SwiftUI
import UIKit
import WebKit

// MARK: - 持有 WKWebView 引用
final class WebRef {
    weak var webView: WKWebView?
    func reload() { webView?.reload() }
    func back() { webView?.goBack() }
    func forward() { webView?.goForward() }
}

// MARK: - 包装器
struct EmbeddedWeb: UIViewRepresentable {
    let url: URL
    let ref: WebRef
    @Binding var isLoading: Bool
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isLoading: $isLoading, failed: $failed) }

    func makeUIView(context: Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        conf.allowsInlineMediaPlayback = true
        conf.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: conf)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.keyboardDismissMode = .interactive
        ref.webView = web
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        ref.webView = web
        if web.url == nil { web.load(URLRequest(url: url)) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let isLoading: Binding<Bool>
        let failed: Binding<Bool>

        init(isLoading: Binding<Bool>, failed: Binding<Bool>) {
            self.isLoading = isLoading
            self.failed = failed
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading.wrappedValue = true
            failed.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
            failed.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            isLoading.wrappedValue = false
            failed.wrappedValue = true
        }

        /// 401 / 407 时弹用户名密码框（nginx basic auth 很常见）
        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition,
                                                   URLCredential?) -> Void) {

            let method = challenge.protectionSpace.authenticationMethod

            if method == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }

            guard method == NSURLAuthenticationMethodHTTPBasic
                    || method == NSURLAuthenticationMethodHTTPDigest else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            let hostKey = challenge.protectionSpace.host
            let userKey = "auth.user.\(hostKey)"
            let passKey = "auth.pass.\(hostKey)"

            if let u = UserDefaults.standard.string(forKey: userKey),
               let p = UserDefaults.standard.string(forKey: passKey),
               !u.isEmpty {
                completionHandler(.useCredential,
                                  URLCredential(user: u, password: p, persistence: .permanent))
                return
            }

            Task { @MainActor in
                guard let presenter = webView.window?.rootViewController?.topMost else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }
                let alert = UIAlertController(
                    title: "需要登录",
                    message: "\(hostKey) 要求输入用户名和密码",
                    preferredStyle: .alert)
                alert.addTextField {
                    $0.placeholder = "用户名"
                    $0.autocapitalizationType = .none
                    $0.autocorrectionType = .no
                }
                alert.addTextField {
                    $0.placeholder = "密码"
                    $0.isSecureTextEntry = true
                }
                alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
                    completionHandler(.cancelAuthenticationChallenge, nil)
                })
                alert.addAction(UIAlertAction(title: "登录", style: .default) { _ in
                    let u = alert.textFields?.first?.text ?? ""
                    let p = alert.textFields?.last?.text ?? ""
                    UserDefaults.standard.set(u, forKey: userKey)
                    UserDefaults.standard.set(p, forKey: passKey)
                    completionHandler(.useCredential,
                                      URLCredential(user: u, password: p, persistence: .permanent))
                })
                presenter.present(alert, animated: true)
            }
        }
    }
}

// MARK: - 页面
struct WebPanelView: View {
    let title: String
    let subtitle: String
    let urlString: String
    var dismissible: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var ref = WebRef()
    @State private var isLoading = true
    @State private var failed = false

    private var url: URL? { URL(string: urlString) }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let url {
                EmbeddedWeb(url: url, ref: ref, isLoading: $isLoading, failed: $failed)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("地址无效", systemImage: "link.badge.plus")
            }

            if isLoading {
                ProgressView().scaleEffect(1.2)
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if failed {
                VStack(spacing: 12) {
                    Text("没加载出来").font(.system(size: 14, weight: .semibold))
                    Text(urlString).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        GhostButton(title: "重试", systemImage: "arrow.clockwise") {
                            failed = false
                            ref.reload()
                        }
                        GhostButton(title: "用浏览器打开", systemImage: "safari") { openInSafari() }
                    }
                }
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }

            toolbar
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            if dismissible {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { openInSafari() } label: { Image(systemName: "safari") }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            Button { ref.back() } label: { Image(systemName: "chevron.left") }
            Button { ref.forward() } label: { Image(systemName: "chevron.right") }
            Button { ref.reload() } label: { Image(systemName: "arrow.clockwise") }
            Spacer()
            Button { openInSafari() } label: { Image(systemName: "square.and.arrow.up") }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }

    private func openInSafari() {
        guard let url else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - 顶层控制器
extension UIViewController {
    var topMost: UIViewController {
        if let presented = presentedViewController { return presented.topMost }
        if let nav = self as? UINavigationController, let visible = nav.visibleViewController {
            return visible.topMost
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.topMost
        }
        return self
    }
}
