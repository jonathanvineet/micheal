import SwiftUI
import UIKit

@available(iOS 15.0, *)
struct ContentView: View {
    @State private var files: [FileItem] = []
    @State private var loading = false
    @State private var currentPath = ""
    @State private var showPicker = false
    @State private var uploadProgress: Double = 0.0
    @State private var isUploading = false
    @State private var uploadingFileName = ""
    @State private var selectedItem: FileItem? = nil
    @State private var showingImageViewer = false

    var body: some View {
        NavigationView {
            VStack {
                if loading {
                    ProgressView("Loading…")
                }
                
                if isUploading {
                    VStack(spacing: 8) {
                        Text("Uploading \(uploadingFileName)…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ProgressView(value: uploadProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                        Text("\(Int(uploadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 10) {
                        ForEach(files) { item in
                            FileGridItem(item: item) {
                                if item.isDirectory {
                                    // Navigate to folder
                                } else if isImageFile(item.name) {
                                    selectedItem = item
                                    showingImageViewer = true
                                }
                            }
                        }
                    }
                    .padding()
                }

                HStack {
                    Button(action: { showPicker.toggle() }) { 
                        Label("Upload", systemImage: "arrow.up.doc") 
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                    
                    Button(action: { loadFiles() }) { 
                        Label("Refresh", systemImage: "arrow.clockwise") 
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Gabriel")
            .sheet(isPresented: $showPicker) {
                DocumentPicker { urls in
                    for url in urls {
                        isUploading = true
                        uploadingFileName = url.lastPathComponent
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
                                        loadFiles()
                                    case .failure(let err):
                                        print("upload error: \(err)")
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
                        loadFiles()
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.1).combined(with: .opacity),
                        removal: .scale(scale: 0.1).combined(with: .opacity)
                    ))
                }
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showingImageViewer)
            .onAppear(perform: loadFiles)
        }
    }

    func loadFiles() {
        loading = true
        FileManagerClient.shared.listFiles(path: currentPath) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let items): self.files = items
                case .failure(let err): print("list error: \(err)")
                }
                loading = false
            }
        }
    }
    
    func isImageFile(_ name: String) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp"]
        return imageExtensions.contains(name.components(separatedBy: ".").last?.lowercased() ?? "")
    }
}

// Grid item for files with thumbnail preview
struct FileGridItem: View {
    let item: FileItem
    let onTap: () -> Void
    @State private var thumbnail: UIImage?
    @State private var isPressed = false
    @Namespace private var animationNamespace
    
    var body: some View {
        VStack {
            ZStack {
                if item.isDirectory {
                    Image(systemName: "folder.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                        .foregroundColor(.yellow)
                } else if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .cornerRadius(8)
                        
                        Image(systemName: iconForFile(item.name))
                            .resizable()
                            .scaledToFit()
                            .frame(height: 50)
                            .foregroundColor(.blue)
                    }
                }
            }
            .frame(width: 100, height: 100)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            
            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 30)
        }
        .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 50) {
            // Long press triggers expansion
            if !item.isDirectory && isImageFile(item.name) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    onTap()
                }
            }
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.2)) {
                isPressed = pressing
            }
        }
        .onTapGesture {
            // Regular tap also works
            if !item.isDirectory && isImageFile(item.name) {
                onTap()
            }
        }
        .onAppear {
            if !item.isDirectory && isImageFile(item.name) {
                loadThumbnail()
            }
        }
    }
    
    func loadThumbnail() {
        FileManagerClient.shared.downloadFile(at: item.path) { result in
            if case .success(let url) = result {
                DispatchQueue.global(qos: .userInitiated).async {
                    if let image = UIImage(contentsOfFile: url.path) {
                        let size = CGSize(width: 300, height: 300)
                        let renderer = UIGraphicsImageRenderer(size: size)
                        let thumb = renderer.image { _ in
                            image.draw(in: CGRect(origin: .zero, size: size))
                        }
                        
                        DispatchQueue.main.async {
                            self.thumbnail = thumb
                        }
                    }
                }
            }
        }
    }
    
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
                                .fontWeight(.semibold)
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
                                .fontWeight(.semibold)
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
                    
                    if let size = item.size {
                        Text(formatBytes(size))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
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
