import AppKit
import SwiftUI
import WebKit
import PulseKit

/// Only packaged assets are served; no localhost credentials reach JavaScript.
@MainActor
struct AgentWebView: NSViewRepresentable {
    let model: AgentModel
    @Binding var failure: String?

    func makeCoordinator() -> Coordinator { Coordinator(model: model, failure: $failure) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let handler = AssistantAssets()
        configuration.setURLSchemeHandler(handler, forURLScheme: "pulse-assistant")
        configuration.userContentController.add(context.coordinator, name: "pulse")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.view = view
        view.load(URLRequest(url: URL(string: "pulse-assistant://local/index.html")!))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.model = model
        context.coordinator.publish()
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.active = false
        coordinator.view = nil
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "pulse")
        view.navigationDelegate = nil; view.uiDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var model: AgentModel
        let failure: Binding<String?>
        weak var view: WKWebView?
        var ready = false
        var active = true
        private var previous: Data?
        init(model: AgentModel, failure: Binding<String?>) { self.model = model; self.failure = failure }

        func publish() {
            // Read observable state even before readiness, so SwiftUI tracks it.
            let items = model.items.map { item -> AgentTimelineItem in
                var item = item
                if item.kind == .approval { item.isRunning = model.state == .awaitingApproval && item.approvalID == model.approvalId }
                return item
            }
            struct Snapshot: Encodable {
                let items: [AgentTimelineItem]; let sessions: [AgentSessionItem]; let sessionId: String?
                let status: String; let busy: Bool; let ready: Bool; let state: String; let model: String; let provider: String
                let memories: [AgentMemoryItem]; let memoryEnabled: Bool; let memoryStatus: String; let largerText: Bool; let hasEarlier: Bool
            }
            let snapshot = Snapshot(items: items, sessions: model.sessions, sessionId: model.sessionId,
                status: model.status, busy: model.isBusy, ready: model.hasApiKey, state: String(describing: model.state),
                model: AgentConfiguration.model, provider: AgentConfiguration.provider,
                memories: model.memories, memoryEnabled: model.memoryEnabled, memoryStatus: model.memoryStatus,
                largerText: ThemeManager.shared.largerText, hasEarlier: model.hasEarlier)
            guard ready, active, let data = try? JSONEncoder().encode(snapshot), data != previous,
                  let state = try? JSONSerialization.jsonObject(with: data) else { return }
            previous = data
            view?.callAsyncJavaScript("window.pulseReceive(state)", arguments: ["state": state], in: nil, in: .page, completionHandler: { _ in })
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard active, message.frameInfo.isMainFrame,
                  message.frameInfo.request.url?.scheme == "pulse-assistant",
                  let body = message.body as? [String: Any], body["version"] as? Int == 1,
                  let action = body["action"] as? String else { return }
            switch action {
            case "ready": ready = true; publish()
            case "send":
                guard model.hasApiKey, let text = body["text"] as? String, text.utf8.count <= 12_000 else { return }
                model.send(text)
            case "copy":
                guard let text = body["text"] as? String, text.utf8.count <= 128_000 else { return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            case "stop": model.cancel()
            case "new": model.newConversation()
            case "session":
                guard let id = body["id"] as? String, UUID(uuidString: id) != nil else { return }
                Task { await model.loadSession(id) }
            case "older": Task { await model.loadEarlier() }
            case "approve":
                guard let id = body["id"] as? String, id == model.approvalId, let approved = body["approved"] as? Bool else { return }
                model.resolveApproval(approved)
            case "settings": PulseNavigation.open(.settings)
            case "reconnect": Task { await model.start() }
            case "memory": Task { await model.refreshMemory() }
            case "memoryDelete":
                guard let id = body["id"] as? String else { return }
                Task { await model.deleteMemory(id) }
            case "memoryToggle":
                guard let enabled = body["enabled"] as? Bool else { return }
                Task { await model.setMemoryEnabled(enabled) }
            default: break
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "pulse-assistant", url.host == "local" { decisionHandler(.allow); return }
            if navigationAction.navigationType == .linkActivated, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            return nil
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failure.wrappedValue = "The chat renderer stopped. Reload to restore your conversation." }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failure.wrappedValue = "Packaged chat assets could not load. Rebuild Pulse and reload." }
    }
}

@MainActor private final class AssistantAssets: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.host == "local",
              let root = Bundle.module.resourceURL?.appendingPathComponent("Assistant", isDirectory: true) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let file = root.appendingPathComponent(String(url.path.dropFirst())).standardizedFileURL
        let types = ["html": "text/html", "js": "application/javascript", "css": "text/css", "svg": "image/svg+xml", "woff2": "font/woff2"]
        guard file.path.hasPrefix(root.standardizedFileURL.path + "/"), let mime = types[file.pathExtension],
              let data = try? Data(contentsOf: file), data.count < 4_000_000 else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
