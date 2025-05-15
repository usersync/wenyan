//
//  MarkdownView.swift
//  WenYan
//
//  Created by Lei Cao on 2024/8/19.
//

import SwiftUI
import WebKit

enum TimeoutError: Error {
    case timedOut
}

struct MarkdownView: NSViewRepresentable {
    @EnvironmentObject var viewModel: MarkdownViewModel
    
    func makeNSView(context: Context) -> WKWebView {
        let userController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userController
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        viewModel.setupWebView(webView)
        viewModel.loadIndex()
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {

    }
    
}

class MarkdownViewModel: NSObject, WKNavigationDelegate, WKScriptMessageHandler, ObservableObject {
    var appState: AppState
    @Published var content: String = ""
    @Published var scrollFactor: CGFloat = 0
    weak var webView: WKWebView?
    
    init(appState: AppState) {
        self.appState = appState
    }

    // 初始化 WebView
    func setupWebView(_ webView: WKWebView) {
        webView.navigationDelegate = self
        let contentController = webView.configuration.userContentController
        contentController.add(self, name: WebkitStatus.loadHandler)
        contentController.add(self, name: WebkitStatus.contentChangeHandler)
        contentController.add(self, name: WebkitStatus.scrollHandler)
        contentController.add(self, name: WebkitStatus.clickHandler)
        contentController.add(self, name: WebkitStatus.errorHandler)
        contentController.add(self, name: WebkitStatus.uploadHandler)
        webView.setValue(true, forKey: "drawsTransparentBackground")
        webView.allowsMagnification = false
        self.webView = webView
    }
    
    // WKNavigationDelegate 方法
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
//        print("didFinish")
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
//        print("didFail")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
//        print("didFailProvisionalNavigation")
    }
    
    // WKScriptMessageHandler 方法
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // 处理来自 JavaScript 的消息
        if message.name == WebkitStatus.loadHandler {
            configWebView()
        } else if message.name == WebkitStatus.contentChangeHandler {
            let content = (message.body as? String) ?? ""
            self.content = content
            Task {
                UserDefaults.standard.set(content, forKey: "lastArticle")
            }
        } else if message.name == WebkitStatus.scrollHandler {
            guard let body = message.body as? [String: CGFloat], let y = body["y0"] else { return }
            scrollFactor = y
        } else if message.name == WebkitStatus.clickHandler {
            if appState.showThemeList {
                appState.showThemeList = false
            }
        } else if message.name == WebkitStatus.errorHandler {
            let content = (message.body as? String) ?? ""
            appState.appError = AppError.bizError(description: content)
        } else if message.name == WebkitStatus.uploadHandler {
            guard let body = message.body as? [String: Any],
                  let name = body["name"] as? String,
                  let type = body["type"] as? String,
                  let dataArray = body["data"] as? [UInt8] else {
                appState.appError = AppError.bizError(description: "未找到需上传的文件")
                onFileUploadFailed()
                return
            }
            let fileData = Data(dataArray)
            Task {
                await upload(fileData: fileData, fileName: name, mimeType: type)
            }
        }
    }
}

extension MarkdownViewModel {
    func configWebView() {
        setContent()
    }
    
    func loadIndex() {
        do {
            let html = try loadFileFromResource(forResource: "codemirror/index", withExtension: "html")
            webView?.loadHTMLString(html, baseURL: getResourceBundle())
        } catch {
            appState.appError = AppError.bizError(description: error.localizedDescription)
        }
    }
    
    func setContent() {
        callJavascript(javascriptString: "setContent(\(content.toJavaScriptString()));")
    }
    
    func getContent(_ block: JavascriptCallback?) {
        callJavascript(javascriptString: "getContent();", callback: block)
    }
    
    func scroll(scrollFactor: CGFloat) {
        callJavascript(javascriptString: "scroll(\(scrollFactor));")
    }
    
    func onFileUploadComplete(_ url: String) {
        callJavascript(javascriptString: "window.onFileUploadComplete(\(url.toJavaScriptString()));")
    }
    
    func onFileUploadFailed() {
        callJavascript(javascriptString: "window.onFileUploadComplete();")
    }
    
    private func callJavascript(javascriptString: String, callback: JavascriptCallback? = nil) {
        WenYan.callJavascript(webView: webView, javascriptString: javascriptString, callback: callback)
    }
    
    func loadArticle() {
        if let lastArticle = UserDefaults.standard.string(forKey: "lastArticle") {
            content = lastArticle
        } else {
            loadDefaultArticle()
        }
    }
    
    func loadDefaultArticle() {
        do {
            content = try loadFileFromResource(forResource: "example", withExtension: "md")
        } catch {
            self.appState.appError = AppError.bizError(description: error.localizedDescription)
        }
    }
    
    func openArticle(url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "md" || fileExtension == "markdown" {
            do {
                content = try String(contentsOfFile: url.path, encoding: .utf8)
                setContent()
            } catch {
                self.appState.appError = AppError.bizError(description: error.localizedDescription)
            }
        }
    }
    
    func upload(fileData: Data, fileName: String, mimeType: String) async {
        let ebabledImageHost = UserDefaults.standard.string(forKey: "ebabledImageHost")
        guard let enabled = ebabledImageHost, enabled != "" else {
            appState.appError = AppError.bizError(description: "未启用图床")
            onFileUploadFailed()
            return
        }
        if enabled == Settings.ImageHosts.gzh.id {
            guard let savedData = UserDefaults.standard.data(forKey: "gzhImageHost"),
                  let gzhImageHost = try? JSONDecoder().decode(GzhImageHost.self, from: savedData) else {
                appState.appError = AppError.bizError(description: "图床未配置")
                onFileUploadFailed()
                return
            }
            if let uploader = UploaderFactory.createUploader(config: gzhImageHost) {
                do {
                    if let url = try await uploader.upload(fileData: fileData, fileName: fileName, mimeType: mimeType) {
                        onFileUploadComplete(url.replacingOccurrences(of: "http://", with: "https://"))
                    } else {
                        onFileUploadFailed()
                    }
                } catch {
                    self.appState.appError = AppError.bizError(description: "公众号图床上传失败: \(error.localizedDescription)")
                    onFileUploadFailed()
                }
            } else {
                appState.appError = AppError.bizError(description: "公众号图床配置错误")
                onFileUploadFailed()
            }
        } else if enabled == Settings.ImageHosts.github.id {
            guard let savedData = UserDefaults.standard.data(forKey: "githubImageHost"),
                  let githubImageHost = try? JSONDecoder().decode(GitHubImageHost.self, from: savedData) else {
                appState.appError = AppError.bizError(description: "GitHub 图床未配置，请在设置中检查配置。")
                onFileUploadFailed()
                return
            }
            if let uploader = UploaderFactory.createUploader(config: githubImageHost) {
                do {
                    let urlString: String? = try await withThrowingTaskGroup(of: String?.self, returning: String?.self) { group in
                        // Upload task
                        group.addTask {
                            return try await uploader.upload(fileData: fileData, fileName: fileName, mimeType: mimeType)
                        }

                        // Timeout task
                        group.addTask {
                            try await Task.sleep(nanoseconds: 20_000_000_000) // 20 seconds
                            throw TimeoutError.timedOut
                        }

                        // Await the first task to complete or throw.
                        // If upload completes first, its result is returned.
                        // If timeout completes first (throws TimeoutError), that error is propagated.
                        // If upload throws another error, that error is propagated.
                        let firstResult = try await group.next()
                        group.cancelAll() // Cancel the other task (timeout or upload if one finished)
                        return firstResult.flatMap { $0 }
                    }

                    if let validUrl = urlString {
                        onFileUploadComplete(validUrl)
                    } else {
                        // This case handles if uploader.upload itself returns nil without throwing an error
                        appState.appError = AppError.bizError(description: "GitHub 图床上传失败，未返回有效URL。请检查配置和网络。")
                        onFileUploadFailed()
                    }
                } catch is TimeoutError { // Catches TimeoutError thrown from the group
                    appState.appError = AppError.bizError(description: "GitHub 图床上传超时 (20秒)。请检查网络连接或仓库设置。")
                    onFileUploadFailed()
                } catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut {
                    appState.appError = AppError.bizError(description: "GitHub 图床上传超时。请检查您的网络连接。可能的原因：网络不稳定、GitHub API响应慢。")
                    onFileUploadFailed()
                } catch {
                    var errorMessage = "GitHub 图床上传失败: \(error.localizedDescription)"
                    errorMessage += "\n\n可能的原因：\n1. GitHub Token 无效或权限不足。\n2. 仓库配置错误（名称、分支、路径）。\n3. 网络连接问题或防火墙限制。\n4. 文件名包含特殊字符。"
                    self.appState.appError = AppError.bizError(description: errorMessage)
                    onFileUploadFailed()
                }
            } else {
                appState.appError = AppError.bizError(description: "GitHub 图床配置错误，无法创建上传器。")
                onFileUploadFailed()
            }
        }
    }
}
