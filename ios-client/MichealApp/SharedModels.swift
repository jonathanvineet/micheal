//
//  SharedModels.swift
//  Micheal
//
//  Created on 12/10/2025.
//

import SwiftUI
import UIKit

// MARK: - Color Extension
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

// MARK: - Font Weight Extension
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

// MARK: - Weather Data Model
struct WeatherData {
    var temp: Int
    var condition: String
    var location: String
}

// MARK: - QuickLook Helpers
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

import QuickLook
