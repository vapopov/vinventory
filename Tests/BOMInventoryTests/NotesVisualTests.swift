import XCTest
import AppKit
import WebKit
@testable import BOMInventory

final class NotesVisualTests: XCTestCase {
    @MainActor private func js(_ web: WKWebView, _ script: String) async throws -> Any {
        let body: String
        if let separator = script.lastIndex(of: ";"), script[script.index(after: separator)...].trimmingCharacters(in: .whitespaces) == "true" {
            body = String(script[...separator]) + "return true;"
        } else { body = "return (" + script + ");" }
        let json: String = try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript("JSON.stringify((()=>{\(body)})())") { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value as? String ?? "null") }
            }
        }
        return try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
    }
    @MainActor private func editor() async throws -> WKWebView {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let url = try XCTUnwrap(NotesVisualDocument.pageURL)
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        for _ in 0..<100 {
            if (try? await js(web, "typeof window.notes === 'object'")) as? Bool == true { return web }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Visual editor did not load"); return web
    }
    @MainActor private func load(_ text: NSAttributedString, web: WKWebView) async throws {
        let literal = try XCTUnwrap(String(data: JSONEncoder().encode(NotesMathPreview.html(text)), encoding: .utf8))
        _ = try await js(web, "window.notes.load(\(literal)); true")
    }
    @MainActor private func tokens(_ web: WKWebView) async throws -> [NotesVisualToken] {
        let value = try await js(web, "window.notes.exportTokens()")
        return try JSONDecoder().decode([NotesVisualToken].self, from: JSONSerialization.data(withJSONObject: value))
    }
    @MainActor func testVisualMathEditingUndoAndRTFRoundTrip() async throws {
        let web = try await editor()
        try await load(NSAttributedString(string: #"Inline $V=IR$ and $$f=\frac{1}{2\pi\sqrt{LC}}$$"#), web: web)
        let count = try await js(web, "document.querySelectorAll('#editor .math').length") as? Int
        XCTAssertEqual(count, 2)
        let source = try await tokens(web)
        XCTAssertEqual(source.filter { $0.kind == "math" }.map(\.value), ["V=IR", #"f=\frac{1}{2\pi\sqrt{LC}}"#])
        _ = try await js(web, "document.querySelector('.math').click();document.getElementById('latex').value='R=V/I';document.getElementById('equationForm').requestSubmit();true")
        let edited = try await tokens(web)
        XCTAssertEqual(edited.first { $0.kind == "math" }?.value, "R=V/I")
        _ = try await js(web, "window.notes.command('undo')")
        let undone = try await tokens(web)
        XCTAssertEqual(undone.first { $0.kind == "math" }?.value, "V=IR")
        _ = try await js(web, "window.notes.command('redo')")
        let redone = try await tokens(web)
        XCTAssertEqual(redone.first { $0.kind == "math" }?.value, "R=V/I")
        let session = NotesEditorSession(notes: PartNotes())
        session.webView = web; session.ready = true
        let note = try await session.document()
        try await load(NotesDocument.load(note), web: web)
        let reopened = try await tokens(web)
        XCTAssertEqual(reopened.filter { $0.kind == "math" }.map(\.value), edited.filter { $0.kind == "math" }.map(\.value))
    }
    @MainActor func testTypingConvertsMathInPlaceAndPreservesFormatting() async throws {
        let web = try await editor()
        try await load(NSAttributedString(string: ""), web: web)
        _ = try await js(web, #"document.getElementById('editor').focus();document.execCommand('insertText',false,'$$V=IR$');document.getElementById('editor').dispatchEvent(new InputEvent('input'));true"#)
        let partial = try await js(web, "document.querySelectorAll('#editor .math').length") as? Int
        XCTAssertEqual(partial, 0)
        _ = try await js(web, #"document.execCommand('insertText',false,'$');document.getElementById('editor').dispatchEvent(new InputEvent('input'));true"#)
        let complete = try await tokens(web)
        XCTAssertEqual(complete.first { $0.kind == "math" }?.value, "V=IR")
        XCTAssertEqual(complete.first { $0.kind == "math" }?.display, true)
        let styled = NSAttributedString(string: "Bold & <safe>", attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .underlineStyle: 1])
        try await load(styled, web: web)
        let restored = try NotesVisualDocument.attributedString(await tokens(web))
        XCTAssertEqual(restored.string, styled.string)
        XCTAssertTrue(NSFontManager.shared.traits(of: try XCTUnwrap(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)).contains(.boldFontMask))
        XCTAssertEqual(restored.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, 1)
    }
    @MainActor func testVisualImagesStayManagedAfterSaving() async throws {
        let web = try await editor()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let input = [NotesVisualToken(kind: "text", value: "Picture: "), NotesVisualToken(kind: "image", value: "data:image/png;base64," + image.base64EncodedString())]
        try await load(NotesVisualDocument.attributedString(input), web: web)
        let exported = try await tokens(web)
        XCTAssertEqual(exported.filter { $0.kind == "image" }.count, 1)
        let draft = AttachmentDraft()
        let note = try NotesDocument.save(NotesVisualDocument.attributedString(exported), draft: draft)
        XCTAssertEqual(note.images.count, 1)
        try await load(NotesDocument.load(note), web: web)
        let reopened = try await tokens(web)
        XCTAssertEqual(reopened.filter { $0.kind == "image" }.count, 1)
    }
}
