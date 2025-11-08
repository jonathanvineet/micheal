import Foundation

// Matches the server's FileItem shape returned by GET /api/files
public struct FileItem: Identifiable, Codable {
    public var id: String { path }
    public let name: String
    public let isDirectory: Bool
    public let size: Int?
    // Server returns modified as a date-like string or timestamp; handle as String for simplicity
    public let modified: String?
    public let path: String
}
