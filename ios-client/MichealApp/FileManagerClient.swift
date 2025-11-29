import Foundation
import UIKit
import UniformTypeIdentifiers

/// Simple HTTP client for Micheal server API. Configure `SERVER_BASE_URL` to point to your running Next.js server.
final class FileManagerClient: NSObject {
    static let shared = FileManagerClient()
    
    // Update this IP address to match your development machine
    private let SERVER_BASE_URL = "http://100.72.29.66:3000/"
    
    // Public accessor for base URL
    var baseURL: String {
        return SERVER_BASE_URL
    }
    
    private var session: URLSession!
    private var uploadProgressHandlers: [Int: (Double) -> Void] = [:]
    // Thumbnail cache and prefetch controls
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let thumbnailSemaphore = DispatchSemaphore(value: 4)
    private let thumbnailQueue = DispatchQueue(label: "thumbnail.queue", attributes: .concurrent)
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        // Allow more concurrent connections to the server for faster parallel downloads (thumbnails/files)
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // List files in a directory
    func listFiles(path: String = "", completion: @escaping (Result<[FileItem], Error>) -> Void) {
        // Fire a debug ping so server logs headers for this client — useful to correlate requests
        pingDebug(test: "listFiles")

        // Build URL explicitly (scheme/host/port/path) to mimic curl formatting
        guard let baseURL = URL(string: SERVER_BASE_URL) else { return }
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        // Ensure we don't accidentally include duplicate slashes
        let basePath = baseURL.path.isEmpty ? "" : baseURL.path
        // If requesting the whiteboards folder, use the focused endpoint which
        // returns only whiteboard JSON files and skips transient zero-byte files.
        if path == "whiteboards" {
            components.path = (basePath as NSString).appendingPathComponent("api/whiteboards")
        } else {
            components.path = (basePath as NSString).appendingPathComponent("api/files")
            // Only include the `path` query parameter when a non-empty path
            // is requested. Some server implementations treat an empty
            // `path=` differently than omitting the parameter — omitting
            // it yields the expected root/cloud listing.
            if !path.isEmpty {
                components.queryItems = [URLQueryItem(name: "path", value: path)]
            }
        }
        guard let url = components.url else { return }

        var req = URLRequest(url: url)
        // Always request a fresh listing from the server — the server
        // currently sets very long cache lifetimes which can cause the
        // app to show stale results after an upload. Force reload and
        // add no-cache headers to bypass URLSession/local caches.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")
        // Make request headers similar to curl to avoid different routing by intermediaries
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        // Some intermediaries or proxies route differently based on User-Agent — mimic curl for testing
        req.setValue("curl/8.7.1", forHTTPHeaderField: "User-Agent")
        // Optionally set Host header to exactly match curl's Host (helps if a proxy cares)
        if let host = baseURL.host, let port = baseURL.port {
            req.setValue("\(host):\(port)", forHTTPHeaderField: "Host")
        } else if let host = baseURL.host {
            req.setValue(host, forHTTPHeaderField: "Host")
        }

        print("FileManagerClient.listFiles: sending request to URL=\(url.absoluteString) headers=\(req.allHTTPHeaderFields ?? [:])")

        let task = session.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data else { completion(.failure(NSError(domain: "no-data", code: -1))); return }

            // Log HTTP status and headers for debugging network issues
            if let httpResp = resp as? HTTPURLResponse {
                print("FileManagerClient.listFiles: URL=\(url.absoluteString) returned status=\(httpResp.statusCode)")
                print("FileManagerClient.listFiles: headers=\(httpResp.allHeaderFields)")
            } else {
                print("FileManagerClient.listFiles: no HTTPURLResponse for URL=\(url.absoluteString)")
            }
            if let bodyString = String(data: data, encoding: .utf8) {
                print("FileManagerClient.listFiles: raw body=\n\(bodyString)")
            } else {
                print("FileManagerClient.listFiles: unable to convert response body to utf8 string")
            }

            // Define Codable response matching server
            struct FilesResponse: Codable {
                let files: [FileItem]
                let currentPath: String?
                let count: Int?
            }

            do {
                let decoder = JSONDecoder()
                // Server `modified` may be returned as a string; FileItem expects `modified` as String
                let respObj = try decoder.decode(FilesResponse.self, from: data)

                // Return server-provided listing verbatim so the app's
                // Cloud Storage view mirrors what `curl` and the server
                // return (including the `whiteboards` directory).
                let files = respObj.files
                print("FileManagerClient.listFiles: returning \(files.count) entries (including folders)")
                completion(.success(files))
            } catch {
                // If decoding fails, log the raw response to help debugging
                if let s = String(data: data, encoding: .utf8) {
                    print("FileManagerClient.listFiles: failed to decode response from \(url). Raw response:\n\(s)")
                } else {
                    print("FileManagerClient.listFiles: failed to decode response and cannot convert data to string")
                }
                completion(.failure(NSError(domain: "invalid-response", code: -1)))
            }
        }
        task.resume()
    }

    // MARK: - Thumbnail helpers
    func thumbnailImage(forPath path: String) -> UIImage? {
        return thumbnailCache.object(forKey: path as NSString)
    }

    func prefetchThumbnail(path: String, completion: @escaping (UIImage?) -> Void) {
        if let img = thumbnailImage(forPath: path) { completion(img); return }

        thumbnailQueue.async {
            self.thumbnailSemaphore.wait()
            defer { self.thumbnailSemaphore.signal() }

            guard let base = URL(string: self.SERVER_BASE_URL) else { DispatchQueue.main.async { completion(nil) }; return }
            var components = URLComponents()
            components.scheme = base.scheme
            components.host = base.host
            components.port = base.port
            components.path = (base.path as NSString).appendingPathComponent("api/thumbnail")
            // Request a small server-resized thumbnail for faster responses
            components.queryItems = [
                URLQueryItem(name: "path", value: path),
                URLQueryItem(name: "w", value: "128"),
                URLQueryItem(name: "h", value: "128")
            ]
            guard let url = components.url else { DispatchQueue.main.async { completion(nil) }; return }

            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData

            let sem = DispatchSemaphore(value: 0)
            var resultImage: UIImage? = nil
            let task = self.session.dataTask(with: req) { data, resp, err in
                defer { sem.signal() }
                if let data = data, let img = UIImage(data: data) {
                    resultImage = img
                    self.thumbnailCache.setObject(img, forKey: path as NSString)
                }
            }
            task.resume()
            // Wait a little longer for thumbnail generation on slower servers
            _ = sem.wait(timeout: .now() + 8)
            DispatchQueue.main.async { completion(resultImage) }
        }
    }

    // Ping the server debug endpoint to get echo of headers/query for correlation
    func pingDebug(test: String = "ios") {
        guard let baseURL = URL(string: SERVER_BASE_URL) else { return }
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        let basePath = baseURL.path.isEmpty ? "" : baseURL.path
        components.path = (basePath as NSString).appendingPathComponent("api/debug")
        components.queryItems = [URLQueryItem(name: "test", value: test)]
        guard let url = components.url else { return }

        var req = URLRequest(url: url)
        req.setValue("*/*", forHTTPHeaderField: "Accept")

        let task = session.dataTask(with: req) { data, resp, err in
            if let err = err {
                print("FileManagerClient.pingDebug: error=\(err)")
                return
            }
            if let httpResp = resp as? HTTPURLResponse {
                print("FileManagerClient.pingDebug: URL=\(url.absoluteString) returned status=\(httpResp.statusCode)")
                print("FileManagerClient.pingDebug: headers=\(httpResp.allHeaderFields)")
            }
            if let data = data, let s = String(data: data, encoding: .utf8) {
                print("FileManagerClient.pingDebug: body=\n\(s)")
            }
        }
        task.resume()
    }

    // Download file to a local url and return local file URL
    func downloadFile(at serverPath: String, completion: @escaping (Result<URL, Error>) -> Void) {
        guard var components = URLComponents(string: SERVER_BASE_URL + "/api/download") else { return }
        components.queryItems = [URLQueryItem(name: "path", value: serverPath)]
        guard let url = components.url else { return }

        // Build a URLRequest so we can control cache policy and headers.
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("curl/8.7.1", forHTTPHeaderField: "User-Agent")

        // Use downloadTask but validate HTTP status code before saving the file.
        let task = session.downloadTask(with: req) { tempURL, resp, err in
            if let err = err { completion(.failure(err)); return }

            guard let httpResp = resp as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "invalid-response", code: -1))); return
            }

            // If server returned non-200, read error body (if any) and return an error.
            guard httpResp.statusCode == 200 else {
                if let tempURL = tempURL, let errData = try? Data(contentsOf: tempURL), let s = String(data: errData, encoding: .utf8) {
                    completion(.failure(NSError(domain: "server-error", code: httpResp.statusCode, userInfo: ["body": s])))
                } else {
                    completion(.failure(NSError(domain: "server-error", code: httpResp.statusCode)))
                }
                return
            }

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
        // Prioritize file downloads triggered by user actions
        task.priority = 1.0
        task.resume()
    }

    // Return a direct URL to download/stream the file from the server without
    // downloading it into the app first. Useful for AVPlayer, AsyncImage, WKWebView.
    func urlForFile(path serverPath: String) -> URL? {
        guard var components = URLComponents(string: SERVER_BASE_URL + "/api/download") else { return nil }
        components.queryItems = [URLQueryItem(name: "path", value: serverPath)]
        return components.url
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
            if let httpResp = resp as? HTTPURLResponse {
                guard (200...299).contains(httpResp.statusCode) else {
                    // If server returned error, surface body if available
                    if let data = data, let s = String(data: data, encoding: .utf8) {
                        completion(.failure(NSError(domain: "server-delete", code: httpResp.statusCode, userInfo: ["body": s])))
                    } else {
                        completion(.failure(NSError(domain: "server-delete", code: httpResp.statusCode)))
                    }
                    return
                }
            }
            completion(.success(()))
        }
        task.resume()
    }
    
    // Delete a file (wrapper for delete)
    func deleteFile(at serverPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        delete(serverPath: serverPath, completion: completion)
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

        let boundary = "----MichealBoundary\(UUID().uuidString)"
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
            if let err = err { 
                completion(.failure(err))
            } else {
                completion(.success(()))
            }
        }
        
        // Store progress handler
        if let handler = progressHandler {
            self.uploadProgressHandlers[uploadTask.taskIdentifier] = handler
        }

        uploadTask.resume()
    }

    // Helper — modern UTType-based mime type detection
    private func mimeTypeForPath(path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let pathExt = url.pathExtension
        
        if let utType = UTType(filenameExtension: pathExt),
           let mimeType = utType.preferredMIMEType {
            return mimeType
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

// MARK: - URLSessionDelegate for upload progress
extension FileManagerClient: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        if let handler = uploadProgressHandlers[task.taskIdentifier] {
            DispatchQueue.main.async {
                handler(progress)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Clean up progress handler when task completes
        uploadProgressHandlers.removeValue(forKey: task.taskIdentifier)
    }
}
