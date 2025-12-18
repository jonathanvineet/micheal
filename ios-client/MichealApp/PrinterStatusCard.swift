//
//  PrinterStatusCard.swift
//  Micheal
//
//  Dashboard card showing current 3D print status and progress
//

import SwiftUI

@available(iOS 15.0, *)
struct PrinterStatusCard: View {
    @StateObject private var printerClient = PrinterClient.shared
    @State private var showFullControls = false
    
    var body: some View {
        Button(action: {
            showFullControls = true
        }) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "cube.box.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.purple)
                    
                    Text("3D PRINTER STATUS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(1.5)
                    
                    Spacer()
                    
                    // Connection indicator
                    Circle()
                        .fill(printerClient.isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                }
                
                if !printerClient.isConnected {
                    // Offline state
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.yellow.opacity(0.5))
                        
                        Text("Printer Offline")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("Tap to configure")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    
                } else if printerClient.printProgress.isPrinting {
                    // Printing state
                    VStack(alignment: .leading, spacing: 16) {
                        // Current file
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.purple)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(printerClient.printProgress.filename)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                Text("Printing...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            }
                            
                            Spacer()
                        }
                        
                        // Progress bar
                        VStack(spacing: 8) {
                            HStack {
                                Text("Progress")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Spacer()
                                
                                Text("\(Int(printerClient.printProgress.percentComplete))%")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.purple)
                            }
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                    
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.purple, Color.purple.opacity(0.7)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geometry.size.width * CGFloat(printerClient.printProgress.percentComplete / 100.0))
                                }
                            }
                            .frame(height: 12)
                        }
                        
                        // Temperature readings
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                    Text("Hotend")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                Text("\(Int(printerClient.currentTemperatures.hotendTemp))°C")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.blue)
                                    Text("Bed")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                Text("\(Int(printerClient.currentTemperatures.bedTemp))°C")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                        }
                        
                        // Control buttons
                        HStack(spacing: 12) {
                            Button(action: { pausePrint() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "pause.circle.fill")
                                    Text("Pause")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.orange.opacity(0.3))
                                .cornerRadius(10)
                            }
                            
                            Button(action: { stopPrint() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "stop.circle.fill")
                                    Text("Stop")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.red.opacity(0.3))
                                .cornerRadius(10)
                            }
                        }
                    }
                    
                } else {
                    // Idle state
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.green.opacity(0.7))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ready to Print")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text("Printer is idle")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            
                            Spacer()
                        }
                        
                        // Temperature readings
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                    Text("Hotend")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                Text("\(Int(printerClient.currentTemperatures.hotendTemp))°C")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.blue)
                                    Text("Bed")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                Text("\(Int(printerClient.currentTemperatures.bedTemp))°C")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            Spacer()
                        }
                        
                        Text("Tap to configure printer")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showFullControls) {
            PrinterFullControlsView()
        }
        .onAppear {
            Task {
                _ = await printerClient.checkConnection()
                if printerClient.isConnected {
                    printerClient.startStatusPolling()
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func pausePrint() {
        Task {
            do {
                try await printerClient.pausePrint()
            } catch {
                print("Failed to pause print: \(error)")
            }
        }
    }
    
    private func stopPrint() {
        Task {
            do {
                try await printerClient.stopPrint()
            } catch {
                print("Failed to stop print: \(error)")
            }
        }
    }
}

// MARK: - Full Controls View (Modal)

@available(iOS 15.0, *)
struct PrinterFullControlsView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.opacity(0.9)
                    .ignoresSafeArea()
                
                ScrollView {
                    PrinterControlCard()
                        .padding()
                }
            }
            .navigationTitle("3D Printer Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.purple)
                }
            }
        }
    }
}
