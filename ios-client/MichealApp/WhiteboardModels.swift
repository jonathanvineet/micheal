//
//  WhiteboardModels.swift
//  Micheal
//
//  Created on 12/10/2025.
//

import SwiftUI
import UIKit
import CoreGraphics

// MARK: - Enhanced Drawing Models
struct DrawingPath: Codable, Identifiable, Equatable {
    var id = UUID()
    var points: [CGPoint] = []
    var color: Color = .white
    var lineWidth: CGFloat = 3.0

    enum CodingKeys: String, CodingKey { case id, points, color, lineWidth }

    init(points: [CGPoint] = [], color: Color = .white, lineWidth: CGFloat = 3.0) {
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)

        if let decodedPoints = try? container.decode([CGPoint].self, forKey: .points) {
            points = decodedPoints
        } else if let coordArrays = try? container.decode([[CGFloat]].self, forKey: .points) {
            points = coordArrays.compactMap { arr in
                guard arr.count >= 2 else { return nil }
                return CGPoint(x: arr[0], y: arr[1])
            }
        } else if let coordArraysD = try? container.decode([[Double]].self, forKey: .points) {
            points = coordArraysD.compactMap { arr in
                guard arr.count >= 2 else { return nil }
                return CGPoint(x: CGFloat(arr[0]), y: CGFloat(arr[1]))
            }
        } else {
            points = []
        }

        lineWidth = try container.decode(CGFloat.self, forKey: .lineWidth)

        if let colorComponents = try? container.decode([CGFloat].self, forKey: .color) {
            if colorComponents.count == 4 {
                color = Color(.sRGB, red: colorComponents[0], green: colorComponents[1], blue: colorComponents[2], opacity: colorComponents[3])
            } else {
                color = .white
            }
        } else if let hexString = try? container.decode(String.self, forKey: .color) {
            color = Color(hex: hexString)
        } else {
            color = .white
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(points, forKey: .points)
        try container.encode(lineWidth, forKey: .lineWidth)

        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        try container.encode([r, g, b, a], forKey: .color)
    }
}

struct PlacedImage: Codable, Identifiable, Equatable {
    var id = UUID()
    var imageData: Data
    var position: CGPoint
    var scale: CGFloat = 1.0
    var rotation: Double = 0.0

    static func == (lhs: PlacedImage, rhs: PlacedImage) -> Bool {
        lhs.id == rhs.id
    }
}

struct DrawingDocument: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var paths: [DrawingPath] = []
    var images: [PlacedImage] = []
    var modifiedAt: Date = Date()
    var lastViewTransform: ViewTransform = ViewTransform()

    struct ViewTransform: Codable, Equatable {
        var scale: CGFloat = 1.0
        var offset: CGSize = .zero
    }

    enum CodingKeys: String, CodingKey {
        case id, name, paths, images, modifiedAt, lastViewTransform
    }

    // Convenience initializer matching older code usage: `DrawingDocument(name:)`
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.paths = []
        self.images = []
        self.modifiedAt = Date()
        self.lastViewTransform = ViewTransform()
    }

    // Backwards-compatible decoder: accept documents saved with older shape
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Guard: ensure the JSON contains at least one expected whiteboard key.
        // Some server error responses (e.g. {"error":"File not found"}) were
        // previously decoding as empty documents and producing many "Untitled"
        // entries. Reject such payloads by failing decode when no known keys
        // are present.
        let hasAnyKey = container.contains(.id) || container.contains(.name) || container.contains(.paths) || container.contains(.images) || container.contains(.modifiedAt) || container.contains(.lastViewTransform)
        if !hasAnyKey {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "JSON does not contain DrawingDocument keys")
            throw DecodingError.dataCorrupted(context)
        }

        // id and name are expected
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? container.decode(String.self, forKey: .name)) ?? "Untitled"

        // paths may be missing in very old documents
        paths = (try? container.decode([DrawingPath].self, forKey: .paths)) ?? []

        // images optional (new in enhanced model)
        images = (try? container.decode([PlacedImage].self, forKey: .images)) ?? []

        // modifiedAt: support ISO8601 and missing value
        if let date = try? container.decode(Date.self, forKey: .modifiedAt) {
            modifiedAt = date
        } else {
            modifiedAt = Date()
        }

        // lastViewTransform optional
        lastViewTransform = (try? container.decode(ViewTransform.self, forKey: .lastViewTransform)) ?? ViewTransform()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(paths, forKey: .paths)
        try container.encode(images, forKey: .images)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(lastViewTransform, forKey: .lastViewTransform)
    }
}

// MARK: - Drawing Store
@MainActor
class DrawingStore: ObservableObject {
    @Published var documents: [DrawingDocument] = []
    private var documentsURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    // Server folder where whiteboards are stored
    private let serverFolder = "whiteboards"
    // syncIndex maps document id -> last synced modifiedAt (from server or after successful upload)
    private var syncIndex: [UUID: Date] = [:]
    private var syncIndexURL: URL { documentsURL.appendingPathComponent("syncIndex.json") }

    init() {
        loadDocuments()
        loadSyncIndex()

        // Start background sync from server (call main-actor-isolated method from async context)
        Task { await self.syncFromServer() }

        // Sync on foreground
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

        // Periodic background sync every 60 seconds
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.syncFromServer() }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    func loadDocuments() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) else { return }
        print("DrawingStore: scanning documents directory: \(documentsURL.path)")
        // Debug: print a compact listing of files in Documents for troubleshooting repeated Untitled docs
        do {
            let docFiles = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: [.fileSizeKey], options: [])
            print("DrawingStore: Documents listing (count=\(docFiles.count)):")
            for f in docFiles {
                let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                print("  - \(f.lastPathComponent) (size=\(size))")
            }
        } catch {
            print("DrawingStore: failed to list Documents directory for debug: \(error)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.documents = urls.filter { $0.pathExtension == "json" }.compactMap { url in
            print("DrawingStore: found candidate file: \(url.lastPathComponent)")
            guard let data = try? Data(contentsOf: url) else { return nil }
            // Try iso8601 then default
            if let doc = try? decoder.decode(DrawingDocument.self, from: data) {
                // If the document has the default Untitled name, print raw JSON to help debugging
                if doc.name == "Untitled" {
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("DrawingStore: DEBUG - Untitled document raw JSON (\(url.lastPathComponent)):\n\(jsonString)")
                    }
                }
                return doc
            }
            if let doc = try? JSONDecoder().decode(DrawingDocument.self, from: data) {
                if doc.name == "Untitled" {
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("DrawingStore: DEBUG - Untitled document raw JSON (\(url.lastPathComponent)) [fallback decoder]:\n\(jsonString)")
                    }
                }
                return doc
            }
            return nil
        }.sorted(by: { $0.modifiedAt > $1.modifiedAt })
        print("DrawingStore: loaded \(self.documents.count) documents from disk")
    }
    
    private func loadSyncIndex() {
        guard FileManager.default.fileExists(atPath: syncIndexURL.path) else { return }
        do {
            let data = try Data(contentsOf: syncIndexURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let raw = try decoder.decode([String: Date].self, from: data)
            var idx: [UUID: Date] = [:]
            for (k, v) in raw {
                if let uuid = UUID(uuidString: k) { idx[uuid] = v }
            }
            self.syncIndex = idx
            print("DrawingStore: loaded syncIndex with \(self.syncIndex.count) entries")
        } catch {
            print("DrawingStore: failed to load syncIndex: \(error)")
        }
    }

    private func saveSyncIndex() {
        do {
            var raw: [String: Date] = [:]
            for (k, v) in syncIndex { raw[k.uuidString] = v }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(raw)
            try data.write(to: syncIndexURL)
            print("DrawingStore: saved syncIndex with \(raw.count) entries")
        } catch {
            print("DrawingStore: failed to save syncIndex: \(error)")
        }
    }
    
    func save(document: DrawingDocument, upload: Bool = true, updateModifiedAt: Bool = true) {
        var docToSave = document
        if updateModifiedAt {
            docToSave.modifiedAt = Date()
        }
        let url = documentsURL.appendingPathComponent("\(docToSave.id).json")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(docToSave)
            try data.write(to: url)
            print("DrawingStore: saved document to \(url.path)")
            DispatchQueue.main.async {
                if let index = self.documents.firstIndex(where: { $0.id == docToSave.id }) { self.documents[index] = docToSave } else { self.documents.insert(docToSave, at: 0) }
                self.documents.sort(by: { $0.modifiedAt > $1.modifiedAt })
            }

            // Upload to server folder (best-effort)
            if upload {
                FileManagerClient.shared.upload(fileURL: url, toPath: serverFolder, progressHandler: nil) { result in
                    switch result {
                    case .success():
                        print("DrawingStore: uploaded whiteboard \(docToSave.id) to server (path: \(self.serverFolder))")
                        // record that we successfully synced this modifiedAt
                        DispatchQueue.main.async {
                            self.syncIndex[docToSave.id] = docToSave.modifiedAt
                            self.saveSyncIndex()
                        }
                    case .failure(let err):
                        print("DrawingStore: failed to upload whiteboard to server: \(err)")
                    }
                }
            }
        } catch { print("Failed to save document: \(error)") }
    }
    
    func createDocument(name: String) -> DrawingDocument { let newDoc = DrawingDocument(name: name); save(document: newDoc); return newDoc }
    
    func delete(document: DrawingDocument) {
        let url = documentsURL.appendingPathComponent("\(document.id).json")
        try? FileManager.default.removeItem(at: url)
        documents.removeAll { $0.id == document.id }

        // Create and upload a small tombstone marker to prevent other devices
        // from re-uploading this document if they haven't seen the deletion yet.
        let tombstone: [String: Any] = [
            "id": document.id.uuidString,
            "deletedAt": ISO8601DateFormatter().string(from: Date())
        ]
        let tombName = "\(document.id).deleted.json"
        let tombURL = documentsURL.appendingPathComponent(tombName)
        do {
            let data = try JSONSerialization.data(withJSONObject: tombstone, options: [])
            try data.write(to: tombURL)

            FileManagerClient.shared.upload(fileURL: tombURL, toPath: serverFolder, progressHandler: nil) { result in
                switch result {
                case .success():
                    print("DrawingStore: uploaded tombstone for deleted doc \(document.id)")
                    // Attempt to delete the actual json on server as well
                    let serverPath = "\(self.serverFolder)/\(document.id).json"
                    FileManagerClient.shared.deleteFile(at: serverPath) { result in
                        switch result {
                        case .success():
                            print("Deleted whiteboard on server: \(serverPath)")
                            DispatchQueue.main.async {
                                if self.syncIndex.removeValue(forKey: document.id) != nil { self.saveSyncIndex() }
                            }
                        case .failure(let err):
                            print("Failed to delete whiteboard on server: \(err)")
                        }
                    }
                case .failure(let err):
                    print("Failed to upload tombstone for deleted doc: \(err)")
                }
                // Remove local tombstone file
                try? FileManager.default.removeItem(at: tombURL)
            }
        } catch {
            print("Failed to create tombstone file: \(error)")
            // fallback: still attempt server delete
            let serverPath = "\(serverFolder)/\(document.id).json"
            FileManagerClient.shared.deleteFile(at: serverPath) { result in
                switch result {
                case .success():
                    print("Deleted whiteboard on server: \(serverPath)")
                    DispatchQueue.main.async {
                        if self.syncIndex.removeValue(forKey: document.id) != nil { self.saveSyncIndex() }
                    }
                case .failure(let err):
                    print("Failed to delete whiteboard on server: \(err)")
                }
            }
        }
    }

    private func deleteLocally(document: DrawingDocument) {
        let url = documentsURL.appendingPathComponent("\(document.id).json")
        try? FileManager.default.removeItem(at: url)
        documents.removeAll { $0.id == document.id }
        // Remove any syncIndex entry for this doc
        if syncIndex.removeValue(forKey: document.id) != nil {
            saveSyncIndex()
        }
    }

    // MARK: - Sync helpers
    // Make syncFromServer public so views can trigger a manual sync (e.g., Sync button)
    func syncFromServer() async {
        // List JSON files in serverFolder and download/merge
        FileManagerClient.shared.listFiles(path: serverFolder) { result in
            switch result {
            case .success(let items):
                print("DrawingStore: syncFromServer - found \(items.count) items on server at path: \(self.serverFolder)")
                
                // For robust two-way sync: do NOT automatically delete local documents
                // just because they're missing on the server. Instead, upload any
                // local-only documents so the server receives the full state (name,
                // images, paths, lastViewTransform, modifiedAt). This preserves
                // local work and keeps server and device in sync.
                let remoteFileNames = Set(items.map { $0.name })
                DispatchQueue.main.async {
                    let localDocumentsToUpload = self.documents.filter { doc in
                        let fileName = "\(doc.id).json"
                        return !remoteFileNames.contains(fileName)
                    }

                    for docToUpload in localDocumentsToUpload {
                        let localURL = self.documentsURL.appendingPathComponent("\(docToUpload.id).json")
                        // If we previously synced this doc (it exists in syncIndex) and the
                        // synced timestamp matches the current modifiedAt, that means the
                        // server previously had it and now it's missing -> treat as remote deletion
                        if let lastSynced = self.syncIndex[docToUpload.id], lastSynced == docToUpload.modifiedAt {
                            print("DrawingStore: remote deleted document previously synced - removing local: \(docToUpload.id).json")
                            self.deleteLocally(document: docToUpload)
                            // also clear any syncIndex entry
                            self.syncIndex.removeValue(forKey: docToUpload.id)
                            self.saveSyncIndex()
                            continue
                        }

                        // Otherwise, this is either a local-only doc (never synced) or
                        // it has local changes since last sync -> upload it to server.
                        print("DrawingStore: uploading local-only or changed document to server: \(localURL.lastPathComponent)")
                        FileManagerClient.shared.upload(fileURL: localURL, toPath: self.serverFolder, progressHandler: nil) { result in
                            switch result {
                            case .success():
                                print("DrawingStore: uploaded local-only whiteboard \(docToUpload.id) to server")
                                DispatchQueue.main.async {
                                    self.syncIndex[docToUpload.id] = docToUpload.modifiedAt
                                    self.saveSyncIndex()
                                }
                            case .failure(let err):
                                print("DrawingStore: failed to upload local-only whiteboard to server: \(err)")
                            }
                        }
                    }
                }

                for item in items where item.name.lowercased().hasSuffix(".json") {
                    print("DrawingStore: remote item: name=\(item.name) path=\(item.path) isDir=\(item.isDirectory)")
                    FileManagerClient.shared.downloadFile(at: item.path) { dlResult in
                        switch dlResult {
                        case .success(let localURL):
                            print("DrawingStore: downloaded remote whiteboard to local temp: \(localURL.path)")
                            do {
                                let data = try Data(contentsOf: localURL)
                                
                                let processDocument: (DrawingDocument) -> Void = { rdoc in
                                    DispatchQueue.main.async {
                                        print("DrawingStore: processing remote doc id=\(rdoc.id) name=\(rdoc.name)")
                                        if let idx = self.documents.firstIndex(where: { $0.id == rdoc.id }) {
                                            if rdoc.modifiedAt > self.documents[idx].modifiedAt {
                                                print("DrawingStore: remote is newer for id=\(rdoc.id) - replacing local")
                                                self.documents[idx] = rdoc
                                                self.save(document: rdoc, upload: false, updateModifiedAt: false)
                                                // record that we've synced this remote state
                                                self.syncIndex[rdoc.id] = rdoc.modifiedAt
                                                self.saveSyncIndex()
                                            } else if rdoc.modifiedAt < self.documents[idx].modifiedAt {
                                                print("DrawingStore: local is newer for id=\(rdoc.id) - uploading local copy")
                                                let localURL = self.documentsURL.appendingPathComponent("\(self.documents[idx].id).json")
                                                FileManagerClient.shared.upload(fileURL: localURL, toPath: self.serverFolder, progressHandler: nil) { result in
                                                    if case .success = result {
                                                        DispatchQueue.main.async {
                                                            self.syncIndex[self.documents[idx].id] = self.documents[idx].modifiedAt
                                                            self.saveSyncIndex()
                                                        }
                                                    }
                                                }
                                            } else {
                                                print("DrawingStore: remote and local have same modifiedAt for id=\(rdoc.id)")
                                                // ensure sync index recorded
                                                self.syncIndex[rdoc.id] = rdoc.modifiedAt
                                                self.saveSyncIndex()
                                            }
                                        } else {
                                            print("DrawingStore: inserting new remote doc id=\(rdoc.id) name=\(rdoc.name)")
                                            self.documents.insert(rdoc, at: 0)
                                            self.save(document: rdoc, upload: false, updateModifiedAt: false)
                                            self.syncIndex[rdoc.id] = rdoc.modifiedAt
                                            self.saveSyncIndex()
                                        }
                                    }
                                }
                                
                                let decoderISO = JSONDecoder(); decoderISO.dateDecodingStrategy = .iso8601
                                do {
                                    let remoteDoc = try decoderISO.decode(DrawingDocument.self, from: data)
                                    processDocument(remoteDoc)
                                } catch let error as DecodingError {
                                    print("!!!!!!!!!! DECODING ERROR (ISO8601) !!!!!!!!!!!")
                                    self.logDecodingError(error)
                                    
                                    // Try fallback decoder
                                    do {
                                        let fallbackDecoder = JSONDecoder()
                                        let remoteDoc = try fallbackDecoder.decode(DrawingDocument.self, from: data)
                                        processDocument(remoteDoc)
                                    } catch let fallbackError as DecodingError {
                                        print("!!!!!!!!!! DECODING ERROR (FALLBACK) !!!!!!!!!!!")
                                        self.logDecodingError(fallbackError)
                                        if let jsonString = String(data: data, encoding: .utf8) {
                                            print("----- RAW JSON -----")
                                            print(jsonString)
                                            print("--------------------")
                                        }
                                    } catch {
                                        print("An unexpected error occurred during fallback decoding: \(error)")
                                    }
                                } catch {
                                    print("An unexpected error occurred during ISO8601 decoding: \(error)")
                                }
                            } catch {
                                print("Failed to read data from downloaded file: \(error)")
                            }
                        case .failure(let err):
                            print("Failed to download remote whiteboard: \(err)")
                        }
                    }
                }
                // Process tombstone (.deleted.json) files: remove local copies and clear syncIndex
                for item in items where item.name.lowercased().hasSuffix(".deleted.json") {
                    print("DrawingStore: found tombstone: \(item.name)")
                    FileManagerClient.shared.downloadFile(at: item.path) { dlResult in
                        switch dlResult {
                        case .success(let localURL):
                            do {
                                let data = try Data(contentsOf: localURL)
                                if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let idStr = obj["id"] as? String, let uuid = UUID(uuidString: idStr) {
                                    DispatchQueue.main.async {
                                        if let idx = self.documents.firstIndex(where: { $0.id == uuid }) {
                                            print("DrawingStore: tombstone indicates deletion of local doc \(uuid) - removing locally")
                                            self.deleteLocally(document: self.documents[idx])
                                        } else {
                                            print("DrawingStore: tombstone for \(uuid) - no local doc to remove")
                                        }
                                        // remove sync index if present
                                        if self.syncIndex.removeValue(forKey: uuid) != nil { self.saveSyncIndex() }
                                    }
                                }
                                // attempt to remove the tombstone file from server to avoid reprocessing
                                FileManagerClient.shared.deleteFile(at: item.path) { _ in }
                                try? FileManager.default.removeItem(at: localURL)
                            } catch {
                                print("Failed to process tombstone file: \(error)")
                            }
                        case .failure(let err):
                            print("Failed to download tombstone: \(err)")
                        }
                    }
                }
            case .failure(let err):
                print("Failed to list remote whiteboards: \(err)")
            }
        }
    }

    @objc private func appWillEnterForeground() {
        Task { await self.syncFromServer() }
    }

    private func logDecodingError(_ error: DecodingError) {
        switch error {
        case .typeMismatch(let type, let context):
            print("Type mismatch for type \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            print("Debug description: \(context.debugDescription)")
        case .valueNotFound(let type, let context):
            print("Value not found for type \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            print("Debug description: \(context.debugDescription)")
        case .keyNotFound(let key, let context):
            print("Key not found: \(key.stringValue) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            print("Debug description: \(context.debugDescription)")
        case .dataCorrupted(let context):
            print("Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            print("Debug description: \(context.debugDescription)")
        @unknown default:
            print("Unknown decoding error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Extension Helpers
extension Collection where Element == CGPoint {
    func boundingBox() -> CGRect? {
        guard let firstPoint = self.first else { return nil }
        var minX = firstPoint.x, minY = firstPoint.y, maxX = firstPoint.x, maxY = firstPoint.y
        self.forEach { point in minX = Swift.min(minX, point.x); minY = Swift.min(minY, point.y); maxX = Swift.max(maxX, point.x); maxY = Swift.max(maxY, point.y) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension CGPoint {
    func transformed(by transform: CGAffineTransform) -> CGPoint { return self.applying(transform) }
}
