import Foundation
import PhotosUI
import SwiftUI
import UIKit

enum AppPermission: String, CaseIterable, Codable, Sendable {
    case photoLibrary
    case camera
    case locationWhenInUse
}

enum PermissionStatus: String, CaseIterable, Codable, Sendable {
    case notDetermined
    case denied
    case authorized
}

struct ImportedPhotoLocation: Equatable, Codable, Sendable {
    var latitude: Double
    var longitude: Double
}

struct ImportedPhoto: Equatable, Codable, Sendable {
    var id: UUID
    var localIdentifier: String?
    var displayImageData: Data
    var thumbnailData: Data
    var pixelWidth: Int32
    var pixelHeight: Int32
    var capturedAt: Date?
    var suggestedLocation: ImportedPhotoLocation?
}

struct CameraCapture {
    var image: UIImage
    var metadata: [String: Any]?
}

@MainActor
protocol PermissionCoordinating {
    func status(for permission: AppPermission) async -> PermissionStatus
    func requestAccess(for permission: AppPermission) async -> PermissionStatus
}

@MainActor
protocol PhotoImporting {
    func importPhotoLibraryItem(_ item: PhotosPickerItem) async throws -> ImportedPhoto
    func importCameraCapture(_ capture: CameraCapture) async throws -> ImportedPhoto
}

@MainActor
protocol LocationSuggesting {
    func suggestedPlace(for location: ImportedPhotoLocation) async -> PlaceDraft?
    func searchPlaces(matching query: String) async throws -> [PlaceDraft]
    func currentLocationPlace() async throws -> PlaceDraft
}
