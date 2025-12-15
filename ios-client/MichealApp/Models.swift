import Foundation

// Matches the server's FileItem shape returned by GET /api/files
public struct FileItem: Identifiable, Codable {
    public var id: String { path }
    public let name: String
    public let isDirectory: Bool
    public let size: Int
    // Server returns modified as a date-like string or timestamp; handle as String for simplicity
    public let modified: String?
    public let path: String
    
    // Custom init to handle optional size from server
    public init(name: String, isDirectory: Bool, size: Int?, modified: String?, path: String) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size ?? 0
        self.modified = modified
        self.path = path
    }
}

// Todo item model
public struct TodoItem: Identifiable, Codable {
    public let id: String
    public var text: String
    public var completed: Bool
    public let createdAt: String
    
    public init(id: String, text: String, completed: Bool, createdAt: String) {
        self.id = id
        self.text = text
        self.completed = completed
        self.createdAt = createdAt
    }
}

