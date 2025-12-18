//
//  PrinterControlCard.swift
//  Micheal
//
//  3D Printer Control Interface - Temperature, Motion, and SD Card Controls
//

import SwiftUI

@available(iOS 15.0, *)
struct PrinterControlCard: View {
    @StateObject private var printerClient = PrinterClient.shared
    @State private var isExpanded = false
    @State private var showSDFiles = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Temperature targets
    @State private var hotendTarget: Double = 0
    @State private var bedTarget: Double = 0
    
    // Motion controls
    @State private var moveDistance: Double = 10.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "cube.box.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.purple)
                    
                    Text("3D PRINTER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(1.5)
                    
                    Spacer()
                    
                    // Connection status
                    HStack(spacing: 6) {
                        Circle()
                            .fill(printerClient.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text(printerClient.isConnected ? "ONLINE" : "OFFLINE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(printerClient.isConnected ? .green : .red)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(20)
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                VStack(spacing: 20) {
                    // Error message
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                    }
                    
                    // Temperature Controls
                    temperatureSection
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 20)
                    
                    // Preheat Presets
                    preheatPresetsSection
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 20)
                    
                    // Motion Controls
                    motionControlsSection
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 20)
                    
                    // SD Card & Print Controls
                    sdCardSection
                }
                .padding(.bottom, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.15), Color.purple.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .onAppear {
            Task {
                _ = await printerClient.checkConnection()
                if printerClient.isConnected {
                    printerClient.startStatusPolling()
                }
            }
        }
        .onDisappear {
            printerClient.stopStatusPolling()
        }
        .sheet(isPresented: $showSDFiles) {
            SDFileBrowserView()
        }
    }
    
    // MARK: - Temperature Section
    
    var temperatureSection: some View {
        VStack(spacing: 16) {
            Text("Temperature Control")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            
            // Hotend Temperature
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("Hotend")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Text("\(Int(printerClient.currentTemperatures.hotendTemp))°C / \(Int(hotendTarget))°C")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 20)
                
                HStack(spacing: 12) {
                    Text("0")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                    
                    Slider(value: $hotendTarget, in: 0...300, step: 5) { editing in
                        if !editing {
                            setHotendTemperature()
                        }
                    }
                    .accentColor(.orange)
                    
                    Text("300")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 20)
            }
            
            // Bed Temperature
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "square.fill")
                        .foregroundColor(.blue)
                    Text("Bed")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Text("\(Int(printerClient.currentTemperatures.bedTemp))°C / \(Int(bedTarget))°C")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 20)
                
                HStack(spacing: 12) {
                    Text("0")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                    
                    Slider(value: $bedTarget, in: 0...120, step: 5) { editing in
                        if !editing {
                            setBedTemperature()
                        }
                    }
                    .accentColor(.blue)
                    
                    Text("120")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 20)
            }
            
            // Turn off heaters button
            Button(action: {
                turnOffHeaters()
            }) {
                HStack {
                    Image(systemName: "power")
                    Text("Turn Off Heaters")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.3))
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Preheat Presets Section
    
    var preheatPresetsSection: some View {
        VStack(spacing: 12) {
            Text("Preheat Presets")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            
            HStack(spacing: 12) {
                // PLA
                Button(action: { preheat(type: .pla) }) {
                    VStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16))
                        Text("PLA")
                            .font(.system(size: 11, weight: .bold))
                        Text("200°/60°")
                            .font(.system(size: 9))
                            .opacity(0.7)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.3))
                    .cornerRadius(12)
                }
                
                // PETG
                Button(action: { preheat(type: .petg) }) {
                    VStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16))
                        Text("PETG")
                            .font(.system(size: 11, weight: .bold))
                        Text("235°/80°")
                            .font(.system(size: 9))
                            .opacity(0.7)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange.opacity(0.3))
                    .cornerRadius(12)
                }
                
                // ABS
                Button(action: { preheat(type: .abs) }) {
                    VStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16))
                        Text("ABS")
                            .font(.system(size: 11, weight: .bold))
                        Text("240°/100°")
                            .font(.system(size: 9))
                            .opacity(0.7)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.3))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Motion Controls Section
    
    var motionControlsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Axis Movement")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Home button
                Button(action: { homeAllAxes() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                        Text("Home")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.3))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 20)
            
            // Distance selector
            HStack {
                Text("Move Distance:")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                
                ForEach([1.0, 10.0, 50.0], id: \.self) { distance in
                    Button(action: { moveDistance = distance }) {
                        Text("\(Int(distance))mm")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(moveDistance == distance ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(moveDistance == distance ? Color.purple.opacity(0.5) : Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // Movement controls
            VStack(spacing: 16) {
                // Z axis
                HStack(spacing: 16) {
                    Spacer()
                    
                    VStack(spacing: 8) {
                        Button(action: { moveZ(up: true) }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.cyan)
                        }
                        
                        Text("Z")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Button(action: { moveZ(up: false) }) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.cyan)
                        }
                    }
                    
                    Spacer()
                }
                
                // X and Y axes
                HStack(spacing: 40) {
                    // Y axis controls
                    VStack(spacing: 12) {
                        Button(action: { moveY(forward: true) }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.green)
                        }
                        
                        HStack(spacing: 20) {
                            Button(action: { moveX(left: true) }) {
                                Image(systemName: "arrow.left.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.orange)
                            }
                            
                            VStack(spacing: 2) {
                                Text("X Y")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.5))
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            
                            Button(action: { moveX(left: false) }) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Button(action: { moveY(forward: false) }) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - SD Card Section
    
    var sdCardSection: some View {
        VStack(spacing: 12) {
            Text("SD Card & Print")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            
            Button(action: {
                showSDFiles = true
                loadSDFiles()
            }) {
                HStack {
                    Image(systemName: "sdcard.fill")
                    Text("Browse SD Card Files")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                }
                .foregroundColor(.white)
                .padding(16)
                .background(Color.purple.opacity(0.3))
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            
            // Emergency stop
            Button(action: { emergencyStop() }) {
                HStack {
                    Image(systemName: "stop.circle.fill")
                    Text("EMERGENCY STOP")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.5))
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Actions
    
    private func setHotendTemperature() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                try await printerClient.setHotendTemperature(Int(hotendTarget))
            } catch {
                errorMessage = "Failed to set hotend temperature"
            }
            isLoading = false
        }
    }
    
    private func setBedTemperature() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                try await printerClient.setBedTemperature(Int(bedTarget))
            } catch {
                errorMessage = "Failed to set bed temperature"
            }
            isLoading = false
        }
    }
    
    private func turnOffHeaters() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                try await printerClient.turnOffHeaters()
                hotendTarget = 0
                bedTarget = 0
            } catch {
                errorMessage = "Failed to turn off heaters"
            }
            isLoading = false
        }
    }
    
    private func preheat(type: PreheatType) {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                switch type {
                case .pla:
                    try await printerClient.preheatPLA()
                    hotendTarget = 200
                    bedTarget = 60
                case .petg:
                    try await printerClient.preheatPETG()
                    hotendTarget = 235
                    bedTarget = 80
                case .abs:
                    try await printerClient.preheatABS()
                    hotendTarget = 240
                    bedTarget = 100
                }
            } catch {
                errorMessage = "Failed to preheat for \(type.rawValue)"
            }
            isLoading = false
        }
    }
    
    private func homeAllAxes() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                try await printerClient.homeAxes()
            } catch {
                errorMessage = "Failed to home axes"
            }
            isLoading = false
        }
    }
    
    private func moveX(left: Bool) {
        Task {
            errorMessage = nil
            do {
                let distance = left ? -moveDistance : moveDistance
                try await printerClient.moveAxis(x: distance)
            } catch {
                errorMessage = "Failed to move X axis"
            }
        }
    }
    
    private func moveY(forward: Bool) {
        Task {
            errorMessage = nil
            do {
                let distance = forward ? moveDistance : -moveDistance
                try await printerClient.moveAxis(y: distance)
            } catch {
                errorMessage = "Failed to move Y axis"
            }
        }
    }
    
    private func moveZ(up: Bool) {
        Task {
            errorMessage = nil
            do {
                let distance = up ? moveDistance : -moveDistance
                try await printerClient.moveAxis(z: distance)
            } catch {
                errorMessage = "Failed to move Z axis"
            }
        }
    }
    
    private func loadSDFiles() {
        Task {
            errorMessage = nil
            do {
                try await printerClient.initSDCard()
                _ = try await printerClient.listSDFiles()
            } catch {
                errorMessage = "Failed to load SD files"
            }
        }
    }
    
    private func emergencyStop() {
        Task {
            do {
                try await printerClient.emergencyStop()
            } catch {
                print("Emergency stop failed: \(error)")
            }
        }
    }
}

// MARK: - SD File Browser View

@available(iOS 15.0, *)
struct SDFileBrowserView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var printerClient = PrinterClient.shared
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.opacity(0.9)
                    .ignoresSafeArea()
                
                VStack {
                    if isLoading {
                        ProgressView()
                            .tint(.purple)
                    } else if printerClient.sdFiles.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "sdcard")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.3))
                            Text("No files found on SD card")
                                .foregroundColor(.white.opacity(0.6))
                        }
                    } else {
                        List {
                            ForEach(printerClient.sdFiles) { file in
                                Button(action: {
                                    startPrint(filename: file.name)
                                }) {
                                    HStack {
                                        Image(systemName: "doc.fill")
                                            .foregroundColor(.purple)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.name)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white)
                                            
                                            if let size = file.size {
                                                Text(file.displaySize)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.white.opacity(0.5))
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "play.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 24))
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("SD Card Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.purple)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { loadFiles() }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.purple)
                    }
                }
            }
        }
        .onAppear {
            loadFiles()
        }
    }
    
    private func loadFiles() {
        Task {
            isLoading = true
            do {
                try await printerClient.initSDCard()
                _ = try await printerClient.listSDFiles()
            } catch {
                print("Failed to load SD files: \(error)")
            }
            isLoading = false
        }
    }
    
    private func startPrint(filename: String) {
        Task {
            do {
                try await printerClient.startPrint(filename: filename)
                dismiss()
            } catch {
                print("Failed to start print: \(error)")
            }
        }
    }
}

// MARK: - Supporting Types

enum PreheatType: String {
    case pla = "PLA"
    case petg = "PETG"
    case abs = "ABS"
}
