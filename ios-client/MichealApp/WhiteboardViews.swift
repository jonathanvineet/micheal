//
//  WhiteboardViews.swift
//  Micheal
//
//  Created on 12/10/2025.
//

import SwiftUI
import UIKit

// MARK: - Whiteboard List View
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

// MARK: - Drawing Preview
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

// MARK: - Drawing Editor View
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

    @State private var selectedImageID: UUID?
    @State private var showImagePicker = false

    private let availableColors: [Color] = [.white, .red, .green, .blue, .yellow, .orange, .purple]

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.1, blue: 0.12).ignoresSafeArea()

            DrawingCanvas(
                paths: $document.paths,
                images: $document.images,
                currentPath: $currentPath,
                scale: $scale,
                lastScale: $lastScale,
                offset: $offset,
                lastOffset: $lastOffset,
                selectedImageID: $selectedImageID
            )
            .ignoresSafeArea()

            VStack {
                editorToolbar
                Spacer()
            }
        }
        .navigationTitle(document.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    saveViewTransform()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: { showImagePicker = true }) { Image(systemName: "photo") }
                Button(action: resetView) { Image(systemName: "arrow.counterclockwise") }
                Button(action: undo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(document.paths.isEmpty && document.images.isEmpty)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker { image in addImage(image) }
        }
        .onAppear { restoreViewTransform() }
        .onDisappear {
            saveViewTransform()
            store.save(document: document)
        }
        .onChange(of: selectedColor) { newColor in currentPath.color = newColor }
        .onChange(of: selectedLineWidth) { newWidth in currentPath.lineWidth = newWidth }
    }

    private var editorToolbar: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(availableColors, id: \.self) { color in
                    Button(action: { selectedColor = color }) {
                        Circle()
                            .fill(color)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                            )
                    }
                }
            }

            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                Slider(value: $selectedLineWidth, in: 1...20)
                Image(systemName: "circle.fill")
                    .font(.system(size: 20))
            }
            .foregroundColor(.white)
            .padding(.horizontal)
        }
        .padding()
        .background(Color.black.opacity(0.5))
        .cornerRadius(20)
        .padding(.horizontal)
    }

    private func undo() {
        if !document.images.isEmpty {
            document.images.removeLast()
        } else if !document.paths.isEmpty {
            document.paths.removeLast()
        }
    }

    private func resetView() {
        withAnimation {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

    private func saveViewTransform() {
        document.lastViewTransform = DrawingDocument.ViewTransform(
            scale: scale,
            offset: offset
        )
    }

    private func restoreViewTransform() {
        scale = document.lastViewTransform.scale
        lastScale = scale
        offset = document.lastViewTransform.offset
        lastOffset = offset
    }

    private func addImage(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }

        // Calculate visible center in canvas coordinates
        let screenCenter = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
        let canvasCenter = screenCenter.transformed(by: transformToCanvas())

        // Smart auto-sizing
        let maxDimension: CGFloat = 800
        let imageSize = image.size
        let scaleFactor = min(1.0, maxDimension / max(imageSize.width, imageSize.height))

        let placedImage = PlacedImage(
            imageData: imageData,
            position: canvasCenter,
            scale: scaleFactor,
            rotation: 0.0
        )

        document.images.append(placedImage)
        selectedImageID = placedImage.id
    }

    private func transformToCanvas() -> CGAffineTransform {
        return CGAffineTransform(scaleX: 1.0 / max(scale, 0.0001), y: 1.0 / max(scale, 0.0001))
            .translatedBy(x: -offset.width, y: -offset.height)
    }
}

// MARK: - Drawing Canvas
@available(iOS 15.0, *)
struct DrawingCanvas: UIViewRepresentable {
    @Binding var paths: [DrawingPath]
    @Binding var images: [PlacedImage]
    @Binding var currentPath: DrawingPath
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var selectedImageID: UUID?

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let rotation = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotation(_:)))
        rotation.delegate = context.coordinator
        view.addGestureRecognizer(rotation)

        return view
    }

    func updateUIView(_ uiView: CanvasView, context: Context) {
        uiView.paths = paths
        uiView.images = images
        uiView.currentPath = currentPath
        uiView.scale = scale
        uiView.offset = offset
        uiView.selectedImageID = selectedImageID
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, CanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: DrawingCanvas

        init(_ parent: DrawingCanvas) { self.parent = parent }

        func didBeginPath(at point: CGPoint) { parent.currentPath.points = [point] }
        func didAppendToPath(at point: CGPoint) { parent.currentPath.points.append(point) }
        func didEndPath() {
            if !parent.currentPath.points.isEmpty {
                parent.paths.append(parent.currentPath)
                parent.currentPath = DrawingPath(color: parent.currentPath.color, lineWidth: parent.currentPath.lineWidth)
            }
        }

        func didTapOnImage(at point: CGPoint) {
            for image in parent.images.reversed() {
                if imageContainsPoint(image: image, point: point) {
                    parent.selectedImageID = image.id
                    return
                }
            }
            parent.selectedImageID = nil
        }

        func didMoveImage(id: UUID, translation: CGSize) {
            if let index = parent.images.firstIndex(where: { $0.id == id }) {
                parent.images[index].position.x += translation.width / parent.scale
                parent.images[index].position.y += translation.height / parent.scale
            }
        }

        func didScaleImage(id: UUID, scale: CGFloat) {
            if let index = parent.images.firstIndex(where: { $0.id == id }) {
                parent.images[index].scale *= scale
            }
        }

        func didRotateImage(id: UUID, rotation: Double) {
            if let index = parent.images.firstIndex(where: { $0.id == id }) {
                parent.images[index].rotation += rotation
            }
        }

        private func imageContainsPoint(image: PlacedImage, point: CGPoint) -> Bool {
            guard let uiImage = UIImage(data: image.imageData) else { return false }
            let size = CGSize(width: uiImage.size.width * image.scale, height: uiImage.size.height * image.scale)
            let rect = CGRect(x: image.position.x - size.width / 2, y: image.position.y - size.height / 2, width: size.width, height: size.height)
            return rect.contains(point)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            if parent.selectedImageID != nil {
                switch gesture.state {
                case .began: break
                case .changed:
                    if let id = parent.selectedImageID { self.didScaleImage(id: id, scale: gesture.scale); gesture.scale = 1.0 }
                default: break
                }
            } else {
                switch gesture.state {
                case .began: parent.lastScale = parent.scale
                case .changed:
                    let newScale = parent.lastScale * gesture.scale
                    parent.scale = Swift.max(0.2, Swift.min(newScale, 5.0))
                case .ended, .cancelled: parent.lastScale = 1.0
                default: break
                }
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)

            if parent.selectedImageID != nil {
                switch gesture.state {
                case .began: break
                case .changed:
                    if let id = parent.selectedImageID { self.didMoveImage(id: id, translation: CGSize(width: translation.x, height: translation.y)); gesture.setTranslation(.zero, in: gesture.view) }
                default: break
                }
                return
            }

            guard gesture.numberOfTouches == 2 else { return }
            switch gesture.state {
            case .began: parent.lastOffset = parent.offset
            case .changed: parent.offset = CGSize(width: parent.lastOffset.width + translation.x, height: parent.lastOffset.height + translation.y)
            default: break
            }
        }

        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let selectedID = parent.selectedImageID else { return }

            switch gesture.state {
            case .changed:
                self.didRotateImage(id: selectedID, rotation: Double(gesture.rotation))
                gesture.rotation = 0
            default: break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { return true }
    }
}

// MARK: - Canvas View Delegate Protocol
protocol CanvasViewDelegate: AnyObject {
    func didBeginPath(at point: CGPoint)
    func didAppendToPath(at point: CGPoint)
    func didEndPath()
    func didTapOnImage(at point: CGPoint)
    func didMoveImage(id: UUID, translation: CGSize)
    func didScaleImage(id: UUID, scale: CGFloat)
    func didRotateImage(id: UUID, rotation: Double)
}

// MARK: - Canvas View (UIView with IMPROVED Touch Handling)
class CanvasView: UIView {
    weak var delegate: CanvasViewDelegate?
    var paths: [DrawingPath] = [] { didSet { setNeedsDisplay() } }
    var images: [PlacedImage] = [] { didSet { setNeedsDisplay() } }
    var currentPath: DrawingPath? { didSet { setNeedsDisplay() } }
    var scale: CGFloat = 1.0 { didSet { setNeedsDisplay() } }
    var offset: CGSize = .zero { didSet { setNeedsDisplay() } }
    var selectedImageID: UUID? { didSet { setNeedsDisplay() } }

    private var isDrawing = false
    private var touchStartTime: Date?
    private var touchStartLocation: CGPoint?
    private var imageDragStart: CGPoint?
    private var hasMovedSignificantly = false
    
    // IMPROVED: Constants for distinguishing tap vs draw
    private let tapDistanceThreshold: CGFloat = 10.0  // Max distance to consider it a tap
    private let tapTimeThreshold: TimeInterval = 0.3  // Max time to consider it a tap

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let canvasPoint = location.transformed(by: transformToCanvas())

        touchStartTime = Date()
        touchStartLocation = location
        hasMovedSignificantly = false

        // IMPROVED: Only interact with single touch
        guard event?.allTouches?.count == 1 else { return }
        
        // Check if starting touch is on an image
        var touchedImageID: UUID?
        for image in images.reversed() {
            if imageContainsPoint(image: image, point: canvasPoint) {
                touchedImageID = image.id
                break
            }
        }
        
        if let imageID = touchedImageID {
            // Touch started on an image
            if selectedImageID == imageID {
                // Image already selected - prepare for potential dragging or drawing
                imageDragStart = canvasPoint
                // Don't start drawing yet - wait for movement to determine intent
            } else {
                // Different image selected - select it
                delegate?.didTapOnImage(at: canvasPoint)
                imageDragStart = canvasPoint
            }
        } else {
            // Touch started outside any image - deselect current image if any
            if selectedImageID != nil {
                delegate?.didTapOnImage(at: canvasPoint)
            }
            // Start drawing
            isDrawing = true
            delegate?.didBeginPath(at: canvasPoint)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let canvasPoint = location.transformed(by: transformToCanvas())
        
        // IMPROVED: Track movement distance from start
        if let startLoc = touchStartLocation {
            let distance = hypot(location.x - startLoc.x, location.y - startLoc.y)
            if distance > tapDistanceThreshold {
                hasMovedSignificantly = true
            }
        }

        // If already drawing, keep drawing
        if isDrawing {
            delegate?.didAppendToPath(at: canvasPoint)
            return
        }

        // If moved significantly and touch started on an image
        if hasMovedSignificantly && imageDragStart != nil && selectedImageID != nil {
            // Prioritize drawing over dragging when user draws
            isDrawing = true
            if let startLoc = touchStartLocation {
                let startCanvasPoint = startLoc.transformed(by: transformToCanvas())
                delegate?.didBeginPath(at: startCanvasPoint)
                delegate?.didAppendToPath(at: canvasPoint)
            }
            imageDragStart = nil  // Stop trying to drag
            return
        }

        // If moved significantly and no image was selected when touch started
        if hasMovedSignificantly && imageDragStart == nil && !isDrawing {
            isDrawing = true
            if let startLoc = touchStartLocation {
                let startCanvasPoint = startLoc.transformed(by: transformToCanvas())
                delegate?.didBeginPath(at: startCanvasPoint)
                delegate?.didAppendToPath(at: canvasPoint)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // IMPROVED: Determine if this was a tap or a draw/drag
        let wasTap = !hasMovedSignificantly && 
                     (touchStartTime.map { Date().timeIntervalSince($0) < tapTimeThreshold } ?? false)
        
        if isDrawing {
            isDrawing = false
            delegate?.didEndPath()
        } else if wasTap && imageDragStart != nil {
            // Quick tap on image without moving - this is handled by touchesBegan's didTapOnImage
            // No additional action needed
        }
        
        // Reset state
        imageDragStart = nil
        touchStartTime = nil
        touchStartLocation = nil
        hasMovedSignificantly = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isDrawing {
            isDrawing = false
            delegate?.didEndPath()
        }
        imageDragStart = nil
        touchStartTime = nil
        touchStartLocation = nil
        hasMovedSignificantly = false
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        context.translateBy(x: offset.width, y: offset.height)
        context.scaleBy(x: scale, y: scale)

        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Draw images first
        for image in images { drawImage(image: image, in: context) }

        // Draw paths on top (so you can draw over images)
        for path in paths { draw(path: path, in: context) }

        if let currentPath = currentPath, isDrawing { draw(path: currentPath, in: context) }

        context.restoreGState()
    }

    private func drawImage(image: PlacedImage, in context: CGContext) {
        guard let uiImage = UIImage(data: image.imageData) else { return }

        context.saveGState()

        // Move to image position
        context.translateBy(x: image.position.x, y: image.position.y)

        // Apply rotation
        context.rotate(by: CGFloat(image.rotation))

        // Apply scale
        let scaledSize = CGSize(width: uiImage.size.width * image.scale, height: uiImage.size.height * image.scale)

        let rect = CGRect(x: -scaledSize.width / 2, y: -scaledSize.height / 2, width: scaledSize.width, height: scaledSize.height)

        uiImage.draw(in: rect)

        // Draw selection border and handles
        if selectedImageID == image.id {
            context.setStrokeColor(UIColor.yellow.cgColor)
            context.setLineWidth(2.0 / scale)
            context.stroke(rect)

            let handleSize: CGFloat = 20.0 / scale
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            for corner in corners {
                let handleRect = CGRect(x: corner.x - handleSize / 2, y: corner.y - handleSize / 2, width: handleSize, height: handleSize)
                context.setFillColor(UIColor.yellow.cgColor)
                context.fillEllipse(in: handleRect)
            }
        }

        context.restoreGState()
    }

    private func draw(path: DrawingPath, in context: CGContext) {
        guard !path.points.isEmpty else { return }

        context.setLineWidth(path.lineWidth / scale)
        context.setStrokeColor(UIColor(path.color).cgColor)

        let cgPath = CGMutablePath()
        cgPath.addLines(between: path.points)
        context.addPath(cgPath)
        context.strokePath()
    }

    private func transformToCanvas() -> CGAffineTransform {
        return CGAffineTransform(scaleX: 1.0 / max(scale, 0.0001), y: 1.0 / max(scale, 0.0001))
            .translatedBy(x: -offset.width, y: -offset.height)
    }

    private func imageContainsPoint(image: PlacedImage, point: CGPoint) -> Bool {
        guard let uiImage = UIImage(data: image.imageData) else { return false }

        let size = CGSize(width: uiImage.size.width * image.scale, height: uiImage.size.height * image.scale)

        let rect = CGRect(x: image.position.x - size.width / 2, y: image.position.y - size.height / 2, width: size.width, height: size.height)

        return rect.contains(point)
    }
}

// MARK: - Image Picker
@available(iOS 15.0, *)
struct ImagePicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}

// MARK: - Scribble Card
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
