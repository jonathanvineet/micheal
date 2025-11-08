import SwiftUI

@available(iOS 15.0, *)
struct ContentView: View {
    @State private var files: [FileItem] = []
    @State private var loading = false
    @State private var currentPath = ""
    @State private var showPicker = false

    var body: some View {
        NavigationView {
            VStack {
                if loading {
                    ProgressView("Loading…")
                }
                List(files) { item in
                    HStack {
                        Image(systemName: item.isDirectory ? "folder" : "doc")
                            .foregroundColor(item.isDirectory ? .yellow : .blue)
                        VStack(alignment: .leading) {
                            Text(item.name)
                                .font(.body)
                            if let s = item.size { Text("\(s) bytes").font(.caption) }
                        }
                        Spacer()
                        if !item.isDirectory {
                            Button(action: { download(item: item) }) {
                                Image(systemName: "arrow.down.to.line")
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())

                HStack {
                    Button(action: { showPicker.toggle() }) { Label("Upload", systemImage: "arrow.up.doc") }
                    Spacer()
                    Button(action: { loadFiles() }) { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                .padding()
            }
            .navigationTitle("Gabriel")
            .sheet(isPresented: $showPicker) {
                DocumentPicker { urls in
                    for url in urls {
                        // Upload each picked URL
                        FileManagerClient.shared.upload(fileURL: url, relativePath: nil, toPath: currentPath) { _ in } completion: { result in
                            switch result {
                            case .success(): print("uploaded")
                            case .failure(let err): print("upload error: \(err)")
                            }
                        }
                    }
                    showPicker = false
                }
            }
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

    func download(item: FileItem) {
        FileManagerClient.shared.downloadFile(at: item.path) { result in
            switch result {
            case .success(let localURL): print("Downloaded to \(localURL)")
            case .failure(let err): print("download error: \(err)")
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
