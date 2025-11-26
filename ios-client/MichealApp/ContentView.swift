import SwiftUI
import UIKit
import QuickLook
import CoreGraphics
import AVKit
import WebKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// Helper to present QLPreviewController programmatically and keep its data source alive
final class QuickLookPresenter: NSObject {
    static let shared = QuickLookPresenter()
    private var dataSource: QuickLookDataSource?
    private var isPresentingQL: Bool = false
    private var pendingURL: URL? = nil

    func present(url: URL) {
        DispatchQueue.main.async {
            // Serialize presentations: if a QuickLook is active, queue this URL.
            if self.isPresentingQL {
                self.pendingURL = url
                return
            }

            guard let top = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?.rootViewController else {
                return
            }

            let presentQL: () -> Void = {
                let ql = QLPreviewController()
                let ds = QuickLookDataSource(url: url)
                self.dataSource = ds
                ql.dataSource = ds
                ql.delegate = ds
                self.isPresentingQL = true
                top.present(ql, animated: true, completion: nil)
            }

            // If a presentation is already in progress, dismiss it non-animated first,
            // then present QuickLook. This avoids the runtime warning where a new
            // presentation is attempted while another is being presented.
            if let presented = top.presentedViewController {
                presented.dismiss(animated: false) {
                    // Small async hop to ensure UIKit updates its presentation state
                    DispatchQueue.main.async {
                        presentQL()
                    }
                }
            } else {
                presentQL()
            }
        }
    }

    func clear() {
        // Called when a QL preview is dismissed. Clear data source and, if a pending
        // URL exists, present it next.
        dataSource = nil
        DispatchQueue.main.async {
            self.isPresentingQL = false
            if let next = self.pendingURL {
                self.pendingURL = nil
                self.present(url: next)
            }
        }
    }
}

final class QuickLookDataSource: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    private let url: URL
    init(url: URL) { self.url = url }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    func previewControllerDidDismiss(_ controller: QLPreviewController) { QuickLookPresenter.shared.clear() }
}

// MARK: - Remote viewers
@available(iOS 15.0, *)
struct RemoteImageViewer: View {
    let url: URL
    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .success(let img):
                    img.resizable().scaledToFit().frame(width: geo.size.width, height: geo.size.height)
                case .failure:
                    Image(systemName: "photo").resizable().scaledToFit().padding()
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}

@available(iOS 15.0, *)
struct RemoteWebViewer: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView()
        // Avoid directly toggling `isZoomEnabled` (not available on all SDK overlays).
        // WKWebView's scrollView supports zooming behavior for some content by default.
        w.allowsBackForwardNavigationGestures = false
        w.load(URLRequest(url: url))
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}


// QuickLook wrapper to preview many file types (PDF, audio, video, images, etc.)
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // nothing to update
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        var parent: QuickLookPreview
        init(_ parent: QuickLookPreview) { self.parent = parent }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return parent.url as NSURL
        }
    }
}

// MARK: - Widget Models
struct GridPosition: Equatable {
    var row: Int
    var col: Int
    var rowSpan: Int
    var colSpan: Int
}

enum WidgetType {
    case camera
    case weather
    case storage
    case todo
}

struct WidgetItem: Identifiable, Equatable {
    let id: String
    let type: WidgetType
    var gridPosition: GridPosition
    
    static func == (lhs: WidgetItem, rhs: WidgetItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Whiteboard / Scribble Models & Views (moved to file scope)
@available(iOS 15.0, *)
struct ScribbleCard: View {
    @Binding var showWhiteboardCollections: Bool
    var body: some View {
        Button(action: { showWhiteboardCollections = true }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SCRIBBLE").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.6)).tracking(1.5)
                    Spacer()
                    Image(systemName: "pencil.tip.crop.circle").font(.system(size: 32)).foregroundColor(.yellow.opacity(0.8))
                }
                Spacer()
                Image(systemName: "scribble.variable").font(.system(size: 40, weight: .light)).foregroundColor(.white.opacity(0.3))
                Spacer()
                Text("Infinite Board").font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.8))
                Text("Tap to draw").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [Color.yellow.opacity(0.15), Color.orange.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)).overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.1), lineWidth: 1)))              
        }.buttonStyle(PlainButtonStyle())
    }
}

struct DrawingPath: Codable, Identifiable, Equatable {
    var id = UUID()
        var points: [CGPoint] = []
    var color: Color = .white
    var lineWidth: CGFloat = 3.0
    enum CodingKeys: String, CodingKey { case id, points, color, lineWidth }
    init(points: [CGPoint] = [], color: Color = .white, lineWidth: CGFloat = 3.0) { self.points = points; self.color = color; self.lineWidth = lineWidth }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
            // Points may be encoded in different shapes: either as an array of point objects
            // or as an array of [x,y] coordinate arrays. Try both.
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
        try container.encode(id, forKey: .id); try container.encode(points, forKey: .points); try container.encode(lineWidth, forKey: .lineWidth)
        let uiColor = UIColor(color); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a); try container.encode([r, g, b, a], forKey: .color)
    }
}

struct DrawingDocument: Codable, Identifiable, Equatable {
    var id = UUID(); var name: String; var paths: [DrawingPath] = []; var modifiedAt: Date = Date()
}

@MainActor
class DrawingStore: ObservableObject {
    @Published var documents: [DrawingDocument] = []
    private var documentsURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    // Server folder where whiteboards are stored
    private let serverFolder = "whiteboards"

    init() {
        loadDocuments()

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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.documents = urls.filter { $0.pathExtension == "json" }.compactMap { url in
            print("DrawingStore: found candidate file: \(url.lastPathComponent)")
            guard let data = try? Data(contentsOf: url) else { return nil }
            // Try iso8601 then default
            if let doc = try? decoder.decode(DrawingDocument.self, from: data) {
                return doc
            }
            if let doc = try? JSONDecoder().decode(DrawingDocument.self, from: data) {
                return doc
            }
            return nil
        }.sorted(by: { $0.modifiedAt > $1.modifiedAt })
        print("DrawingStore: loaded \(self.documents.count) documents from disk")
    }
    func save(document: DrawingDocument, upload: Bool = true) {
        var docToSave = document; docToSave.modifiedAt = Date()
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

        // Attempt to delete on server as well
        let serverPath = "\(serverFolder)/\(document.id).json"
        FileManagerClient.shared.deleteFile(at: serverPath) { result in
            switch result {
            case .success(): print("Deleted whiteboard on server: \(serverPath)")
            case .failure(let err): print("Failed to delete whiteboard on server: \(err)")
            }
        }
    }

    private func deleteLocally(document: DrawingDocument) {
        let url = documentsURL.appendingPathComponent("\(document.id).json")
        try? FileManager.default.removeItem(at: url)
        documents.removeAll { $0.id == document.id }
    }

    // MARK: - Sync helpers
    // Make syncFromServer public so views can trigger a manual sync (e.g., Sync button)
    func syncFromServer() async {
        // List JSON files in serverFolder and download/merge
        FileManagerClient.shared.listFiles(path: serverFolder) { result in
            switch result {
            case .success(let items):
                print("DrawingStore: syncFromServer - found \(items.count) items on server at path: \(self.serverFolder)")
                
                // --- BEGIN DELETION LOGIC ---
                let remoteFileNames = Set(items.map { $0.name })
                DispatchQueue.main.async {
                    let localDocumentsToDelete = self.documents.filter { doc in
                        let fileName = "\(doc.id).json"
                        return !remoteFileNames.contains(fileName)
                    }
                    
                    for docToDelete in localDocumentsToDelete {
                        print("DrawingStore: deleting local document not present on server: \(docToDelete.id).json")
                        self.deleteLocally(document: docToDelete)
                    }
                }
                // --- END DELETION LOGIC ---

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
                                                self.save(document: rdoc, upload: false)
                                            } else if rdoc.modifiedAt < self.documents[idx].modifiedAt {
                                                print("DrawingStore: local is newer for id=\(rdoc.id) - uploading local copy")
                                                let localURL = self.documentsURL.appendingPathComponent("\(self.documents[idx].id).json")
                                                FileManagerClient.shared.upload(fileURL: localURL, toPath: self.serverFolder, progressHandler: nil) { _ in }
                                            } else {
                                                print("DrawingStore: remote and local have same modifiedAt for id=\(rdoc.id)")
                                            }
                                        } else {
                                            print("DrawingStore: inserting new remote doc id=\(rdoc.id) name=\(rdoc.name)")
                                            self.documents.insert(rdoc, at: 0)
                                            self.save(document: rdoc, upload: false)
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

@available(iOS 15.0, *)
struct WhiteboardListView: View {
    @StateObject private var store = DrawingStore()
    @State private var showNewDocSheet = false
    @State private var newDocName = ""
    @State private var selectedDocID: UUID?
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                if store.documents.isEmpty { emptyStateView } else { drawingsGridView }
            }
            .navigationTitle("Whiteboards")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Done") { presentationMode.wrappedValue.dismiss() } }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await store.syncFromServer()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }

                    Button { showNewDocSheet = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNewDocSheet) { createNewDocumentSheet }
            .background(
                NavigationLink(
                    destination: Group {
                        if let id = selectedDocID, let index = store.documents.firstIndex(where: { $0.id == id }) {
                            DrawingEditorView(document: $store.documents[index])
                        } else {
                            EmptyView()
                        }
                    },
                    isActive: Binding(get: { selectedDocID != nil }, set: { isActive in if !isActive { selectedDocID = nil } }),
                    label: { EmptyView() }
                )
            )
        }
        .accentColor(.yellow).environmentObject(store).onAppear {
            store.loadDocuments()
            Task {
                await store.syncFromServer()
            }
        }
    }
    private var drawingsGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                ForEach(store.documents) { doc in
                    Button(action: { selectedDocID = doc.id }) {
                        VStack(alignment: .leading, spacing: 8) {
                            DrawingPreview(document: doc)
                                .aspectRatio(4/3, contentMode: .fit)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))

                            Text(doc.name).font(.headline).foregroundColor(.primary).lineLimit(1)
                            Text(doc.modifiedAt, style: .relative).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive, action: { store.delete(document: doc) }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "scribble.variable").font(.system(size: 60)).foregroundColor(.gray)
            Text("No Whiteboards").font(.title.bold())
            Text("Tap the + button to create a new one.").font(.subheadline).foregroundColor(.gray)
        }
    }

    private var createNewDocumentSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Whiteboard Name")) {
                    TextField("My Awesome Drawing", text: $newDocName)
                }
                Button("Create") {
                    let newDoc = store.createDocument(name: newDocName.isEmpty ? "Untitled" : newDocName)
                    newDocName = ""
                    showNewDocSheet = false
                    selectedDocID = newDoc.id
                }
                .disabled(newDocName.isEmpty)
            }
            .navigationTitle("New Whiteboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNewDocSheet = false; newDocName = "" }
                }
            }
        }
    }
}

@available(iOS 15.0, *)
struct DrawingPreview: View {
    let document: DrawingDocument

    var body: some View {
        Canvas { context, size in
            let allPoints = document.paths.flatMap { $0.points }
            guard let boundingBox = allPoints.boundingBox() else { return }

            let drawingSize = boundingBox.size
            guard drawingSize.width > 0, drawingSize.height > 0 else { return }
            let scale = Swift.min(size.width / drawingSize.width, size.height / drawingSize.height)
            let offset = CGPoint(x: (size.width - drawingSize.width * scale) / 2, y: (size.height - drawingSize.height * scale) / 2)

            context.translateBy(x: offset.x, y: offset.y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -boundingBox.origin.x, y: -boundingBox.origin.y)

            for path in document.paths {
                guard !path.points.isEmpty else { continue }
                var p = Path()
                p.addLines(path.points)
                context.stroke(p, with: .color(path.color), style: StrokeStyle(lineWidth: path.lineWidth / scale, lineCap: .round, lineJoin: .round))
            }
        }
        .clipped()
    }
}

@available(iOS 15.0, *)
struct DrawingEditorView: View {
    @Binding var document: DrawingDocument
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var store: DrawingStore
    @State private var currentPath = DrawingPath()
    @State private var selectedColor: Color = .white
    @State private var selectedLineWidth: CGFloat = 3.0
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    private let availableColors: [Color] = [.white, .red, .green, .blue, .yellow, .orange, .purple]

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.1, blue: 0.12).ignoresSafeArea()
            DrawingCanvas(paths: $document.paths, currentPath: $currentPath, scale: $scale, lastScale: $lastScale, offset: $offset, lastOffset: $lastOffset)
                .ignoresSafeArea()
            VStack { editorToolbar; Spacer() }
        }
        .navigationTitle(document.name).navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { Button(action: { presentationMode.wrappedValue.dismiss() }) { HStack { Image(systemName: "chevron.left"); Text("Back") } } }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: resetView) { Image(systemName: "arrow.counterclockwise") }
                Button(action: undo) { Image(systemName: "arrow.uturn.backward") }.disabled(document.paths.isEmpty)
            }
        }
        .onDisappear { store.save(document: document) }
        .onChange(of: selectedColor) { newColor in currentPath.color = newColor }
        .onChange(of: selectedLineWidth) { newWidth in currentPath.lineWidth = newWidth }
    }
    private var editorToolbar: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(availableColors, id: \.self) { color in
                    Button(action: { selectedColor = color }) {
                        Circle().fill(color).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0))
                    }
                }
            }
            HStack {
                Image(systemName: "circle.fill").font(.system(size: 8))
                Slider(value: $selectedLineWidth, in: 1...20)
                Image(systemName: "circle.fill").font(.system(size: 20))
            }
            .foregroundColor(.white).padding(.horizontal)
        }
        .padding().background(Color.black.opacity(0.5)).cornerRadius(20).padding(.horizontal)
        .onChange(of: selectedColor) { newColor in currentPath.color = newColor }
        .onChange(of: selectedLineWidth) { newWidth in currentPath.lineWidth = newWidth }
    }
    private func undo() { if !document.paths.isEmpty { document.paths.removeLast() } }
    private func resetView() { withAnimation { scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero } }
}

@available(iOS 15.0, *)
struct DrawingCanvas: UIViewRepresentable {
    @Binding var paths: [DrawingPath]; @Binding var currentPath: DrawingPath
    @Binding var scale: CGFloat; @Binding var lastScale: CGFloat; @Binding var offset: CGSize; @Binding var lastOffset: CGSize
    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView(); view.delegate = context.coordinator; view.backgroundColor = .clear; view.isMultipleTouchEnabled = true
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:))); pinch.delegate = context.coordinator; view.addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:))); pan.minimumNumberOfTouches = 2; pan.delegate = context.coordinator; view.addGestureRecognizer(pan)
        return view
    }
    func updateUIView(_ uiView: CanvasView, context: Context) { uiView.paths = paths; uiView.currentPath = currentPath; uiView.scale = scale; uiView.offset = offset }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, CanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: DrawingCanvas
        init(_ parent: DrawingCanvas) { self.parent = parent }
        func didBeginPath(at point: CGPoint) { parent.currentPath.points = [point] }
        func didAppendToPath(at point: CGPoint) { parent.currentPath.points.append(point) }
        func didEndPath() { if !parent.currentPath.points.isEmpty { parent.paths.append(parent.currentPath); parent.currentPath = DrawingPath(color: parent.currentPath.color, lineWidth: parent.currentPath.lineWidth) } }
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began: parent.lastScale = parent.scale
            case .changed: let newScale = parent.lastScale * gesture.scale; parent.scale = Swift.max(0.2, Swift.min(newScale, 5.0))
            case .ended, .cancelled: parent.lastScale = 1.0
            default: break
            }
        }
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.numberOfTouches == 2 else { return }
            let translation = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .began: parent.lastOffset = parent.offset
            case .changed: parent.offset = CGSize(width: parent.lastOffset.width + translation.x, height: parent.lastOffset.height + translation.y)
            default: break
            }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { return true }
    }
}

protocol CanvasViewDelegate: AnyObject { func didBeginPath(at point: CGPoint); func didAppendToPath(at point: CGPoint); func didEndPath() }

class CanvasView: UIView {
    weak var delegate: CanvasViewDelegate?; var paths: [DrawingPath] = [] { didSet { setNeedsDisplay() } }; var currentPath: DrawingPath? { didSet { setNeedsDisplay() } }
    var scale: CGFloat = 1.0 { didSet { setNeedsDisplay() } }; var offset: CGSize = .zero { didSet { setNeedsDisplay() } }; private var isDrawing = false
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard event?.allTouches?.count == 1, let touch = touches.first else { isDrawing = false; return }
        isDrawing = true; let point = touch.location(in: self).transformed(by: transformToCanvas()); delegate?.didBeginPath(at: point)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawing, let touch = touches.first else { return }
        let point = touch.location(in: self).transformed(by: transformToCanvas()); delegate?.didAppendToPath(at: point)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { guard isDrawing else { return }; isDrawing = false; delegate?.didEndPath() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { guard isDrawing else { return }; isDrawing = false; delegate?.didEndPath() }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState(); context.translateBy(x: offset.width, y: offset.height); context.scaleBy(x: scale, y: scale)
        context.setLineCap(.round); context.setLineJoin(.round)
        for path in paths { draw(path: path, in: context) }
        if let currentPath = currentPath, isDrawing { draw(path: currentPath, in: context) }
        context.restoreGState()
    }
    private func draw(path: DrawingPath, in context: CGContext) {
        guard !path.points.isEmpty else { return }
        context.setLineWidth(path.lineWidth / scale); context.setStrokeColor(UIColor(path.color).cgColor)
        let cgPath = CGMutablePath(); cgPath.addLines(between: path.points); context.addPath(cgPath); context.strokePath()
    }
    private func transformToCanvas() -> CGAffineTransform {
        // In draw(_:) we do: translate(offset); scale(scale)
        // The inverse (view -> canvas) is: scale by 1/scale, then translate by -offset
        return CGAffineTransform(scaleX: 1.0 / max(scale, 0.0001), y: 1.0 / max(scale, 0.0001)).translatedBy(x: -offset.width, y: -offset.height)
    }
}

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

// MARK: - iOS Version Compatibility Helpers
extension Font.Weight {
    /// Returns .black on iOS 16+, .heavy on iOS 15
    static var compatibleBlack: Font.Weight {
        if #available(iOS 16.0, *) {
            return .black
        } else {
            return .heavy
        }
    }
}

@available(iOS 15.0, *)
struct ContentView: View {
    @State private var showDashboard = true
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Device-specific background image
                DeviceBackgroundView()
                    .ignoresSafeArea()

                // Main content -- fill the available space. We avoid adding
                // manual top/bottom safe-area padding here so the content
                // can occupy the full screen without wasted gaps.
                VStack(spacing: 0) {
                    if showDashboard {
                        DashboardView(showDashboard: $showDashboard)
                    } else {
                        FileManagerView(showDashboard: $showDashboard)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Device Background View
struct DeviceBackgroundView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var backgroundImageName: String {
        // Detect device type
        let idiom = UIDevice.current.userInterfaceIdiom
        
        switch idiom {
        case .phone:
            // iPhone uses iphone.jpg
            return "iphone"
        case .pad:
            // iPad uses background.jpg
            return "background"
        default:
            return "background"
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            if let image = UIImage(named: backgroundImageName) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()
            } else {
                // Fallback gradient if image not found
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            
            // Dark overlay for better content visibility
            Color.black.opacity(0.3)
                .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Dashboard View
@available(iOS 15.0, *)
struct DashboardView: View {
    @Binding var showDashboard: Bool
    @State private var currentTime = Date()
    @State private var serverReachable = false
    @State private var checkingConnection = true
    
    // Missing state variables
    @State private var weather = WeatherData(temp: 32, condition: "Partly Cloudy", location: "Chennai")
    @State private var storageUsed: Double = 0.0
    @State private var storageTotal: Double = 100.0
    @State private var recentFiles: [FileItem] = []
    @State private var todos: [String] = []
    @State private var newTodo: String = ""
    @State private var showTodoInput: Bool = false
    @State private var showWhiteboardCollections: Bool = false
    
    // Widget editing state
    @State private var isEditMode = false
    @State private var widgets: [WidgetItem] = [
        WidgetItem(id: "camera", type: .camera, gridPosition: GridPosition(row: 0, col: 0, rowSpan: 2, colSpan: 2)),
        WidgetItem(id: "weather", type: .weather, gridPosition: GridPosition(row: 0, col: 2, rowSpan: 1, colSpan: 1)),
        WidgetItem(id: "storage", type: .storage, gridPosition: GridPosition(row: 1, col: 2, rowSpan: 1, colSpan: 1)),
        WidgetItem(id: "todo", type: .todo, gridPosition: GridPosition(row: 2, col: 0, rowSpan: 1, colSpan: 3))
    ]
    @State private var draggedWidget: WidgetItem?
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Use shared instance instead of creating new one
    private var fileManagerClient: FileManagerClient {
        FileManagerClient.shared
    }
    
    // Timer for clock updates
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // Adaptive grid columns based on device
    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad: 3 columns in landscape
            return [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ]
        } else {
            // iPhone: 2 columns
            return [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ]
        }
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection status banner
                    if checkingConnection {
                        HStack {
                            ProgressView()
                            Text("Checking server connection...")
                                .font(.caption)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    } else if !serverReachable {
                        VStack(spacing: 8) {
                                Text("⚠️ Cannot reach server")
                                    .font(.headline)
                                Text("Make sure you're on the same WiFi network")
                                    .font(.caption)
                                Text("Server: \(fileManagerClient.baseURL)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Button("Retry Connection") {
                                    checkServerConnection()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        // Header with clock
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text("Hello, ")
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                    Text("Batman")
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [Color.yellow, Color.orange],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                Text(currentTime, style: .date)
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(currentTime, style: .time)
                                    .font(.system(size: 36, weight: Font.Weight.compatibleBlack))
                                    .foregroundColor(.white)
                                Text(currentTime.formatted(.dateTime.hour().minute()).components(separatedBy: " ").last ?? "")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                                    .textCase(.uppercase)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        

                        // Responsive layout: iPad shows three-column layout (left: Cloud+Scribble stacked,
                        // middle: camera, right: todo). iPhone stacks these vertically but keeps Cloud+Scribble
                        // side-by-side for compact rows.
                        if horizontalSizeClass == .regular {
                            HStack(alignment: .top, spacing: 16) {
                                // Left column: Cloud Storage (top) and Scribble (bottom)
                                VStack(spacing: 16) {
                                    Button(action: { showDashboard = false }) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            HStack {
                                                Text("CLOUD STORAGE")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.white.opacity(0.6))
                                                    .tracking(1.5)
                                                Spacer()
                                                Image(systemName: "internaldrive.fill")
                                                    .font(.system(size: 32))
                                                    .foregroundColor(.yellow.opacity(0.8))
                                            }
                                            Spacer()
                                            Image(systemName: "externaldrive.fill.badge.icloud")
                                                .font(.system(size: 40, weight: .light))
                                                .foregroundColor(.white.opacity(0.3))
                                            Spacer()
                                            Text("Manage Files")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white.opacity(0.8))
                                            Text("Tap to expand")
                                                .font(.system(size: 11))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(20)
                                        .background(
                                            RoundedRectangle(cornerRadius: 24)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.yellow.opacity(0.15), Color.orange.opacity(0.1)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 24)
                                                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    ScribbleCard(showWhiteboardCollections: $showWhiteboardCollections)
                                }
                                .frame(minWidth: 0, maxWidth: .infinity)

                                // Middle: Expandable camera
                                ExpandableCameraCard()
                                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 320)

                                // Right: Todo column
                                TodoCard(todos: $todos, newTodo: $newTodo, showTodoInput: $showTodoInput)
                                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 300)
                            }
                            .padding(.horizontal, 16)
                        } else {
                            // Compact: stack vertically but keep Cloud+Scribble side-by-side row
                            HStack(spacing: 16) {
                                // Cloud Storage Card
                                Button(action: { showDashboard = false }) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Text("CLOUD STORAGE")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.white.opacity(0.6))
                                                .tracking(1.5)
                                            Spacer()
                                            Image(systemName: "internaldrive.fill")
                                                .font(.system(size: 32))
                                                .foregroundColor(.yellow.opacity(0.8))
                                        }
                                        Spacer()
                                        Image(systemName: "externaldrive.fill.badge.icloud")
                                            .font(.system(size: 40, weight: .light))
                                            .foregroundColor(.white.opacity(0.3))
                                        Spacer()
                                        Text("Manage Files")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white.opacity(0.8))
                                        Text("Tap to expand")
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 24)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.yellow.opacity(0.15), Color.orange.opacity(0.1)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 24)
                                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())

                                // Scribble Card
                                ScribbleCard(showWhiteboardCollections: $showWhiteboardCollections)
                            }
                            .frame(height: 180)
                            .padding(.horizontal, 16)

                            // Expandable Camera Feed
                            ExpandableCameraCard()
                                .padding(.horizontal, 16)

                            // Things To Do Card
                            TodoCard(todos: $todos, newTodo: $newTodo, showTodoInput: $showTodoInput)
                                .frame(height: 300)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 20)
                        }
                        
                        // Cloud Storage Button
                        Button(action: { showDashboard = false }) {
                            HStack {
                                Image(systemName: "internaldrive.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.black)
                                    .frame(width: 56, height: 56)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.yellow, Color.orange],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cloud Storage")
                                        .font(.system(size: 24, weight: Font.Weight.compatibleBlack))
                                        .foregroundColor(.white)
                                    Text("Tap to expand and manage files")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                
                                Spacer()
                                
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.yellow)
                            }
                            .padding(24)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.black.opacity(0.5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 24)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                }
                .onReceive(timer) { _ in
                    currentTime = Date()
                }
                .onAppear {
                    checkServerConnection()
                    loadRecentFiles()
                }
            }
            .fullScreenCover(isPresented: $showWhiteboardCollections) {
                WhiteboardListView()
            }

            
            // Done button when in edit mode
            if isEditMode {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isEditMode = false
                            }
                        }) {
                            Text("Done")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(20)
                        }
                        .padding()
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
    }
    
    func checkServerConnection() {
        checkingConnection = true
        
        guard let url = URL(string: "\(fileManagerClient.baseURL)/api/ping") else {
            checkingConnection = false
            serverReachable = false
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = NSURLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                checkingConnection = false
                
                if let error = error {
                    print("❌ Server connection test failed: \(error.localizedDescription)")
                    serverReachable = false
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("✅ Server responded with status: \(httpResponse.statusCode)")
                    serverReachable = (httpResponse.statusCode == 200)
                } else {
                    serverReachable = false
                }
            }
        }.resume()
    }
    
    func loadRecentFiles() {
        FileManagerClient.shared.listFiles(path: "") { result in
            if case .success(let items) = result {
                DispatchQueue.main.async {
                    recentFiles = Array(items.prefix(3))
                    storageUsed = Double(items.reduce(0) { $0 + $1.size }) / 1_000_000_000
                }
            }
        }
    }
}

// MARK: - Weather Card
@available(iOS 15.0, *)
struct WeatherCard: View {
    let weather: WeatherData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WEATHER")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.5)
                
                Spacer()
                
                Image(systemName: weatherIcon)
                    .font(.system(size: 32))
                    .foregroundColor(.blue.opacity(0.8))
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(weather.temp)")
                    .font(.system(size: 56, weight: Font.Weight.compatibleBlack))
                    .foregroundColor(.white)
                Text("°C")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Text(weather.condition)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Text(weather.location)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    var weatherIcon: String {
        switch weather.condition.lowercased() {
        case "clear": return "sun.max.fill"
        case "rain": return "cloud.rain.fill"
        case "snow": return "cloud.snow.fill"
        case "cloudy": return "cloud.fill"
        case "partly cloudy": return "cloud.sun.fill"
        default: return "cloud.sun.fill"
        }
    }
}

// MARK: - Camera Feed Card
@available(iOS 15.0, *)
struct CameraFeedCard: View {
    @ObservedObject private var mjpegStream = MJPEGStreamView.shared
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text("Live Camera Feed")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                ZStack {
                    Rectangle()
                        .fill(Color.black)
                        .aspectRatio(16/9, contentMode: .fit)

                    if mjpegStream.isLoading {
                        ProgressView()
                            .tint(.yellow)
                    } else if !mjpegStream.errorMessage.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "video.slash.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.3))
                            Text(mjpegStream.errorMessage)
                                .foregroundColor(.red)
                                .font(.system(size: 12))
                        }
                    } else if let currentFrame = mjpegStream.currentFrame {
                        Image(uiImage: currentFrame)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.3))
                            Text("Connecting to camera...")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    // Live indicator
                    VStack {
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(mjpegStream.isStreaming ? Color.red : Color.gray)
                                    .frame(width: 8, height: 8)
                                    .shadow(color: mjpegStream.isStreaming ? .red : .clear, radius: 4)

                                Text(mjpegStream.isStreaming ? "LIVE" : "OFFLINE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(mjpegStream.isStreaming ? .red : .gray)
                                    .tracking(0.5)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.7))
                                    .overlay(
                                        Capsule()
                                            .stroke(mjpegStream.isStreaming ? Color.red.opacity(0.5) : Color.gray.opacity(0.5), lineWidth: 1)
                                    )
                            )

                            Spacer()
                        }
                        .padding(16)

                        Spacer()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.black.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .onAppear {
                // Start streaming once when the app/view first appears.
                if !mjpegStream.isStreaming {
                    mjpegStream.startStreaming(url: "\(FileManagerClient.shared.baseURL)/api/camera-stream")
                }
            }
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    if !mjpegStream.isStreaming {
                        mjpegStream.startStreaming(url: "\(FileManagerClient.shared.baseURL)/api/camera-stream")
                    }
                case .background, .inactive:
                    // Keep stream running across navigation; do not stop here so the connection stays alive.
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    // MARK: - Storage Card
    @available(iOS 15.0, *)
    struct StorageCard: View {
        let storageUsed: Double
        let storageTotal: Double
        let recentFiles: [FileItem]
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    
                    Text("STORAGE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(1.5)
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", storageUsed))
                        .font(.system(size: 32, weight: Font.Weight.compatibleBlack))
                        .foregroundColor(.white)
                    Text("GB")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                // Storage bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.3))
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(min(storageUsed / storageTotal, 1.0)))
                    }
                }
                .frame(height: 8)
                
                Text("\(Int(storageTotal)) GB Total")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.1), Color.green.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Todo Card
    @available(iOS 15.0, *)
    struct TodoCard: View {
        @Binding var todos: [String]
        @Binding var newTodo: String
        @Binding var showTodoInput: Bool
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("THINGS TO DO")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(1.5)
                    
                    Spacer()
                    
                    Button(action: { showTodoInput.toggle() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 40, height: 40)
                            .background(Color.yellow)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                if showTodoInput {
                    TextField("What needs to be done?", text: $newTodo, onCommit: {
                        if !newTodo.trimmingCharacters(in: .whitespaces).isEmpty {
                            todos.append(newTodo.trimmingCharacters(in: .whitespaces))
                            newTodo = ""
                            showTodoInput = false
                        }
                    })
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                }
                
                ScrollView {
                    if todos.isEmpty {
                        VStack(spacing: 12) {
                            Text("No tasks yet")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(todos.enumerated()), id: \.offset) { index, todo in
                                HStack(spacing: 12) {
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                        .frame(width: 20, height: 20)
                                    
                                    Text(todo)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Button(action: { todos.remove(at: index) }) {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black.opacity(0.2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.1), Color.yellow.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }


// MARK: - File Manager View
@available(iOS 15.0, *)
struct FileManagerView: View {
    @Binding var showDashboard: Bool
    // Simple in-memory cache keyed by path so each folder listing is cached separately
    private static var cachedFilesByPath: [String: [FileItem]] = [:]
    private static var didLoadPaths: Set<String> = []
    @State private var files: [FileItem] = []
    @State private var loading = false
    // Persist the current folder across view recreations so breadcrumbs and state remain
    // when navigating back and forth between dashboard and cloud storage.
    @AppStorage("filemanager.currentPath") private var currentPath: String = ""
    @State private var showPicker = false
    @State private var uploadProgress: Double = 0.0
    @State private var isUploading = false
    @State private var uploadingFileName = ""
    @State private var selectedItem: FileItem? = nil
    @State private var showingImageViewer = false
    @State private var previewURL: URL? = nil
    // Unified local-preview presentation state. We present a single
    // sheet for both placeholder and final QuickLook content.
    @State private var isPresentingLocalPreview = false
    @State private var isLoadingPreview = false
    // Quick lightweight placeholder shown immediately while the full
    // file downloads. We prefetch a small thumbnail and present it
    // quickly to avoid QuickLook showing "No preview available".
    @State private var previewPlaceholderImage: UIImage? = nil
    // Remote streaming/viewing
    @State private var remoteURL: URL? = nil
    @State private var showingRemoteImage = false
    @State private var showingRemoteVideo = false
    @State private var showingRemoteWeb = false
    @State private var activePlayer: AVPlayer? = nil
    @State private var isStreamingLoading = false
    @State private var playerStatusObserver: NSKeyValueObservation? = nil
    // Prevent re-entrant preview opens
    @State private var isOpeningPreview = false
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Adaptive grid columns for file grid
    private var fileGridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad: 6 columns
            return Array(repeating: GridItem(.flexible()), count: 6)
        } else {
            // iPhone: 3 columns
            return Array(repeating: GridItem(.flexible()), count: 3)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(
                                colors: [Color.yellow, Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cloud Storage")
                            .font(.system(size: 20, weight: Font.Weight.compatibleBlack))
                            .foregroundColor(.white)
                        Text("Manage your files")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Button(action: { showDashboard = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 14))
                            Text("Back")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(20)
                .background(Color.black.opacity(0.3))

                // Breadcrumbs for current folder path
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        BreadcrumbButton(title: "All files", targetPath: "", currentPath: $currentPath) {
                            loadFiles(force: true)
                        }

                        if !currentPath.isEmpty {
                            let segments = currentPath.split(separator: "/").map(String.init)
                            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                                let prefix = segments.prefix(idx + 1).joined(separator: "/")
                                BreadcrumbButton(title: seg, targetPath: prefix, currentPath: $currentPath) {
                                    loadFiles(force: true)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                
                if loading {
                    ProgressView("Loading…")
                        .padding()
                }
                
                if isUploading {
                    VStack(spacing: 8) {
                        Text("Uploading \(uploadingFileName)…")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        ProgressView(value: uploadProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                            .tint(.yellow)
                        Text("\(Int(uploadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                    )
                    .padding(.horizontal)
                }
                
                ScrollView {
                    LazyVGrid(columns: fileGridColumns, spacing: 10) {
                                ForEach(files) { item in
                                    FileGridItem(item: item) {
                                        if item.isDirectory {
                                            // Navigate into folder
                                            if currentPath.isEmpty {
                                                currentPath = item.name
                                            } else {
                                                currentPath = "\(currentPath)/\(item.name)"
                                            }
                                            loadFiles(force: true)
                                        } else {
                                            // Open any file type using QuickLook after downloading
                                            openFile(item: item)
                                        }
                                    }
                                }
                    }
                    .padding()
                }
                
                HStack {
                    Button(action: { showPicker.toggle() }) {
                        Label("Upload", systemImage: "arrow.up.doc")
                            .foregroundColor(.black)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .padding()
                    .background(Color.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    Spacer()
                    
                    Button(action: { loadFiles(force: true) }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                    if !currentPath.isEmpty {
                        Button(action: {
                            // Go up one directory
                            if let idx = currentPath.lastIndex(of: "/") {
                                currentPath = String(currentPath[..<idx])
                            } else {
                                currentPath = ""
                            }
                            loadFiles(force: true)
                        }) {
                            Label("Up", systemImage: "arrow.up")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                }
                .padding()

                // Make action bar adaptive on compact widths: stack vertically on narrow screens
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker { urls in
                    for url in urls {
                        // Optimistically insert the file into the UI immediately
                        let filename = url.lastPathComponent
                        var fileSize: Int? = nil
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attrs[.size] as? NSNumber {
                            fileSize = size.intValue
                        }
                        let serverPath = currentPath.isEmpty ? filename : "\(currentPath)/\(filename)"
                        let optimistic = FileItem(name: filename, isDirectory: false, size: fileSize, modified: nil, path: serverPath)
                        // Insert at top of lists so users see it immediately
                        DispatchQueue.main.async {
                            self.files.insert(optimistic, at: 0)
                            FileManagerView.cachedFilesByPath[self.currentPath] = self.files
                        }

                        isUploading = true
                        uploadingFileName = filename
                        uploadProgress = 0.0
                        
                        FileManagerClient.shared.upload(
                            fileURL: url,
                            relativePath: nil,
                            toPath: currentPath,
                            progressHandler: { progress in
                                uploadProgress = progress
                            },
                            completion: { result in
                                DispatchQueue.main.async {
                                    isUploading = false
                                    switch result {
                                                    case .success():
                                                        print("uploaded \(url.lastPathComponent)")
                                                        // Refresh listing to replace optimistic entry with canonical server data
                                                        loadFiles(force: true)
                                    case .failure(let err):
                                        print("upload error: \(err)")
                                        // Remove optimistic placeholder on failure
                                        DispatchQueue.main.async {
                                            self.files.removeAll { $0.path == serverPath }
                                            FileManagerView.cachedFilesByPath[self.currentPath] = self.files
                                        }
                                    }
                                }
                            }
                        )
                    }
                    showPicker = false
                }
            }
            .fullScreenCover(isPresented: $showingImageViewer) {
                if let item = selectedItem {
                    ImageViewer(item: item, isPresented: $showingImageViewer) {
                        loadFiles(force: true)
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.1).combined(with: .opacity),
                        removal: .scale(scale: 0.1).combined(with: .opacity)
                    ))
                }
            }
            .sheet(isPresented: $isPresentingLocalPreview, onDismiss: {
                previewPlaceholderImage = nil
                previewURL = nil
                isLoadingPreview = false
            }) {
                VStack {
                    if isLoadingPreview {
                        if let img = previewPlaceholderImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding()
                        } else {
                            VStack(spacing: 12) {
                                ProgressView("Preparing preview…")
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(1.2)
                                Text("Loading preview…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    } else if let url = previewURL {
                        // Use the programmatic QuickLook presenter instead of embedding
                        // a QuickLookController inside a SwiftUI sheet to avoid
                        // double-presentation conflicts on iPad. Present and then
                        // dismiss this transient sheet.
                        VStack {
                            Text("Opening preview…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .onAppear {
                                    QuickLookPresenter.shared.present(url: url)
                                    // Dismiss the SwiftUI sheet so only the programmatic
                                    // QLPreviewController is visible. Delay slightly to
                                    // avoid race with presentation.
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        isPresentingLocalPreview = false
                                    }
                                }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Preview unavailable")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                }
            }
            .sheet(isPresented: $showingRemoteImage, onDismiss: { remoteURL = nil }) {
                if let url = remoteURL {
                    RemoteImageViewer(url: url)
                } else {
                    Text("No image")
                }
            }
            .sheet(isPresented: $showingRemoteVideo, onDismiss: {
                if let p = activePlayer { p.pause() }
                activePlayer = nil
                remoteURL = nil
                playerStatusObserver?.invalidate()
                playerStatusObserver = nil
            }) {
                if let url = remoteURL {
                    ZStack {
                        VideoPlayer(player: activePlayer)
                            .edgesIgnoringSafeArea(.all)
                            .onAppear {
                                if activePlayer == nil {
                                    activePlayer = AVPlayer(url: url)
                                    // Observe the player's item status to clear loading indicator
                                    if let item = activePlayer?.currentItem {
                                        playerStatusObserver = item.observe(\.status, options: [.initial, .new]) { it, _ in
                                            DispatchQueue.main.async {
                                                if it.status == .readyToPlay {
                                                    self.isStreamingLoading = false
                                                    self.playerStatusObserver = nil
                                                }
                                            }
                                        }
                                    }
                                }
                                activePlayer?.play()
                            }
                            .onDisappear {
                                activePlayer?.pause()
                            }

                        if isStreamingLoading {
                            VStack(spacing: 12) {
                                ProgressView("Preparing playback…")
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(1.2)
                                Text("Loading…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(20)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground).opacity(0.9)))
                        }
                    }
                } else {
                    Text("No media")
                }
            }
            .sheet(isPresented: $showingRemoteWeb, onDismiss: { remoteURL = nil }) {
                if let url = remoteURL {
                    RemoteWebViewer(url: url)
                } else {
                    Text("No preview")
                }
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showingImageViewer)
            .onAppear { loadFiles() }
        }
        
        // end of FileManagerView
    }

// Move helper methods into an extension so they exist in the type context
// and can freely reference `self`/`@State` properties when used from
// nested closures.
@available(iOS 15.0, *)
extension FileManagerView {
    func loadFiles(force: Bool = false) {
        if !force, let cached = FileManagerView.cachedFilesByPath[currentPath] {
            files = cached
            return
        }

        loading = true
        FileManagerClient.shared.listFiles(path: currentPath) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let items):
                    // Filter out internal folders we don't want to expose
                    let filtered = items.filter { item in
                        if item.isDirectory {
                            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            if name == ".thumbs" || name == "whiteboards" {
                                return false
                            }
                        }
                        return true
                    }

                    self.files = filtered
                    FileManagerView.cachedFilesByPath[self.currentPath] = filtered
                    FileManagerView.didLoadPaths.insert(self.currentPath)
                case .failure(let err):
                    print("list error: \(err)")
                }

                loading = false
            }
        }
    }

    func isImageFile(_ name: String) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp"]
        return imageExtensions.contains(name.components(separatedBy: ".").last?.lowercased() ?? "")
    }

    func isVideoFile(_ name: String) -> Bool {
        let exts = ["mp4", "mov", "m4v", "webm"]
        return exts.contains(name.components(separatedBy: ".").last?.lowercased() ?? "")
    }

    func isAudioFile(_ name: String) -> Bool {
        let exts = ["mp3", "wav", "m4a", "aac"]
        return exts.contains(name.components(separatedBy: ".").last?.lowercased() ?? "")
    }

    func isPdfFile(_ name: String) -> Bool {
        return name.components(separatedBy: ".").last?.lowercased() == "pdf"
    }

    // Open a file. For common media types (images, video, audio, PDF)
    // prefer streaming directly from the server so the app doesn't
    // need to fully download the file first. For unknown types we
    // fall back to download+QuickLook.
    func openFile(item: FileItem) {
        // Robust, single-entry preview flow with validation and serialized presentation.
        guard !isOpeningPreview else { return }
        isOpeningPreview = true

        let filename = item.name
        let localDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localURL = localDocs.appendingPathComponent(filename)

        // Reset preview UI immediately and show placeholder
        DispatchQueue.main.async {
            self.previewURL = nil
            self.previewPlaceholderImage = nil
            self.isLoadingPreview = true
            self.isPresentingLocalPreview = true
        }

        // Prefetch thumbnail asynchronously (non-blocking)
        FileManagerClient.shared.prefetchThumbnail(path: item.path) { img in
            DispatchQueue.main.async {
                if let img = img { self.previewPlaceholderImage = img }
            }
        }

        func finishOpening() {
            DispatchQueue.main.async { self.isOpeningPreview = false }
        }

        func presentLocal(_ url: URL) {
            DispatchQueue.main.async {
                self.isLoadingPreview = false
                // Dismiss the placeholder sheet before presenting QL to avoid conflicts
                self.isPresentingLocalPreview = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    QuickLookPresenter.shared.present(url: url)
                    finishOpening()
                }
            }
        }

        func presentRemotePlayer(_ remote: URL) {
            DispatchQueue.main.async {
                self.isLoadingPreview = false
                // Dismiss placeholder first
                self.isPresentingLocalPreview = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    let player = AVPlayer(url: remote)
                    let pvc = AVPlayerViewController()
                    pvc.player = player
                    if let top = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .flatMap({ $0.windows })
                        .first(where: { $0.isKeyWindow })?.rootViewController {
                        top.present(pvc, animated: true) {
                            player.play()
                            finishOpening()
                        }
                    } else {
                        finishOpening()
                    }
                }
            }
        }

        // If streamable, prefer streaming
        if isVideoFile(filename) || isAudioFile(filename) {
            if let remote = FileManagerClient.shared.urlForFile(path: item.path) {
                presentRemotePlayer(remote)
                return
            }
        }

        // If local copy exists, validate it first
        if FileManager.default.fileExists(atPath: localURL.path) {
            DispatchQueue.global(qos: .userInitiated).async {
                var valid = true
                if self.isImageFile(filename) {
                    if UIImage(contentsOfFile: localURL.path) == nil { valid = false }
                }
                DispatchQueue.main.async {
                    if valid {
                        presentLocal(localURL)
                    } else {
                        // Remove corrupt file and fallthrough to download
                        try? FileManager.default.removeItem(at: localURL)
                        // continue to download below
                        DispatchQueue.main.async { self.isLoadingPreview = true; self.isPresentingLocalPreview = true }
                    }
                }
            }
            // If file existed and was valid, presentLocal will return; otherwise continue to download
            if FileManager.default.fileExists(atPath: localURL.path) { return }
        }

        // Download a fresh copy and validate
        FileManagerClient.shared.downloadFile(at: item.path) { result in
            switch result {
            case .success(let downloadedURL):
                DispatchQueue.global(qos: .userInitiated).async {
                    var valid = true
                    if self.isImageFile(filename) {
                        if UIImage(contentsOfFile: downloadedURL.path) == nil { valid = false }
                    }
                    DispatchQueue.main.async {
                        if valid {
                            presentLocal(downloadedURL)
                        } else {
                            // Corrupt download: remove, show unavailable and allow retry
                            try? FileManager.default.removeItem(at: downloadedURL)
                            self.isLoadingPreview = false
                            self.isPresentingLocalPreview = true
                            finishOpening()
                        }
                    }
                }
            case .failure(let err):
                DispatchQueue.main.async {
                    self.isLoadingPreview = false
                    self.previewURL = nil
                    self.isPresentingLocalPreview = true
                    finishOpening()
                }
                print("Failed to download file for preview: \(err)")
            }
        }
    }
}

// MARK: - Expandable Camera Card (simple wrapper providing expand behavior)
@available(iOS 15.0, *)
struct ExpandableCameraCard: View {
    @State private var expanded: Bool = false
    @State private var showFullscreen: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Camera")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { withAnimation { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if expanded {
                Button(action: { showFullscreen = true }) {
                    CameraFeedCard()
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 6)
            } else {
                // Collapsed preview - show small live camera feed
                CameraFeedCard()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .onTapGesture {
                        // tapping collapsed view expands it
                        withAnimation { expanded = true }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .fullScreenCover(isPresented: $showFullscreen) {
            FullscreenCameraView(isPresented: $showFullscreen)
                .edgesIgnoringSafeArea(.all)
        }
    }
}

// MARK: - Fullscreen Camera View with Pinch-to-Zoom
@available(iOS 15.0, *)
struct FullscreenCameraView: View {
    @Binding var isPresented: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            CameraFeedCard()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { v in
                            scale = lastScale * v
                        }
                        .onEnded { _ in
                            lastScale = scale
                            // limit zoom
                            scale = min(max(1.0, scale), 5.0)
                            lastScale = scale
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { g in
                            offset = CGSize(width: lastOffset.width + g.translation.width, height: lastOffset.height + g.translation.height)
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .padding()

            HStack(spacing: 12) {
                Button(action: {
                    withAnimation {
                        // reset zoom and offset
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }) {
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: 18, weight: .semibold))
                        .padding(10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            .padding(20)
        }
    }
}


// MARK: - Editable Widget Grid
@available(iOS 15.0, *)
struct EditableWidgetGrid: View {
    @Binding var widgets: [WidgetItem]
    @Binding var isEditMode: Bool
    let weather: WeatherData
    let storageUsed: Double
    let storageTotal: Double
    let recentFiles: [FileItem]
    @Binding var todos: [String]
    @Binding var newTodo: String
    @Binding var showTodoInput: Bool
    let columns: Int
    
    @State private var draggedWidget: WidgetItem?
    @State private var dragOffset: CGSize = .zero
    @State private var showResizeMenu: WidgetItem? = nil
    
    var body: some View {
        let cellWidth: CGFloat = 120
        let cellHeight: CGFloat = 120
        let spacing: CGFloat = 16
        
        ZStack {
            VStack(spacing: spacing) {
                ForEach(0..<maxRow, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { col in
                            if let widget = widgetAt(row: row, col: col) {
                                widgetView(for: widget)
                                    .frame(
                                        width: cellWidth * CGFloat(widget.gridPosition.colSpan) + spacing * CGFloat(widget.gridPosition.colSpan - 1),
                                        height: cellHeight * CGFloat(widget.gridPosition.rowSpan) + spacing * CGFloat(widget.gridPosition.rowSpan - 1)
                                    )
                                    .scaleEffect(isEditMode ? 0.95 : 1.0)
                                    .opacity(draggedWidget?.id == widget.id ? 0.6 : 1.0)
                                    .offset(draggedWidget?.id == widget.id ? dragOffset : .zero)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEditMode)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: widget.gridPosition)
                                    .onLongPressGesture(minimumDuration: 0.8) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            if !isEditMode {
                                                isEditMode = true
                                            } else {
                                                // If already in edit mode, long press opens resize menu
                                                showResizeMenu = widget
                                            }
                                        }
                                    }
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                if isEditMode && showResizeMenu == nil {
                                                    draggedWidget = widget
                                                    dragOffset = value.translation
                                                }
                                            }
                                            .onEnded { value in
                                                if isEditMode && showResizeMenu == nil {
                                                    let newCol = max(0, min(col + Int((value.translation.width / (cellWidth + spacing)).rounded()), columns - widget.gridPosition.colSpan))
                                                    let newRow = max(0, row + Int((value.translation.height / (cellHeight + spacing)).rounded()))
                                                    
                                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                        moveWidget(widget, to: GridPosition(
                                                            row: newRow,
                                                            col: newCol,
                                                            rowSpan: widget.gridPosition.rowSpan,
                                                            colSpan: widget.gridPosition.colSpan
                                                        ))
                                                        draggedWidget = nil
                                                        dragOffset = .zero
                                                    }
                                                }
                                            }
                                    )
                            } else if !isCoveredBySpan(row: row, col: col) {
                                Color.clear
                                    .frame(width: cellWidth, height: cellHeight)
                            }
                        }
                    }
                }
            }
            
            // Resize menu overlay
            if let selectedWidget = showResizeMenu {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showResizeMenu = nil
                    }
                
                VStack(spacing: 20) {
                    Text("Resize Widget")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    VStack(spacing: 16) {
                        // Width controls
                        HStack(spacing: 20) {
                            Text("Width:")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 80, alignment: .leading)
                            
                            Button(action: {
                                resizeWidget(selectedWidget, widthChange: -1, heightChange: 0)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.red)
                            }
                            .disabled(selectedWidget.gridPosition.colSpan <= 1)
                            
                            Text("\(selectedWidget.gridPosition.colSpan)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40)
                            
                            Button(action: {
                                resizeWidget(selectedWidget, widthChange: 1, heightChange: 0)
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.green)
                            }
                            .disabled(selectedWidget.gridPosition.col + selectedWidget.gridPosition.colSpan >= columns)
                        }
                        
                        // Height controls
                        HStack(spacing: 20) {
                            Text("Height:")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 80, alignment: .leading)
                            
                            Button(action: {
                                resizeWidget(selectedWidget, widthChange: 0, heightChange: -1)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.red)
                            }
                            .disabled(selectedWidget.gridPosition.rowSpan <= 1)
                            
                            Text("\(selectedWidget.gridPosition.rowSpan)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40)
                            
                            Button(action: {
                                resizeWidget(selectedWidget, widthChange: 0, heightChange: 1)
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    
                    Button(action: {
                        showResizeMenu = nil
                    }) {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(25)
                    }
                    .padding(.top, 10)
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(white: 0.15))
                        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    var maxRow: Int {
        (widgets.map { $0.gridPosition.row + $0.gridPosition.rowSpan }.max() ?? 1)
    }
    
    func widgetAt(row: Int, col: Int) -> WidgetItem? {
        widgets.first { widget in
            widget.gridPosition.row == row && widget.gridPosition.col == col
        }
    }
    
    func isCoveredBySpan(row: Int, col: Int) -> Bool {
        widgets.contains { widget in
            row >= widget.gridPosition.row &&
            row < widget.gridPosition.row + widget.gridPosition.rowSpan &&
            col >= widget.gridPosition.col &&
            col < widget.gridPosition.col + widget.gridPosition.colSpan &&
            !(row == widget.gridPosition.row && col == widget.gridPosition.col)
        }
    }
    
    func widgetView(for widget: WidgetItem) -> some View {
        Group {
            switch widget.type {
            case .camera:
                CameraFeedCard()
            case .weather:
                WeatherCard(weather: weather)
            case .storage:
                StorageCard(storageUsed: storageUsed, storageTotal: storageTotal, recentFiles: recentFiles)
            case .todo:
                TodoCard(todos: $todos, newTodo: $newTodo, showTodoInput: $showTodoInput)
            }
        }
        .overlay(
            Group {
                if isEditMode {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.blue, lineWidth: 2)
                }
            }
        )
    }
    
    func moveWidget(_ widget: WidgetItem, to newPosition: GridPosition) {
        if let index = widgets.firstIndex(where: { $0.id == widget.id }) {
            widgets[index].gridPosition = newPosition
        }
    }
    
    func resizeWidget(_ widget: WidgetItem, widthChange: Int = 0, heightChange: Int = 0) {
        if let index = widgets.firstIndex(where: { $0.id == widget.id }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                var newColSpan = widgets[index].gridPosition.colSpan + widthChange
                var newRowSpan = widgets[index].gridPosition.rowSpan + heightChange
                
                // Ensure minimum size of 1x1
                newColSpan = max(1, newColSpan)
                newRowSpan = max(1, newRowSpan)
                
                // Ensure doesn't exceed grid bounds
                let maxColSpan = columns - widgets[index].gridPosition.col
                newColSpan = min(newColSpan, maxColSpan)
                
                widgets[index].gridPosition.colSpan = newColSpan
                widgets[index].gridPosition.rowSpan = newRowSpan
            }
        }
    }
}

// MARK: - Weather Data Model
struct WeatherData {
    var temp: Int
    var condition: String
    var location: String
}

// Grid item for files with thumbnail preview
// Small breadcrumb button used in the folder navigation bar
struct BreadcrumbButton: View {
    let title: String
    let targetPath: String
    @Binding var currentPath: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            if currentPath != targetPath {
                currentPath = targetPath
                action()
            }
        }) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(currentPath == targetPath ? Color.white.opacity(0.12) : Color.black.opacity(0.12))
                .cornerRadius(12)
                .foregroundColor(.white)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FileGridItem: View {
        let item: FileItem
        let onTap: () -> Void
        @State private var thumbnail: UIImage?
        @State private var isPressed = false
        @Namespace private var animationNamespace
        
        var body: some View {
            Button(action: { onTap() }) {
                GeometryReader { geo in
                    VStack(spacing: 8) {
                        ZStack {
                            let thumbSize = min(geo.size.width, geo.size.height * 0.7)
                            if item.isDirectory {
                                Image(systemName: "folder.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: thumbSize * 0.9, maxHeight: thumbSize * 0.9)
                                    .foregroundColor(.yellow)
                            } else if let thumb = thumbnail {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: thumbSize, height: thumbSize)
                                    .clipped()
                                    .cornerRadius(8)
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.12))
                                    .frame(width: thumbSize, height: thumbSize)
                                    .cornerRadius(8)
                                    .overlay(
                                        Image(systemName: iconForFile(item.name))
                                            .resizable()
                                            .scaledToFit()
                                            .padding(12)
                                            .foregroundColor(.blue)
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Text(item.name)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(6)
                }
                .frame(minHeight: 120)
            }
            .buttonStyle(PlainButtonStyle())
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                if !item.isDirectory && isImageFile(item.name) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        onTap()
                    }
                }
            })
            .onAppear {
                // Start thumbnail prefetch for image files only, using a shared
                // prefetcher with limited concurrency and an in-memory cache.
                if !item.isDirectory && isImageFile(item.name) {
                    if let img = FileManagerClient.shared.thumbnailImage(forPath: item.path) {
                        thumbnail = img
                    } else {
                        FileManagerClient.shared.prefetchThumbnail(path: item.path) { img in
                            if let img = img {
                                self.thumbnail = img
                            }
                        }
                    }
                }
            }
        }
        
        // loadThumbnail removed — using ThumbnailPrefetcher instead
        
        func isImageFile(_ name: String) -> Bool {
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp"]
            return imageExtensions.contains(name.components(separatedBy: ".").last?.lowercased() ?? "")
        }
        
        func iconForFile(_ name: String) -> String {
            let ext = name.components(separatedBy: ".").last?.lowercased() ?? ""
            switch ext {
            case "pdf": return "doc.fill"
            case "zip", "rar", "7z": return "doc.zipper"
            case "mp4", "mov", "avi": return "film.fill"
            case "mp3", "wav", "m4a": return "music.note"
            default: return "doc.fill"
            }
        }
    }


// Full screen image viewer with actions
struct ImageViewer: View {
        let item: FileItem
        @Binding var isPresented: Bool
        let onRefresh: () -> Void
        
        @State private var image: UIImage?
        @State private var isLoading = true
        @State private var scale: CGFloat = 1.0
        @State private var lastScale: CGFloat = 1.0
        @State private var offset: CGSize = .zero
        @State private var lastOffset: CGSize = .zero
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Loading image...")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                } else if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        scale = min(max(scale * delta, 1), 5)
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                        if scale < 1 {
                                            withAnimation {
                                                scale = 1
                                            }
                                        }
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        if scale > 1 {
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if scale > 1 {
                                    scale = 1
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.5
                                }
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        Text("Failed to load image")
                            .foregroundColor(.white)
                    }
                }
                
                VStack {
                    HStack {
                        Button(action: {
                            withAnimation(.spring()) {
                                isPresented = false
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "xmark")
                                    .font(.title3)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding()
                        
                        Spacer()
                        
                        Menu {
                            Button(action: downloadToPhotos) {
                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                            }
                            Button(action: shareImage) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button(role: .destructive, action: deleteFile) {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "ellipsis")
                                    .font(.title3)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding()
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 8) {
                        Text(item.name)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text(formatBytes(item.size))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.6))
                            .blur(radius: 10)
                    )
                    .padding()
                }
            }
            .statusBar(hidden: true)
            .onAppear {
                loadImage()
            }
        }
        
        func loadImage() {
            isLoading = true
            print("Loading image for: \(item.path)")
            
            FileManagerClient.shared.downloadFile(at: item.path) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let url):
                        print("Downloaded to: \(url.path)")
                        if let img = UIImage(contentsOfFile: url.path) {
                            withAnimation(.easeIn(duration: 0.3)) {
                                self.image = img
                                self.isLoading = false
                            }
                            print("Image loaded successfully: \(img.size)")
                        } else {
                            print("Failed to create UIImage from file")
                            self.isLoading = false
                        }
                    case .failure(let error):
                        print("Download failed: \(error.localizedDescription)")
                        self.isLoading = false
                    }
                }
            }
        }
        
        func formatBytes(_ bytes: Int) -> String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(bytes))
        }
        
        func downloadToPhotos() {
            guard let img = image else { return }
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            
            // Show a subtle feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        
        func shareImage() {
            guard let img = image else { return }
            let av = UIActivityViewController(activityItems: [img], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                
                var topVC = rootVC
                while let presentedVC = topVC.presentedViewController {
                    topVC = presentedVC
                }
                
                av.popoverPresentationController?.sourceView = topVC.view
                av.popoverPresentationController?.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                av.popoverPresentationController?.permittedArrowDirections = []
                
                topVC.present(av, animated: true)
            }
        }
        
        func deleteFile() {
            FileManagerClient.shared.deleteFile(at: item.path) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success():
                        withAnimation(.spring()) {
                            isPresented = false
                        }
                        onRefresh()
                        
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    case .failure(let err):
                        print("delete error: \(err)")
                    }
                }
            }
        }
    }
    
    // MARK: - MJPEG Stream Handler
    @available(iOS 15.0, *)
    class MJPEGStreamView: NSObject, ObservableObject, URLSessionDataDelegate {
        // Shared singleton so the stream connection can be established once per app lifecycle
        static let shared = MJPEGStreamView()
        @Published var currentFrame: UIImage?
        @Published var isLoading = true
        @Published var errorMessage = ""
        @Published var isStreaming = false
        @Published var connectionStatus = ""
        
        private var session: URLSession?
        private var dataTask: URLSessionDataTask?
        private var receivedData = Data()
        private let jpegSOI = Data([0xFF, 0xD8]) // JPEG Start Of Image
        private let jpegEOI = Data([0xFF, 0xD9]) // JPEG End Of Image
        private var lastFrameTime = Date()
        private let imageQueue = DispatchQueue(label: "com.gabriel.imageDecoding", qos: .userInitiated)
        private let bufferLock = NSLock() // Thread safety for buffer access
        private var retryCount = 0
        private let maxRetries = 5
        private var isActive = true // Track if view is active
        private var url = "" // Store the URL for reconnection
        
        override init() {
            super.init()
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30 // Reduced to 30 seconds
            config.timeoutIntervalForResource = 300 // 5 minutes
            config.httpMaximumConnectionsPerHost = 1
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.waitsForConnectivity = true
            session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }
        
        func startStreaming(url: String) {
            // Don't restart if already streaming to the same URL
            if isStreaming && dataTask?.currentRequest?.url?.absoluteString == url {
                print("MJPEG: Already streaming to this URL, skipping duplicate start")
                return
            }
            
            // Store the URL for reconnection
            self.url = url
            
            // Don't retry if we've exceeded max retries
            if retryCount >= maxRetries {
                print("MJPEG: Max retries exceeded (\(maxRetries))")
                DispatchQueue.main.async {
                    self.errorMessage = "Connection failed. Please check server."
                    self.isLoading = false
                }
                return
            }
            
            // Stop any existing stream first
            stopStreaming()
            
            guard let streamURL = URL(string: url) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid URL"
                    self.isLoading = false
                }
                return
            }
            
            print("Starting MJPEG stream from: \(url) (attempt \(retryCount + 1)/\(maxRetries))")
            
            DispatchQueue.main.async {
                self.isLoading = true
                self.errorMessage = ""
                self.isActive = true
            }
            
            var request = URLRequest(url: streamURL)
            request.timeoutInterval = 60
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpShouldHandleCookies = false
            request.networkServiceType = .video
            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            
            dataTask = session?.dataTask(with: request)
            dataTask?.resume()
        }
        
        func stopStreaming() {
            guard dataTask != nil else { return }
            
            print("MJPEG: Stopping stream, cleaning up resources")
            isActive = false
            dataTask?.cancel()
            dataTask = nil
            
            bufferLock.lock()
            receivedData.removeAll() // Clear buffer
            receivedData = Data() // Reset data
            bufferLock.unlock()
            
            DispatchQueue.main.async {
                self.isStreaming = false
                self.isLoading = false
            }
        }
        
        // URLSessionDataDelegate methods
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            // Only log if we're not already streaming to reduce spam
            if !isStreaming {
                print("✅ MJPEG: Connected to stream")
            }
            
            DispatchQueue.main.async {
                self.isLoading = false
                self.isStreaming = true
                self.retryCount = 0 // Reset retry count on successful connection
            }
            
            completionHandler(.allow)
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            bufferLock.lock()
            receivedData.append(data)
            
            // Limit buffer size
            if receivedData.count > 1000000 {
                receivedData.removeAll()
                bufferLock.unlock()
                return
            }
            
            bufferLock.unlock()
            
            // Process frames in background
            imageQueue.async { [weak self] in
                guard let self = self else { return }
                
                self.bufferLock.lock()
                
                // Look for JPEG frames in the buffer
                while self.receivedData.count > 100 {
                    // Find JPEG start marker
                    guard let startRange = self.receivedData.range(of: self.jpegSOI) else {
                        // No start marker, clear buffer
                        self.receivedData.removeAll()
                        break
                    }
                    
                    // Validate start range is within bounds
                    guard startRange.lowerBound < self.receivedData.endIndex,
                          startRange.upperBound <= self.receivedData.endIndex else {
                        self.receivedData.removeAll()
                        break
                    }
                    
                    // Ensure we have enough data after start
                    let startIndex = self.receivedData.distance(from: self.receivedData.startIndex, to: startRange.lowerBound)
                    if startIndex + 2 >= self.receivedData.count {
                        // Not enough data yet
                        break
                    }
                    
                    // Find JPEG end marker after the start
                    guard let searchStart = self.receivedData.index(startRange.upperBound, offsetBy: 2, limitedBy: self.receivedData.endIndex) else {
                        break
                    }
                    
                    // Validate search range
                    guard searchStart < self.receivedData.endIndex else {
                        break
                    }
                    
                    let searchRange = searchStart..<self.receivedData.endIndex
                    guard let endRange = self.receivedData.range(of: self.jpegEOI, in: searchRange) else {
                        // No end marker yet, keep data if not too large
                        if self.receivedData.count > 500000 {
                            self.receivedData.removeAll()
                        }
                        break
                    }
                    
                    // Validate end range is within bounds
                    guard endRange.lowerBound < self.receivedData.endIndex,
                          endRange.upperBound <= self.receivedData.endIndex else {
                        self.receivedData.removeAll()
                        break
                    }
                    
                    // Validate frame range - ensure start is before end
                    guard startRange.lowerBound < endRange.upperBound,
                          startRange.lowerBound < self.receivedData.endIndex,
                          endRange.upperBound <= self.receivedData.endIndex else {
                        // Invalid range, remove bad data
                        if let nextStart = self.receivedData.index(startRange.upperBound, offsetBy: 1, limitedBy: self.receivedData.endIndex) {
                            if nextStart <= self.receivedData.endIndex {
                                self.receivedData.removeSubrange(self.receivedData.startIndex..<nextStart)
                            } else {
                                self.receivedData.removeAll()
                            }
                        } else {
                            self.receivedData.removeAll()
                        }
                        continue
                    }
                    
                    // Extract complete JPEG frame - double check bounds
                    let frameRange = startRange.lowerBound..<endRange.upperBound
                    guard frameRange.lowerBound < frameRange.upperBound,
                          frameRange.upperBound <= self.receivedData.endIndex else {
                        self.receivedData.removeAll()
                        break
                    }
                    
                    let frameData = self.receivedData.subdata(in: frameRange)
                    
                    // Basic JPEG validation - check minimum size
                    guard frameData.count > 100 else {
                        // Too small to be a valid JPEG, skip
                        let removeRange = self.receivedData.startIndex..<endRange.upperBound
                        if removeRange.lowerBound < removeRange.upperBound,
                           removeRange.upperBound <= self.receivedData.endIndex {
                            self.receivedData.removeSubrange(removeRange)
                        } else {
                            self.receivedData.removeAll()
                        }
                        continue
                    }
                    
                    // Throttle to max 30 FPS
                    let now = Date()
                    let timeSinceLastFrame = now.timeIntervalSince(self.lastFrameTime)
                    
                    // Decode JPEG in background - less frequently to reduce errors
                    if timeSinceLastFrame >= 0.05 { // 20 FPS = 50ms per frame (reduced from 30 FPS)
                        // Attempt to decode with explicit options to reduce warnings
                        if let image = UIImage(data: frameData) {
                            self.lastFrameTime = now
                            
                            DispatchQueue.main.async {
                                self.currentFrame = image
                                self.isStreaming = true
                            }
                        }
                    }
                    
                    // Remove processed frame from buffer - validate range first
                    guard endRange.upperBound <= self.receivedData.endIndex else {
                        self.receivedData.removeAll()
                        break
                    }
                    
                    let removeRange = self.receivedData.startIndex..<endRange.upperBound
                    guard removeRange.lowerBound < removeRange.upperBound,
                          removeRange.upperBound <= self.receivedData.endIndex else {
                        self.receivedData.removeAll()
                        break
                    }
                    
                    self.receivedData.removeSubrange(removeRange)
                }
                
                self.bufferLock.unlock()
            }
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                let nsError = error as NSError
                // Ignore cancellation errors
                if nsError.code == NSURLErrorCancelled {
                    print("MJPEG stream cancelled")
                    return
                }
                
                // Only retry if still active and haven't exceeded max retries
                guard isActive && retryCount < maxRetries else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Disconnected"
                        self.isLoading = false
                        self.isStreaming = false
                    }
                    return
                }
                
                retryCount += 1
                
                if nsError.code == NSURLErrorTimedOut {
                    print("MJPEG stream timeout, retrying... (attempt \(retryCount)/\(maxRetries))")
                    DispatchQueue.main.async {
                        self.errorMessage = "Reconnecting..."
                        self.isLoading = true
                    }
                } else {
                    print("MJPEG stream error: \(error.localizedDescription), retrying... (attempt \(retryCount)/\(maxRetries))")
                    DispatchQueue.main.async {
                        self.errorMessage = "Connection lost - retrying..."
                        self.isLoading = true
                        self.isStreaming = false
                    }
                }
                
                // Exponential backoff: 2s, 4s, 8s...
                let delay = min(pow(2.0, Double(retryCount)), 10.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, self.isActive else { return }
                    if let url = task.currentRequest?.url?.absoluteString {
                        self.startStreaming(url: url)
                    }
                }
            } else {
                // Stream completed without error - this can happen with DevTunnels/proxies
                // Automatically reconnect if we're still active and haven't exceeded retries
                print("MJPEG stream completed normally - isActive: \(isActive), retryCount: \(retryCount)/\(maxRetries)")
                
                // Check if we got redirected to an auth page
                if let responseURL = task.response?.url?.absoluteString,
                   !responseURL.contains("/api/camera-stream") {
                    print("⚠️ Redirected to: \(responseURL)")
                    print("⚠️ DevTunnels authentication expired - please re-authenticate in browser")
                    DispatchQueue.main.async {
                        self.isActive = false
                        self.isStreaming = false
                        self.connectionStatus = "Auth required"
                        self.errorMessage = "DevTunnels authentication required"
                    }
                    return
                }
                
                guard isActive && retryCount < maxRetries else {
                    print("⚠️ Not reconnecting - isActive: \(isActive), retryCount: \(retryCount)")
                    DispatchQueue.main.async {
                        self.isStreaming = false
                    }
                    return
                }
                
                retryCount += 1
                print("🔄 Auto-reconnecting... (attempt \(retryCount)/\(maxRetries))")
                
                DispatchQueue.main.async {
                    self.errorMessage = "Reconnecting..."
                    self.isLoading = true
                }
                
                // Quick retry for normal completion - use ORIGINAL url, not redirected one
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self, self.isActive else { 
                        print("⚠️ Reconnect cancelled - stream no longer active")
                        return
                    }
                    // Use self.url (original) instead of task URL (which might be redirected)
                    print("🔄 Reconnecting to: \(self.url)")
                    self.startStreaming(url: self.url)
                }
            }
        }
        
        deinit {
            print("MJPEG: Deinitializing stream handler")
            isActive = false
            dataTask?.cancel()
            dataTask = nil
            session?.invalidateAndCancel()
            session = nil
            
            bufferLock.lock()
            receivedData.removeAll()
            bufferLock.unlock()
            
            currentFrame = nil
        }
    }
    
    
    // Simple DocumentPicker wrapper to select files
    struct DocumentPicker: UIViewControllerRepresentable {
        var onPick: ([URL]) -> Void
        
        func makeCoordinator() -> Coordinator { Coordinator(self) }
        
        func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
            let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            vc.delegate = context.coordinator
            vc.allowsMultipleSelection = true
            return vc
        }
        
        func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
        
        class Coordinator: NSObject, UIDocumentPickerDelegate {
            let parent: DocumentPicker
            init(_ p: DocumentPicker) { parent = p }
            func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                parent.onPick(urls)
            }
        }
    }

@available(iOS 15.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
