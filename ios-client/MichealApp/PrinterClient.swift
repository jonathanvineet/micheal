//
//  PrinterClient.swift
//  Micheal
//
//  3D Printer API Client for Marlin-based printer control
//

import Foundation
import Combine

class PrinterClient: ObservableObject {
    static let shared = PrinterClient()
    
    private let baseURL: String
    private let session: URLSession
    
    // Published state for real-time updates
    @Published var isConnected: Bool = false
    @Published var currentTemperatures: TemperatureReadings = TemperatureReadings()
    @Published var printProgress: PrintProgress = PrintProgress()
    @Published var sdFiles: [SDFile] = []
    @Published var printerStatus: PrinterStatus = PrinterStatus()
    
    // Polling timer
    private var statusTimer: Timer?
    
    init() {
        // Use the same base URL as FileManagerClient
        self.baseURL = FileManagerClient.shared.baseURL
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Connection
    
    func checkConnection() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/ping") else { return false }
        
        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                let connected = (200...299).contains(httpResponse.statusCode)
                await MainActor.run { isConnected = connected }
                return connected
            }
        } catch {
            print("Connection check failed: \(error)")
        }
        
        await MainActor.run { isConnected = false }
        return false
    }
    
    // MARK: - Temperature Control
    
    func setHotendTemperature(_ temp: Int, wait: Bool = false) async throws {
        let action = wait ? "hotend-wait" : "hotend"
        try await sendTemperatureCommand(action: action, temp: temp)
    }
    
    func setBedTemperature(_ temp: Int, wait: Bool = false) async throws {
        let action = wait ? "bed-wait" : "bed"
        try await sendTemperatureCommand(action: action, temp: temp)
    }
    
    func turnOffHeaters() async throws {
        try await sendTemperatureCommand(action: "off", temp: nil)
    }
    
    func preheatPLA() async throws {
        try await setHotendTemperature(200)
        try await setBedTemperature(60)
    }
    
    func preheatPETG() async throws {
        try await setHotendTemperature(235)
        try await setBedTemperature(80)
    }
    
    func preheatABS() async throws {
        try await setHotendTemperature(240)
        try await setBedTemperature(100)
    }
    
    private func sendTemperatureCommand(action: String, temp: Int?) async throws {
        guard let url = URL(string: "\(baseURL)/api/printer/temperature") else {
            throw PrinterError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["action": action]
        if let temp = temp {
            body["temp"] = temp
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PrinterError.requestFailed
        }
        
        print("Temperature command sent: \(action) \(temp ?? 0)°C")
    }
    
    // MARK: - Motion Control
    
    func homeAxes(x: Bool = true, y: Bool = true, z: Bool = true) async throws {
        guard let url = URL(string: "\(baseURL)/api/printer/motion") else {
            throw PrinterError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "action": "home",
            "params": [
                "x": x,
                "y": y,
                "z": z
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PrinterError.requestFailed
        }
        
        print("Homing axes: X:\(x) Y:\(y) Z:\(z)")
    }
    
    func moveAxis(x: Double? = nil, y: Double? = nil, z: Double? = nil, feedrate: Int = 3000) async throws {
        guard let url = URL(string: "\(baseURL)/api/printer/motion") else {
            throw PrinterError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var params: [String: Any] = ["feedrate": feedrate]
        if let x = x { params["x"] = x }
        if let y = y { params["y"] = y }
        if let z = z { params["z"] = z }
        
        let body: [String: Any] = [
            "action": "move",
            "params": params
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PrinterError.requestFailed
        }
        
        print("Moving: X:\(x ?? 0) Y:\(y ?? 0) Z:\(z ?? 0)")
    }
    
    // MARK: - SD Card Operations
    
    func listSDFiles() async throws -> [SDFile] {
        guard let url = URL(string: "\(baseURL)/api/printer/sd?action=list") else {
            throw PrinterError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PrinterError.requestFailed
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(SDFilesResponse.self, from: data)
        
        await MainActor.run {
            self.sdFiles = result.files
        }
        
        return result.files
    }
    
    func startPrint(filename: String) async throws {
        try await sendSDCommand(action: "print", filename: filename)
    }
    
    func pausePrint() async throws {
        try await sendSDCommand(action: "pause")
    }
    
    func resumePrint() async throws {
        try await sendSDCommand(action: "resume")
    }
    
    func stopPrint() async throws {
        try await sendSDCommand(action: "stop")
    }
    
    func initSDCard() async throws {
        try await sendSDCommand(action: "init")
    }
    
    private func sendSDCommand(action: String, filename: String? = nil) async throws {
        guard let url = URL(string: "\(baseURL)/api/printer/sd") else {
            throw PrinterError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["action": action]
        if let filename = filename {
            body["filename"] = filename
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PrinterError.requestFailed
        }
        
        print("SD command sent: \(action) \(filename ?? "")")
    }
    
    func getSDProgress() async throws -> PrintProgress {
        guard let url = URL(string: "\(baseURL)/api/printer/sd?action=progress") else {
            throw PrinterError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PrinterError.requestFailed
        }
        
        let decoder = JSONDecoder()
        let progress = try decoder.decode(PrintProgress.self, from: data)
        
        await MainActor.run {
            self.printProgress = progress
        }
        
        return progress
    }
    
    // MARK: - Status Polling
    
    func startStatusPolling() {
        stopStatusPolling() // Clear any existing timer
        
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task {
                await self?.updateStatus()
            }
        }
        
        // Run immediately
        Task {
            await updateStatus()
        }
    }
    
    func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }
    
    private func updateStatus() async {
        // Update temperatures
        do {
            let temps = try await getTemperatures()
            await MainActor.run {
                self.currentTemperatures = temps
            }
        } catch {
            print("Failed to get temperatures: \(error)")
        }
        
        // Update print progress
        do {
            let progress = try await getSDProgress()
            await MainActor.run {
                self.printProgress = progress
            }
        } catch {
            print("Failed to get print progress: \(error)")
        }
    }
    
    func getTemperatures() async throws -> TemperatureReadings {
        guard let url = URL(string: "\(baseURL)/api/printer/status?action=temperature") else {
            throw PrinterError.invalidURL
        }
        
        let (data, _) = try await session.data(from: url)
        let decoder = JSONDecoder()
        let temps = try decoder.decode(TemperatureReadings.self, from: data)
        
        return temps
    }
    
    // MARK: - Emergency Stop
    
    func emergencyStop() async throws {
        guard let url = URL(string: "\(baseURL)/api/printer/safety") else {
            throw PrinterError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["action": "emergency_stop"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, _) = try await session.data(for: request)
        print("⚠️ EMERGENCY STOP TRIGGERED")
    }
}

// MARK: - Models

struct TemperatureReadings: Codable {
    var hotendTemp: Double = 0
    var hotendTarget: Double = 0
    var bedTemp: Double = 0
    var bedTarget: Double = 0
    
    enum CodingKeys: String, CodingKey {
        case hotendTemp = "hotend_temp"
        case hotendTarget = "hotend_target"
        case bedTemp = "bed_temp"
        case bedTarget = "bed_target"
    }
}

struct PrintProgress: Codable {
    var isPrinting: Bool = false
    var filename: String = ""
    var percentComplete: Double = 0
    var bytesPrinted: Int = 0
    var totalBytes: Int = 0
    
    enum CodingKeys: String, CodingKey {
        case isPrinting = "printing"
        case filename
        case percentComplete = "percent"
        case bytesPrinted = "bytes_printed"
        case totalBytes = "total_bytes"
    }
}

struct SDFile: Codable, Identifiable {
    var id: String { name }
    var name: String
    var size: Int?
    
    var displaySize: String {
        guard let size = size else { return "Unknown" }
        let kb = Double(size) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        } else {
            let mb = kb / 1024.0
            return String(format: "%.1f MB", mb)
        }
    }
}

struct SDFilesResponse: Codable {
    var files: [SDFile]
}

struct PrinterStatus: Codable {
    var connected: Bool = false
    var firmware: String = "Unknown"
    var state: String = "idle"
}

enum PrinterError: Error {
    case invalidURL
    case requestFailed
    case decodingFailed
    case notConnected
}
