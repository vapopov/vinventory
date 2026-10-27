import XCTest
import AppKit
import WebKit
@testable import BOMInventory

final class NotesMathTests: XCTestCase {
    @MainActor func testOfflineMathRendersAndTextRemainsEscaped() async throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 500), configuration: configuration)
        let url = try XCTUnwrap(NotesMathPreview.pageURL)
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        var ready = false
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("typeof window.updateNotes === 'function'")) as? Bool == true { ready = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(ready)
        let text = NSAttributedString(string: #"Inline $V=IR$ and $$f=\frac{1}{2\pi\sqrt{LC}}$$ <script>window.injected=true</script>"#)
        let html = NotesMathPreview.html(text)
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        let literal = try XCTUnwrap(String(data: JSONEncoder().encode(html), encoding: .utf8))
        _ = try await web.evaluateJavaScript("window.updateNotes(\(literal)); true")
        let count = try await web.evaluateJavaScript("document.querySelectorAll('.katex').length") as? Int
        XCTAssertEqual(count, 2)
        let errors = try await web.evaluateJavaScript("document.querySelectorAll('.katex-error').length") as? Int
        XCTAssertEqual(errors, 0)
        let escaped = try await web.evaluateJavaScript("window.injected === undefined") as? Bool
        XCTAssertEqual(escaped, true)
        let fraction = try await web.evaluateJavaScript("document.querySelectorAll('.mfrac').length > 0") as? Bool
        XCTAssertEqual(fraction, true)
    }
    @MainActor func testPreviewPreservesFormattingAndLaTeXSource() {
        let text = NSAttributedString(string: #"Bold $R=\frac{V}{I}$"#, attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .underlineStyle: NSUnderlineStyle.single.rawValue])
        let html = NotesMathPreview.html(text)
        XCTAssertTrue(html.contains("font-weight:bold"))
        XCTAssertTrue(html.contains("text-decoration:underline"))
        XCTAssertTrue(html.contains(#"$R=\frac{V}{I}$"#))
    }
}
