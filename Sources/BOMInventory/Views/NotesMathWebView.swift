import SwiftUI
// WebKit delegate SDK annotations predate strict concurrency; this bridge stays on MainActor.
@preconcurrency import WebKit

struct NotesMathWebView: NSViewRepresentable {
    var session: NotesEditorSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "notes")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        session.webView = web
        if let url = NotesVisualDocument.pageURL { web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        else { session.error = "The notes editor resources are missing." }
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {}
    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "notes")
        web.navigationDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let session: NotesEditorSession
        init(session: NotesEditorSession) { self.session = session }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let data = try? JSONEncoder().encode(session.initialHTML), let literal = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.notes.load(\(literal)); true") { [weak self] _, error in
                if let error { self?.session.error = error.localizedDescription }
                else { self?.session.ready = true }
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { session.error = error.localizedDescription }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let data = message.body as? [String: String], data["action"] == "paste" else { return }
            session.paste()
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let initial = navigationAction.navigationType == .other && navigationAction.request.url?.standardizedFileURL == NotesVisualDocument.pageURL?.standardizedFileURL
            decisionHandler(initial ? .allow : .cancel)
        }
    }
}
