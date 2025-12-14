import Foundation
import UIKit
import UniformTypeIdentifiers
import AVFoundation

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
    
    // MARK: - Caching and Optimization
    // File listing cache with TTL (20 seconds)
    private struct CachedListing {
        let files: [FileItem]
        let timestamp: Date
        let etag: String?
    }
    private var fileListingCache: [String: CachedListing] = [:]
    private let listingCacheTTL: TimeInterval = 20
    private let cacheQueue = DispatchQueue(label: "cache.queue", attributes: .concurrent)
    
    // Request deduplication - prevent multiple simultaneous requests
    private var pendingListRequests: [String: [(Result<[FileItem], Error>) -> Void]] = [:]
    private let requestQueue = DispatchQueue(label: "request.queue")
    
    // ETag cache for conditional requests
    private var etagCache: [String: String] = [:]
    
    // Thumbnail cache and prefetch controls - OPTIMIZED
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private lazy var thumbnailSemaphore: DispatchSemaphore = {
        let isIpad = UIDevice.current.userInterfaceIdiom == .pad
        return DispatchSemaphore(value: isIpad ? 16 : 8)  // iPad: 16 concurrent, iPhone: 8
    }()
    private let thumbnailQueue = DispatchQueue(label: "thumbnail.queue", attributes: .concurrent)
    private var pendingThumbnails: [String: [(UIImage?) -> Void]] = [:]
    private let thumbnailLock = NSLock()
    
    private override init() {
        super.init()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        config.httpMaximumConnectionsPerHost = 16
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(memoryCapacity: 50_000_000, diskCapacity: 200_000_000)
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        // Configure thumbnail cache limits - increased for iPad with more screen space
        let cacheIsIpad = UIDevice.current.userInterfaceIdiom == .pad
        thumbnailCache.countLimit = cacheIsIpad ? 1000 : 500  // iPad: 1000, iPhone: 500
        thumbnailCache.totalCostLimit = cacheIsIpad ? 300_000_000 : 100_000_000  // iPad: 300MB, iPhone: 100MB
    }
    
    // List files - OPTIMIZED with caching
    func listFiles(path: String = "", forceRefresh: Bool = false, completion: @escaping (Result<[FileItem], Error>) -> Void) {
        let cacheKey = path
        
        // Check cache first
        if !forceRefresh {
            cacheQueue.sync {
                if let cached = fileListingCache[cacheKey] {
                    let age = Date().timeIntervalSince(cached.timestamp)
                    if age < listingCacheTTL {
                        DispatchQueue.main.async {
                            completion(.success(cached.files))
                        }
                        return
                    }
                }
            }
        }
        
        // Check if request in flight
        requestQueue.sync {
            if pendingListRequests[cacheKey] != nil {
                pendingListRequests[cacheKey]?.append(completion)
                return
            }
            pendingListRequests[cacheKey] = [completion]
        }

        // Build URL
        guard let baseURL = URL(string: SERVER_BASE_URL) else {
            notifyListRequestCompletion(for: cacheKey, result: .failure(NSError(domain: "invalid-url", code: -1)))
            return
        }
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        let basePath = baseURL.path.isEmpty ? "" : baseURL.path
        
        if path == "whiteboards" {
            components.path = (basePath as NSString).appendingPathComponent("api/whiteboards")
        } else {
            components.path = (basePath as NSString).appendingPathComponent("api/files")
            if !path.isEmpty {
                components.queryItems = [URLQueryItem(name: "path", value: path)]
            }
        }
        guard let url = components.url else {
            notifyListRequestCompletion(for: cacheKey, result: .failure(NSError(domain: "invalid-url", code: -1)))
            return
        }

        var req = URLRequest(url: url)
        req.cachePolicy = .returnCacheDataElseLoad
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        
        if let etag = etagCache[cacheKey] {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let task = session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self = self else { return }
            
            if let err = err {
                self.notifyListRequestCompletion(for: cacheKey, result: .failure(err))
                return
            }
            
            // Handle 304
            if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 304 {
                self.cacheQueue.sync {
                    if let cached = self.fileListingCache[cacheKey] {
                        self.notifyListRequestCompletion(for: cacheKey, result: .success(cached.files))
                        return
                    }
                }
            }
            
            guard let data = data else {
                self.notifyListRequestCompletion(for: cacheKey, result: .failure(NSError(domain: "no-data", code: -1)))
                return
            }

            struct FilesResponse: Codable {
                let files: [FileItem]
                let currentPath: String?
                let count: Int?
            }

            do {
                let decoder = JSONDecoder()
                let respObj = try decoder.decode(FilesResponse.self, from: data)
                let files = respObj.files
                
                // Store ETag
                if let httpResp = resp as? HTTPURLResponse,
                   let etag = httpResp.allHeaderFields["ETag"] as? String {
                    self.etagCache[cacheKey] = etag
                }
                
                // Update cache
                self.cacheQueue.async(flags: .barrier) {
                    self.fileListingCache[cacheKey] = CachedListing(
                        files: files,
                        timestamp: Date(),
                        etag: self.etagCache[cacheKey]
                    )
                }
                
                self.notifyListRequestCompletion(for: cacheKey, result: .success(files))
            } catch {
                self.notifyListRequestCompletion(for: cacheKey, result: .failure(NSError(domain: "invalid-response", code: -1)))
            }
        }
        task.priority = URLSessionTask.highPriority
        task.resume()
    }
    
    // Helper to notify all waiting callbacks
    private func notifyListRequestCompletion(for key: String, result: Result<[FileItem], Error>) {
        requestQueue.sync {
            let callbacks = pendingListRequests[key] ?? []
            pendingListRequests.removeValue(forKey: key)
            
            DispatchQueue.main.async {
                callbacks.forEach { $0(result) }
            }
        }
    }
    
    // Invalidate cache
    func invalidateCache(for path: String = "") {
        cacheQueue.async(flags: .barrier) {
            self.fileListingCache.removeValue(forKey: path)
            if !path.isEmpty, let parentPath = (path as NSString).deletingLastPathComponent as String? {
                self.fileListingCache.removeValue(forKey: parentPath)
            }
        }
    }

    // MARK: - Thumbnail helpers
    func thumbnailImage(forPath path: String) -> UIImage? {
        return thumbnailCache.object(forKey: path as NSString)
    }

    func prefetchThumbnail(path: String, completion: @escaping (UIImage?) -> Void) {
        if let img = thumbnailImage(forPath: path) {
            completion(img)
            return
        }
        
        thumbnailLock.lock()
        if pendingThumbnails[path] != nil {
            pendingThumbnails[path]?.append(completion)
            thumbnailLock.unlock()
            return
        }
        pendingThumbnails[path] = [completion]
        thumbnailLock.unlock()

        thumbnailQueue.async {
            self.thumbnailSemaphore.wait()
            defer { self.thumbnailSemaphore.signal() }

            guard let base = URL(string: self.SERVER_BASE_URL) else {
                self.notifyThumbnailCallbacks(for: path, image: nil)
                return
            }
            var components = URLComponents()
            components.scheme = base.scheme
            components.host = base.host
            components.port = base.port
            components.path = (base.path as NSString).appendingPathComponent("api/thumbnail")
            components.queryItems = [
                URLQueryItem(name: "path", value: path),
                URLQueryItem(name: "w", value: "160"),
                URLQueryItem(name: "h", value: "160")
            ]
            guard let url = components.url else {
                self.notifyThumbnailCallbacks(for: path, image: nil)
                return
            }

            var req = URLRequest(url: url)
            req.cachePolicy = .returnCacheDataElseLoad
            req.timeoutInterval = 5

            let sem = DispatchSemaphore(value: 0)
            var resultImage: UIImage? = nil
            let task = self.session.dataTask(with: req) { data, resp, err in
                defer { sem.signal() }
                if let data = data, let img = UIImage(data: data) {
                    resultImage = img
                    let cost = data.count
                    self.thumbnailCache.setObject(img, forKey: path as NSString, cost: cost)
                }
            }
            task.priority = URLSessionTask.lowPriority
            task.resume()
            _ = sem.wait(timeout: .now() + 5)
            
            self.notifyThumbnailCallbacks(for: path, image: resultImage)
        }
    }
    
    private func notifyThumbnailCallbacks(for path: String, image: UIImage?) {
        thumbnailLock.lock()
        let callbacks = pendingThumbnails[path] ?? []
        pendingThumbnails.removeValue(forKey: path)
        thumbnailLock.unlock()
        
        DispatchQueue.main.async {
            callbacks.forEach { $0(image) }
        }
    }

    // Download file - OPTIMIZED
    func downloadFile(at serverPath: String, completion: @escaping (Result<URL, Error>) -> Void) {
        guard var components = URLComponents(string: SERVER_BASE_URL + "/api/download") else { return }
        components.queryItems = [URLQueryItem(name: "path", value: serverPath)]
        guard let url = components.url else { return }

        var req = URLRequest(url: url)
        req.cachePolicy = .returnCacheDataElseLoad
        req.setValue("*/*", forHTTPHeaderField: "Accept")

        let task = session.downloadTask(with: req) { [weak self] tempURL, resp, err in
            if let err = err { completion(.failure(err)); return }

            guard let httpResp = resp as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "invalid-response", code: -1)))
                return
            }

            guard httpResp.statusCode == 200 else {
                if let tempURL = tempURL, let errData = try? Data(contentsOf: tempURL), let s = String(data: errData, encoding: .utf8) {
                    completion(.failure(NSError(domain: "server-error", code: httpResp.statusCode, userInfo: ["body": s])))
                } else {
                    completion(.failure(NSError(domain: "server-error", code: httpResp.statusCode)))
                }
                return
            }

            guard let tempURL = tempURL else { completion(.failure(NSError(domain: "no-temp", code: -1))); return }

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
        // CRITICAL: Set highest priority for file downloads (user is waiting)
        task.priority = URLSessionTask.highPriority
        task.resume()
    }

    func urlForFile(path serverPath: String) -> URL? {
        guard var components = URLComponents(string: SERVER_BASE_URL + "/api/download") else { return nil }
        components.queryItems = [URLQueryItem(name: "path", value: serverPath)]
        return components.url
    }
    
    // Create optimized AVPlayer for video streaming with fast preload
    func createOptimizedVideoPlayer(path serverPath: String) -> (player: AVPlayer, resourceLoader: StreamingResourceLoaderDelegate)? {
        guard let url = urlForFile(path: serverPath) else { return nil }
        
        // Create custom URLSession for video streaming
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        let videoSession = URLSession(configuration: config)
        
        // Create AVAsset with custom resource loader
        let asset = AVURLAsset(url: url)
        let loaderDelegate = StreamingResourceLoaderDelegate(session: videoSession)
        asset.resourceLoader.setDelegate(loaderDelegate, queue: DispatchQueue.main)
        
        // Create player item with optimizations
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
        
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        
        return (player, loaderDelegate)
    }

    // Delete file
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

        let task = session.dataTask(with: req) { [weak self] data, resp, err in
            if let err = err { completion(.failure(err)); return }
            if let httpResp = resp as? HTTPURLResponse {
                guard (200...299).contains(httpResp.statusCode) else {
                    if let data = data, let s = String(data: data, encoding: .utf8) {
                        completion(.failure(NSError(domain: "server-delete", code: httpResp.statusCode, userInfo: ["body": s])))
                    } else {
                        completion(.failure(NSError(domain: "server-delete", code: httpResp.statusCode)))
                    }
                    return
                }
            }
            
            let parentPath = (serverPath as NSString).deletingLastPathComponent
            self?.invalidateCache(for: parentPath)
            
            completion(.success(()))
        }
        task.resume()
    }
    
    func deleteFile(at serverPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        delete(serverPath: serverPath, completion: completion)
    }

    // Create folder
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

    // Upload file - OPTIMIZED
    func upload(fileURL: URL, relativePath: String? = nil, toPath: String = "", progressHandler: ((Double) -> Void)? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: SERVER_BASE_URL + "/api/files") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"

        let boundary = "----MichealBoundary\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"path\"\r\n\r\n")
        body.appendString("\(toPath)\r\n")

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

        if let rel = relativePath {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"path-0\"\r\n\r\n")
            body.appendString("\(rel)\r\n")
        }

        body.appendString("--\(boundary)--\r\n")

        let uploadTask = session.uploadTask(with: req, from: body) { [weak self] data, resp, err in
            guard let self = self else { return }
            
            if let err = err {
                completion(.failure(err))
            } else {
                self.invalidateCache(for: toPath)
                completion(.success(()))
            }
        }
        
        if let handler = progressHandler {
            self.uploadProgressHandlers[uploadTask.taskIdentifier] = handler
        }

        uploadTask.priority = URLSessionTask.highPriority
        uploadTask.resume()
    }

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

// MARK: - Helpers
private extension Data {
    mutating func appendString(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}

// MARK: - URLSessionDelegate
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
        uploadProgressHandlers.removeValue(forKey: task.taskIdentifier)
    }
}

// MARK: - Optimized AVAssetResourceLoaderDelegate for video streaming
class StreamingResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    let session: URLSession
    
    init(session: URLSession) {
        self.session = session
        super.init()
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url else { return false }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 30
        
        // Add range request if needed for seeking
        if let contentInformationRequest = loadingRequest.contentInformationRequest {
            let task = session.dataTask(with: request) { data, response, error in
                if let httpResponse = response as? HTTPURLResponse {
                    contentInformationRequest.contentType = httpResponse.mimeType
                    contentInformationRequest.contentLength = httpResponse.expectedContentLength
                    contentInformationRequest.isByteRangeAccessSupported = true
                }
                
                if let data = data {
                    loadingRequest.dataRequest?.respond(with: data)
                }
                loadingRequest.finishLoading()
            }
            task.resume()
            return true
        }
        
        if let dataRequest = loadingRequest.dataRequest {
            let task = session.dataTask(with: request) { data, response, error in
                if let data = data {
                    dataRequest.respond(with: data)
                }
                loadingRequest.finishLoading(with: error)
            }
            task.resume()
            return true
        }
        
        return false
    }
}
