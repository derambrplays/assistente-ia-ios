import Foundation
import UIKit
import UniformTypeIdentifiers

/// Um arquivo anexado a uma mensagem. O conteúdo fica guardado no próprio
/// iPhone (Application Support); a mensagem salva só os metadados.
struct Attachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var mimeType: String
    var fileName: String
    var byteCount: Int

    var isImage: Bool { mimeType.hasPrefix("image/") }

    var isText: Bool {
        if mimeType.hasPrefix("text/") { return true }
        let textExtensions = [
            "txt", "md", "markdown", "json", "csv", "xml", "html", "htm",
            "css", "js", "ts", "swift", "py", "java", "kt", "c", "h",
            "cpp", "cs", "php", "rb", "go", "rs", "sh", "yml", "yaml",
            "log", "ini", "conf", "sql"
        ]
        return textExtensions.contains(fileExtension)
    }

    var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    var symbol: String {
        if isImage { return "photo" }
        if mimeType == "application/pdf" { return "doc.richtext" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType.hasPrefix("video/") { return "video" }
        if isText { return "doc.text" }
        return "doc"
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

enum AttachmentStore {
    /// Limite por arquivo e limite total por mensagem (a API aceita ~20 MB
    /// de dados embutidos por requisição; deixamos uma margem de segurança).
    static let maxFileBytes = 8 * 1024 * 1024
    static let maxTotalBytes = 14 * 1024 * 1024
    static let maxCount = 5

    private static let cache = NSCache<NSString, UIImage>()

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for attachment: Attachment) -> URL {
        directory.appendingPathComponent(attachment.fileName)
    }

    static func data(for attachment: Attachment) -> Data? {
        try? Data(contentsOf: url(for: attachment))
    }

    static func image(for attachment: Attachment) -> UIImage? {
        guard attachment.isImage else { return nil }
        if let cached = cache.object(forKey: attachment.fileName as NSString) {
            return cached
        }
        guard let data = data(for: attachment), let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: attachment.fileName as NSString)
        return image
    }

    static func totalBytes(_ attachments: [Attachment]) -> Int {
        attachments.reduce(0) { $0 + $1.byteCount }
    }

    static func remove(_ attachment: Attachment) {
        cache.removeObject(forKey: attachment.fileName as NSString)
        try? FileManager.default.removeItem(at: url(for: attachment))
    }

    /// Grava o arquivo e devolve os metadados. Devolve nil se vazio ou grande demais.
    static func make(name: String, mimeType: String, data: Data) -> Attachment? {
        guard !data.isEmpty, data.count <= maxFileBytes else { return nil }
        let ext = extensionFor(mimeType: mimeType, name: name)
        let fileName = UUID().uuidString + "." + ext
        let destination = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            return nil
        }
        return Attachment(
            name: name,
            mimeType: mimeType,
            fileName: fileName,
            byteCount: data.count
        )
    }

    /// Lê um arquivo escolhido no seletor de documentos. Imagens são
    /// redimensionadas e convertidas para JPEG (mais rápido de enviar).
    static func makeFile(url: URL) -> Attachment? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > maxFileBytes { return nil }

        guard let raw = try? Data(contentsOf: url) else { return nil }
        let mime = mimeType(for: url)

        if mime.hasPrefix("image/"), let jpeg = compressedImageData(raw) {
            let base = url.deletingPathExtension().lastPathComponent
            return make(name: base + ".jpg", mimeType: "image/jpeg", data: jpeg)
        }

        return make(name: url.lastPathComponent, mimeType: mime, data: raw)
    }

    /// Redimensiona para no máximo 1600 px e converte para JPEG.
    static func compressedImageData(
        _ data: Data,
        maxSide: CGFloat = 1600,
        quality: CGFloat = 0.8
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, maxSide / longest)
        let size = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    static func text(for attachment: Attachment) -> String? {
        guard attachment.isText, let data = data(for: attachment) else { return nil }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        guard let text = text else { return nil }
        return String(text.prefix(120_000))
    }

    static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    private static func extensionFor(mimeType: String, name: String) -> String {
        let fromName = (name as NSString).pathExtension.lowercased()
        if !fromName.isEmpty { return fromName }
        if let type = UTType(mimeType: mimeType),
           let preferred = type.preferredFilenameExtension {
            return preferred
        }
        return "dat"
    }
}
