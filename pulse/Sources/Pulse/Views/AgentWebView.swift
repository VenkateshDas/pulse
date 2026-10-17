import AppKit
import SwiftUI
import WebKit
import PulseKit

/// Only packaged assets are served; no localhost credentials reach JavaScript.
@MainActor
struct AgentWebView: NSViewRepresentable {
    let model: AgentModel
    let snapshot: Snapshot
    @Binding var failure: String?

    func makeCoordinator() -> Coordinator { Coordinator(model: model, snapshot: snapshot, failure: $failure) }
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
        context.coordinator.snapshot = snapshot
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

    struct Snapshot: Encodable {
        var items: [AgentTimelineItem]; let sessions: [AgentSessionItem]; let sessionId: String?
        let status: String; let busy: Bool; let ready: Bool; let state: String; let model: String; let provider: String
        let memories: [AgentMemoryItem]; let memoryEnabled: Bool; let memoryStatus: String; let largerText: Bool; let hasEarlier: Bool
        let draft: String
        let readOnly: Bool
        let usage: AgentUsageSnapshot?
    }

    static func snapshot(for model: AgentModel, largerText: Bool) -> Snapshot {
        let items = model.items.map { item -> AgentTimelineItem in
            var item = item
            if item.kind == .approval { item.isRunning = model.state == .awaitingApproval && item.approvalID == model.approvalId }
            return item
        }
        return Snapshot(items: items, sessions: model.sessions, sessionId: model.sessionId,
            status: model.status, busy: model.isBusy, ready: model.hasApiKey, state: String(describing: model.state),
            model: AgentConfiguration.model, provider: AgentConfiguration.provider,
            memories: model.memories, memoryEnabled: model.memoryEnabled, memoryStatus: model.memoryStatus,
            largerText: largerText, hasEarlier: model.hasEarlier, draft: model.draft, readOnly: model.investigationOnly,
            usage: model.usage)
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var model: AgentModel
        var snapshot: Snapshot
        let failure: Binding<String?>
        weak var view: WKWebView?
        var ready = false
        var active = true
        private var previous: Data?
        private var renderedItems: [String: AgentTimelineItem] = [:]
        private var renderedOrder: [String] = []
        init(model: AgentModel, snapshot: Snapshot, failure: Binding<String?>) { self.model = model; self.snapshot = snapshot; self.failure = failure }

        func publish() {
            guard ready, active else { return }
            var metadata = snapshot; metadata.items = []
            guard let data = try? JSONEncoder().encode(metadata) else { return }
            let changed = snapshot.items.filter { renderedItems[$0.id] != $0 }
            let order = snapshot.items.map(\.id)
            guard data != previous || !changed.isEmpty || order != renderedOrder else { return }
            struct Patch: Encodable { let state: Snapshot?; let items: [AgentTimelineItem]; let order: [String]? }
            let patch = Patch(state: data != previous ? metadata : nil, items: changed, order: order != renderedOrder ? order : nil)
            guard let encoded = try? JSONEncoder().encode(patch), let value = try? JSONSerialization.jsonObject(with: encoded) else { return }
            previous = data; renderedItems = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) }); renderedOrder = order
            // Stream only changed rows; loaded history is not re-encoded for each token.
            view?.callAsyncJavaScript("window.pulsePatch(patch)", arguments: ["patch": value], in: nil, in: .page, completionHandler: { _ in })
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
            case "draft":
                guard let text = body["text"] as? String else { return }
                model.setDraft(text)
            case "mode":
                guard let readOnly = body["readOnly"] as? Bool else { return }
                model.setInvestigationOnly(readOnly)
            case "answer":
                guard let id = body["id"] as? String, id == model.approvalId, let answer = body["text"] as? String else { return }
                model.answerQuestion(answer)
            case "copy":
                guard let text = body["text"] as? String, text.utf8.count <= 128_000 else { return }
                NSPasteboard.general.clearContents()
                let success = NSPasteboard.general.setString(text, forType: .string)
                if let id = body["id"] as? String, id.utf8.count <= 128 {
                    view?.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('pulse-copy', {detail: {id, success}}))",
                        arguments: ["id": id, "success": success], in: nil, in: .page, completionHandler: { _ in })
                }
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
