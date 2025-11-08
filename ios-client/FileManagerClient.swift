import Foundation
import UIKit

/// Simple HTTP client for Gabriel server API. Configure `SERVER_BASE_URL` to point to your running Next.js server.
final class FileManagerClient {
    static let shared = FileManagerClient()
    
    // TODO: set this to your machine IP or localhost when testing in simulator
    private let SERVER_BASE_URL = "http://192.168.1.75:3000"
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }
    
    // List files in a directory
    func listFiles(path: String = "", completion: @escaping (Result<[FileItem], Error>) -> Void) {
        guard var components = URLComponents(string: SERVER_BASE_URL + "/api/files") else { return }
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else { return }

        let task = session.dataTask(with: url) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data else { completion(.failure(NSError(domain: "no-data", code: -1))); return }
            do {
                let decoder = JSONDecoder()
                // Server returns { files: [...] }
                let top = try decoder.decode([String: [FileItem]].self, from: data)
                let items = top["files"] ?? []
                completion(.success(items))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    // Download file to a local url and return local file URL
    func downloadFile(at serverPath: String, completion: @escaping (Result<URL, Error>) -> Void) {
        guard var components = URLComponents(string: SERVER_BASE_URL + "/api/download") else { return }
        components.queryItems = [URLQueryItem(name: "path", value: serverPath)]
        guard let url = components.url else { return }
        let task = session.downloadTask(with: url) { tempURL, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let tempURL = tempURL else { completion(.failure(NSError(domain: "no-temp", code: -1))); return }
            // Move to documents directory with the same filename
            do {
                let fileName = serverPath.split(separator: "/").last.map(String.init) ?? "download"
                let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.moveItem(at: tempURL, to: dest)
                completion(.success(dest))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    // Delete a file or folder on server
    func delete(serverPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: SERVER_BASE_URL + "/api/files") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["filePath": serverPath]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(.failure(error)); return
        }

        let task = session.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            completion(.success(()))
        }
        task.resume()
    }

    // Create a folder on server
    func createFolder(name: String, currentPath: String = "", completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: SERVER_BASE_URL + "/api/folder") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["folderName": name, "currentPath": currentPath]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch { completion(.failure(error)); return }

        let task = session.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            completion(.success(()))
        }
        task.resume()
    }

    // Upload single file (or multiple by calling multiple times). Uses multipart/form-data.
    func upload(fileURL: URL, relativePath: String? = nil, toPath: String = "", progressHandler: ((Double) -> Void)? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: SERVER_BASE_URL + "/api/files") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"

        let boundary = "----GabrielBoundary\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // path field
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"path\"\r\n\r\n")
        body.appendString("\(toPath)\r\n")

        // file field
        let filename = fileURL.lastPathComponent
        let fieldName = "file-0"
        let mimeType = mimeTypeForPath(path: fileURL.path)

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"")
        body.appendString(fieldName)
        body.appendString("\"; filename=\"")
        body.appendString(filename)
        body.appendString("\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        do {
            let fileData = try Data(contentsOf: fileURL)
            body.append(fileData)
            body.appendString("\r\n")
        } catch {
            completion(.failure(error)); return
        }

        // optional relative path
        if let rel = relativePath {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"path-0\"\r\n\r\n")
            body.appendString("\(rel)\r\n")
        }

        body.appendString("--\(boundary)--\r\n")

        // Use uploadTask for progress
        let uploadTask = session.uploadTask(with: req, from: body) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            completion(.success(()))
        }

        // KVO for progress is possible on urlSessionTask but with URLSession directly it's simpler to observe via delegate; omitted for brevity.
        uploadTask.resume()
    }

    // Helper — rudimentary mime type detection
    private func mimeTypeForPath(path: String) -> String {
        let url = NSURL(fileURLWithPath: path)
        let pathExt = url.pathExtension ?? ""
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExt as CFString, nil)?.takeRetainedValue(),
           let mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
            return mime as String
        }
        return "application/octet-stream"
    }
}

// MARK: - Small helpers
private extension Data {
    mutating func appendString(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}

import MobileCoreServices
import UniformTypeIdentifiers
