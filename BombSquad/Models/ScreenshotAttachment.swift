import Foundation

struct ScreenshotAttachment: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let createdAt: Date
    let pixelWidth: Int?
    let pixelHeight: Int?

    init(
        id: UUID = UUID(),
        url: URL,
        createdAt: Date = Date(),
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    var fileName: String {
        url.lastPathComponent
    }

    var sizeLabel: String? {
        guard let pixelWidth, let pixelHeight else { return nil }
        return "\(pixelWidth)x\(pixelHeight)"
    }
}
