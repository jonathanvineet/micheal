import SwiftUI
import UIKit

@available(iOS 15.0, *)
struct ContentView: View {
    @State private var showDashboard = true
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if showDashboard {
                DashboardView(showDashboard: $showDashboard)
            } else {
                FileManagerView(showDashboard: $showDashboard)
            }
        }
    }
}

// MARK: - Dashboard View
@available(iOS 15.0, *)
struct DashboardView: View {
    @State private var currentTime = Date()
    @State private var fileManagerClient = FileManagerClient()
    @State private var serverReachable = false
    @State private var checkingConnection = true
    
    var body: some View {
        NavigationView {
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
                            Text("Batman")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.yellow, Color.orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        Text(currentTime, style: .date)
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(currentTime, style: .time)
                            .font(.system(size: 36, weight: .black))
                            .foregroundColor(.white)
                        Text(currentTime.formatted(.dateTime.hour().minute()).components(separatedBy: " ").last ?? "")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                            .textCase(.uppercase)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Dashboard Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    
                    // Weather Card
                    WeatherCard(weather: weather)
                        .frame(height: 220)
                    
                    // Storage Card
                    StorageCard(storageUsed: storageUsed, storageTotal: storageTotal, recentFiles: recentFiles)
                        .frame(height: 220)
                }
                .padding(.horizontal, 16)
                
                // Camera Feed - Full Width
                CameraFeedCard()
                    .frame(height: 280)
                    .padding(.horizontal, 16)
                
                // Things To Do Card
                TodoCard(todos: $todos, newTodo: $newTodo, showTodoInput: $showTodoInput)
                    .frame(height: 320)
                    .padding(.horizontal, 16)
                
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
                                .font(.system(size: 24, weight: .black))
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
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .onAppear {
            checkServerConnection()
            loadRecentFiles()
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
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
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
                    .font(.system(size: 56, weight: .black))
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
        default: return "cloud.sun.fill"
        }
    }
}

// MARK: - Camera Feed Card
@available(iOS 15.0, *)
struct CameraFeedCard: View {
    @StateObject private var mjpegStream = MJPEGStreamView()
    
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
                            
                            Text(mjpegStream.isStreaming ? "LIVE 30 FPS" : "OFFLINE")
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
            mjpegStream.startStreaming(url: "\(FileManagerClient.shared.baseURL)/api/camera-stream")
        }
        .onDisappear {
            mjpegStream.stopStreaming()
        }
    }
}

// MARK: - Storage Card
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
                    .font(.system(size: 32, weight: .black))
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
                        .font(.system(size: 20, weight: .black))
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
            .background(Color.black.opacity(0.5))
            
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
                        .foregroundColor(.black)
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding()
                .background(Color.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
                
                Button(action: { loadFiles() }) { 
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
            }
            .padding()
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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

// MARK: - Weather Data Model
struct WeatherData {
    var temp: Int
    var condition: String
    var location: String
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
    @Published var currentFrame: UIImage?
    @Published var isLoading = true
    @Published var errorMessage = ""
    @Published var isStreaming = false
    
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var receivedData = Data()
    private let jpegSOI = Data([0xFF, 0xD8]) // JPEG Start Of Image
    private let jpegEOI = Data([0xFF, 0xD9]) // JPEG End Of Image
    private var lastFrameTime = Date()
    private let imageQueue = DispatchQueue(label: "com.gabriel.imageDecoding", qos: .userInitiated)
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // 2 minutes
        config.timeoutIntervalForResource = 7200 // 2 hours
        config.httpMaximumConnectionsPerHost = 1
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = true // Important for iOS
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func startStreaming(url: String) {
        // Don't restart if already streaming to the same URL
        if isStreaming && dataTask?.currentRequest?.url?.absoluteString == url {
            return
        }
        
        stopStreaming()
        
        guard let streamURL = URL(string: url) else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL"
                self.isLoading = false
            }
            return
        }
        
        print("Starting MJPEG stream from: \(url)")
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = ""
        }
        
        var request = URLRequest(url: streamURL)
        request.timeoutInterval = 120
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.networkServiceType = .video // Optimize for video streaming
        
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }
    
    func stopStreaming() {
        guard dataTask != nil else { return }
        
        print("Stopping MJPEG stream")
        dataTask?.cancel()
        dataTask = nil
        receivedData = Data()
        
        DispatchQueue.main.async {
            self.isStreaming = false
        }
    }
    
    // URLSessionDataDelegate methods
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        print("MJPEG: Connected to stream")
        
        DispatchQueue.main.async {
            self.isLoading = false
            self.isStreaming = true
        }
        
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        
        // Limit buffer size
        if receivedData.count > 1000000 {
            receivedData.removeAll()
            return
        }
        
        // Process frames in background
        imageQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Look for JPEG frames in the buffer
            while self.receivedData.count > 100 {
                // Find JPEG start marker
                guard let startRange = self.receivedData.range(of: self.jpegSOI) else {
                    // No start marker, clear buffer
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
                let searchStart = self.receivedData.index(startRange.upperBound, offsetBy: 2, limitedBy: self.receivedData.endIndex) ?? self.receivedData.endIndex
                
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
                
                // Validate frame range
                guard startRange.lowerBound < endRange.upperBound else {
                    // Invalid range, remove bad data
                    if let nextStart = self.receivedData.index(startRange.upperBound, offsetBy: 1, limitedBy: self.receivedData.endIndex) {
                        self.receivedData.removeSubrange(self.receivedData.startIndex..<nextStart)
                    } else {
                        self.receivedData.removeAll()
                    }
                    continue
                }
                
                // Extract complete JPEG frame
                let frameRange = startRange.lowerBound..<endRange.upperBound
                let frameData = self.receivedData.subdata(in: frameRange)
                
                // Throttle to max 30 FPS
                let now = Date()
                let timeSinceLastFrame = now.timeIntervalSince(self.lastFrameTime)
                
                // Decode JPEG in background
                if timeSinceLastFrame >= 0.033 { // 30 FPS = ~33ms per frame
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
                
                self.receivedData.removeSubrange(self.receivedData.startIndex..<endRange.upperBound)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            // Ignore cancellation errors
            if nsError.code == NSURLErrorCancelled {
                print("MJPEG stream cancelled")
            } else if nsError.code == NSURLErrorTimedOut {
                print("MJPEG stream timeout, will retry...")
                DispatchQueue.main.async {
                    self.errorMessage = "Connecting..."
                    self.isLoading = true
                }
                // Retry after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if let url = task.currentRequest?.url?.absoluteString {
                        self.startStreaming(url: url)
                    }
                }
            } else {
                print("MJPEG stream error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Connection lost - retrying..."
                    self.isLoading = false
                    self.isStreaming = false
                }
                // Retry after 3 seconds for other errors
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if let url = task.currentRequest?.url?.absoluteString {
                        self.startStreaming(url: url)
                    }
                }
            }
        } else {
            print("MJPEG stream completed")
            DispatchQueue.main.async {
                self.isStreaming = false
            }
        }
    }
    
    deinit {
        stopStreaming()
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
