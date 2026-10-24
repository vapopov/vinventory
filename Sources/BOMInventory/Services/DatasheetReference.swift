import Foundation
import PDFKit

enum DatasheetReference {
    static func url(for value: String) throws -> URL {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        guard let url = URL(string: value), url.isFileURL || (["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil) else {
            throw InventoryError.message("Enter an HTTP/HTTPS datasheet URL or import a local PDF.")
        }
        return url
    }
    static func validatePDF(at url: URL) throws {
        try validatePDF(data: Data(contentsOf: url))
    }
    static func validatePDF(data: Data) throws {
        guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else {
            throw InventoryError.message("The selected or downloaded file is not a readable PDF.")
        }
    }
}

struct DatasheetDownloader {
    static func download(from source: URL, to destination: URL, session: URLSession = .shared) async throws {
        guard ["https", "http"].contains(source.scheme?.lowercased() ?? ""), source.host != nil else {
            throw InventoryError.message("Enter an HTTP or HTTPS URL to download a datasheet.")
        }
        // Many vendor catalogs still publish HTTP links even when the same PDF is
        // available over HTTPS. Upgrade before URLSession encounters macOS ATS.
        guard var components = URLComponents(url: source, resolvingAgainstBaseURL: false) else {
            throw InventoryError.message("The datasheet URL is invalid.")
        }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
            if components.port == 80 { components.port = nil }
        }
        guard let secureURL = components.url else { throw InventoryError.message("The datasheet URL is invalid.") }
        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: URLRequest(url: secureURL, timeoutInterval: 60)) }
        catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            throw InventoryError.message("This server redirected to an unsecured connection. Use an HTTPS PDF link or import the PDF from a file.")
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw InventoryError.message("The datasheet server returned an unsuccessful response.")
        }
        try DatasheetReference.validatePDF(data: data)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Task.checkCancellation()
        try data.write(to: destination, options: .atomic)
    }
}
