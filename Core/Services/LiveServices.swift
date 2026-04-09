import AVFoundation
import CoreLocation
import Foundation
import ImageIO
import MapKit
import Photos
import PhotosUI
import SwiftUI
import UIKit

enum PermissionCoordinatorError: LocalizedError {
    case locationServicesDisabled

    var errorDescription: String? {
        switch self {
        case .locationServicesDisabled:
            "Location Services are turned off for this device."
        }
    }
}

enum PhotoImportError: LocalizedError {
    case unreadableImage
    case unsupportedImageData
    case failedToEncodeDisplayImage
    case failedToEncodeThumbnail

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "Couldn't read that photo."
        case .unsupportedImageData:
            "That image format isn't supported yet."
        case .failedToEncodeDisplayImage, .failedToEncodeThumbnail:
            "Couldn't prepare that photo for saving."
        }
    }
}

enum LocationSuggestionError: LocalizedError {
    case locationPermissionRequired
    case currentLocationUnavailable

    var errorDescription: String? {
        switch self {
        case .locationPermissionRequired:
            "Allow location access to use your current location."
        case .currentLocationUnavailable:
            "Couldn't determine your current location right now."
        }
    }
}

@MainActor
final class LivePermissionCoordinator: NSObject, PermissionCoordinating, @preconcurrency CLLocationManagerDelegate {
    private var locationManager: CLLocationManager?
    private var locationAuthorizationContinuation: CheckedContinuation<PermissionStatus, Never>?

    func status(for permission: AppPermission) async -> PermissionStatus {
        switch permission {
        case .photoLibrary:
            return Self.photoLibraryPermissionStatus(from: PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .camera:
            return Self.cameraPermissionStatus(from: AVCaptureDevice.authorizationStatus(for: .video))
        case .locationWhenInUse:
            let authorizationStatus = locationManager?.authorizationStatus ?? CLLocationManager().authorizationStatus
            return Self.locationPermissionStatus(from: authorizationStatus)
        }
    }

    func requestAccess(for permission: AppPermission) async -> PermissionStatus {
        switch permission {
        case .photoLibrary:
            let existingStatus = await status(for: permission)
            guard existingStatus == .notDetermined else {
                return existingStatus
            }

            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { authorizationStatus in
                    continuation.resume(
                        returning: Self.photoLibraryPermissionStatus(from: authorizationStatus)
                    )
                }
            }
        case .camera:
            let existingStatus = await status(for: permission)
            guard existingStatus == .notDetermined else {
                return existingStatus
            }

            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }

            return granted ? .authorized : .denied
        case .locationWhenInUse:
            let existingStatus = await status(for: permission)
            guard existingStatus == .notDetermined else {
                return existingStatus
            }

            guard CLLocationManager.locationServicesEnabled() else {
                return .denied
            }

            if locationManager == nil {
                let manager = CLLocationManager()
                manager.delegate = self
                locationManager = manager
            }

            return await withCheckedContinuation { continuation in
                locationAuthorizationContinuation = continuation
                locationManager?.requestWhenInUseAuthorization()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = locationAuthorizationContinuation else {
            return
        }

        let status = Self.locationPermissionStatus(from: manager.authorizationStatus)
        guard status != .notDetermined else {
            return
        }

        locationAuthorizationContinuation = nil
        continuation.resume(returning: status)
    }

    nonisolated private static func photoLibraryPermissionStatus(
        from authorizationStatus: PHAuthorizationStatus
    ) -> PermissionStatus {
        switch authorizationStatus {
        case .authorized, .limited:
            .authorized
        case .denied, .restricted:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }
    }

    nonisolated private static func cameraPermissionStatus(
        from authorizationStatus: AVAuthorizationStatus
    ) -> PermissionStatus {
        switch authorizationStatus {
        case .authorized:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    nonisolated private static func locationPermissionStatus(
        from authorizationStatus: CLAuthorizationStatus
    ) -> PermissionStatus {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            .authorized
        case .denied, .restricted:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }
    }
}

@MainActor
final class LivePhotoImportService: PhotoImporting {
    private let displayLongEdge: CGFloat = 2048
    private let thumbnailSide: CGFloat = 320

    func importPhotoLibraryItem(_ item: PhotosPickerItem) async throws -> ImportedPhoto {
        guard let imageData = try await item.loadTransferable(type: Data.self) else {
            throw PhotoImportError.unreadableImage
        }

        let metadata = await photoLibraryMetadata(
            localIdentifier: item.itemIdentifier,
            imageData: imageData
        )
        let normalizedImage = try normalizeImportedImage(from: imageData)

        return ImportedPhoto(
            id: UUID(),
            localIdentifier: item.itemIdentifier,
            displayImageData: normalizedImage.displayImageData,
            thumbnailData: normalizedImage.thumbnailData,
            pixelWidth: normalizedImage.pixelWidth,
            pixelHeight: normalizedImage.pixelHeight,
            capturedAt: metadata.capturedAt,
            suggestedLocation: metadata.location
        )
    }

    func importCameraCapture(_ capture: CameraCapture) async throws -> ImportedPhoto {
        let normalizedImage = try normalizeImportedImage(from: capture.image)
        let metadata = cameraMetadata(from: capture.metadata)

        return ImportedPhoto(
            id: UUID(),
            localIdentifier: nil,
            displayImageData: normalizedImage.displayImageData,
            thumbnailData: normalizedImage.thumbnailData,
            pixelWidth: normalizedImage.pixelWidth,
            pixelHeight: normalizedImage.pixelHeight,
            capturedAt: metadata.capturedAt,
            suggestedLocation: metadata.location
        )
    }

    private func normalizeImportedImage(from imageData: Data) throws -> NormalizedImage {
        guard let image = UIImage(data: imageData) else {
            throw PhotoImportError.unsupportedImageData
        }

        return try normalizeImportedImage(from: image)
    }

    private func normalizeImportedImage(from image: UIImage) throws -> NormalizedImage {
        let displayImage = resizedImage(from: image, maxLongEdge: displayLongEdge)
        let thumbnailImage = squareThumbnail(from: displayImage, sideLength: thumbnailSide)

        guard let displayImageData = displayImage.jpegData(compressionQuality: 0.82) else {
            throw PhotoImportError.failedToEncodeDisplayImage
        }

        guard let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.72) else {
            throw PhotoImportError.failedToEncodeThumbnail
        }

        let pixelWidth = Int32(max(1, Int(displayImage.size.width.rounded(.toNearestOrEven))))
        let pixelHeight = Int32(max(1, Int(displayImage.size.height.rounded(.toNearestOrEven))))

        return NormalizedImage(
            displayImageData: displayImageData,
            thumbnailData: thumbnailData,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    private func resizedImage(from image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0,
              size.height > 0 else {
            return image
        }

        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else {
            return image
        }

        let scaleRatio = maxLongEdge / longEdge
        let targetSize = CGSize(
            width: floor(size.width * scaleRatio),
            height: floor(size.height * scaleRatio)
        )
        return renderImage(size: targetSize) { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func squareThumbnail(from image: UIImage, sideLength: CGFloat) -> UIImage {
        let sourceSize = image.size
        guard sourceSize.width > 0,
              sourceSize.height > 0 else {
            return image
        }

        let scale = max(sideLength / sourceSize.width, sideLength / sourceSize.height)
        let scaledSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let origin = CGPoint(
            x: (sideLength - scaledSize.width) / 2,
            y: (sideLength - scaledSize.height) / 2
        )

        return renderImage(size: CGSize(width: sideLength, height: sideLength)) { _ in
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }

    private func renderImage(
        size: CGSize,
        drawing: (UIGraphicsImageRendererContext) -> Void
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image(actions: drawing)
    }

    private func photoLibraryMetadata(
        localIdentifier: String?,
        imageData: Data
    ) async -> ImportedPhotoMetadata {
        if let localIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject {
            return ImportedPhotoMetadata(
                capturedAt: asset.creationDate,
                location: asset.location.map {
                    ImportedPhotoLocation(
                        latitude: $0.coordinate.latitude,
                        longitude: $0.coordinate.longitude
                    )
                }
            )
        }

        // PhotosPicker does not guarantee that every imported transfer includes an addressable PHAsset.
        // When the picker only gives us image bytes, fall back to whatever EXIF/GPS payload is embedded.
        return metadata(from: imageData)
    }

    private func cameraMetadata(from metadataDictionary: [String: Any]?) -> ImportedPhotoMetadata {
        metadata(from: metadataDictionary as [AnyHashable: Any]?)
    }

    private func metadata(from imageData: Data) -> ImportedPhotoMetadata {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ImportedPhotoMetadata(capturedAt: nil, location: nil)
        }

        return metadata(from: properties)
    }

    private func metadata(from properties: [AnyHashable: Any]?) -> ImportedPhotoMetadata {
        guard let properties else {
            return ImportedPhotoMetadata(capturedAt: nil, location: nil)
        }

        let capturedAt = exifDate(from: properties)
        let location = gpsLocation(from: properties)
        return ImportedPhotoMetadata(capturedAt: capturedAt, location: location)
    }

    private func exifDate(from properties: [AnyHashable: Any]) -> Date? {
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [AnyHashable: Any],
           let rawDate = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String ?? exif[kCGImagePropertyExifDateTimeDigitized as String] as? String,
           let parsedDate = Self.exifDateFormatter.date(from: rawDate) {
            return parsedDate
        }

        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [AnyHashable: Any],
           let rawDate = tiff[kCGImagePropertyTIFFDateTime as String] as? String,
           let parsedDate = Self.exifDateFormatter.date(from: rawDate) {
            return parsedDate
        }

        return nil
    }

    private func gpsLocation(from properties: [AnyHashable: Any]) -> ImportedPhotoLocation? {
        guard let gps = properties[kCGImagePropertyGPSDictionary as String] as? [AnyHashable: Any],
              let latitudeValue = gps[kCGImagePropertyGPSLatitude as String] as? CLLocationDegrees,
              let longitudeValue = gps[kCGImagePropertyGPSLongitude as String] as? CLLocationDegrees else {
            return nil
        }

        let latitudeRef = (gps[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased()
        let longitudeRef = (gps[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased()

        let latitude = latitudeRef == "S" ? -latitudeValue : latitudeValue
        let longitude = longitudeRef == "W" ? -longitudeValue : longitudeValue
        return ImportedPhotoLocation(latitude: latitude, longitude: longitude)
    }

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()
}

@MainActor
final class LiveLocationSuggestionService: NSObject, LocationSuggesting, @preconcurrency CLLocationManagerDelegate {
    private var currentLocationManager: CLLocationManager?
    private var currentLocationContinuation: CheckedContinuation<CLLocation, Error>?

    func suggestedPlace(for location: ImportedPhotoLocation) async -> PlaceDraft? {
        let location = CLLocation(latitude: location.latitude, longitude: location.longitude)
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            return placemarks.first.map(Self.placeDraft(from:))
        } catch {
            return PlaceDraft(
                title: "Photo location",
                locality: nil,
                country: nil,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
    }

    func searchPlaces(matching query: String) async throws -> [PlaceDraft] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return []
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]

        let response = try await MKLocalSearch(request: request).start()
        var seenKeys = Set<String>()

        return response.mapItems.compactMap { mapItem in
            let place = Self.placeDraft(from: mapItem.placemark)
            let key = [
                place.displayTitle,
                place.displaySubtitle ?? "",
                place.latitude.map { String(format: "%.5f", $0) } ?? "",
                place.longitude.map { String(format: "%.5f", $0) } ?? ""
            ].joined(separator: "|")

            guard seenKeys.insert(key).inserted else {
                return nil
            }

            return place
        }
    }

    func currentLocationPlace() async throws -> PlaceDraft {
        guard CLLocationManager.locationServicesEnabled() else {
            throw PermissionCoordinatorError.locationServicesDisabled
        }

        let authorizationStatus = currentLocationManager?.authorizationStatus ?? CLLocationManager().authorizationStatus
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            throw LocationSuggestionError.locationPermissionRequired
        }

        if currentLocationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            desiredAccuracy(manager)
            currentLocationManager = manager
        }

        let location = try await withCheckedThrowingContinuation { continuation in
            currentLocationContinuation = continuation
            currentLocationManager?.requestLocation()
        }

        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        if let placemark = placemarks?.first {
            return Self.placeDraft(from: placemark)
        }

        return PlaceDraft(
            title: "Current location",
            locality: nil,
            country: nil,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last,
              let continuation = currentLocationContinuation else {
            return
        }

        currentLocationContinuation = nil
        continuation.resume(returning: location)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        guard let continuation = currentLocationContinuation else {
            return
        }

        currentLocationContinuation = nil
        continuation.resume(throwing: error)
    }

    private func desiredAccuracy(_ manager: CLLocationManager) {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    private static func placeDraft(from placemark: CLPlacemark) -> PlaceDraft {
        let coordinate = placemark.location?.coordinate
        return PlaceDraft(
            title: placemark.name ?? placemark.locality ?? placemark.country ?? "Unnamed place",
            locality: placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea,
            country: placemark.country,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude
        )
    }
}

struct PreviewPermissionCoordinator: PermissionCoordinating {
    func status(for permission: AppPermission) async -> PermissionStatus {
        .authorized
    }

    func requestAccess(for permission: AppPermission) async -> PermissionStatus {
        .authorized
    }
}

struct PreviewPhotoImportService: PhotoImporting {
    func importPhotoLibraryItem(_ item: PhotosPickerItem) async throws -> ImportedPhoto {
        throw PhotoImportError.unreadableImage
    }

    func importCameraCapture(_ capture: CameraCapture) async throws -> ImportedPhoto {
        throw PhotoImportError.unreadableImage
    }
}

struct PreviewLocationSuggestionService: LocationSuggesting {
    func suggestedPlace(for location: ImportedPhotoLocation) async -> PlaceDraft? {
        PlaceDraft(
            title: "Preview Place",
            locality: "Preview City",
            country: "Preview Country",
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    func searchPlaces(matching query: String) async throws -> [PlaceDraft] {
        guard !query.isEmpty else {
            return []
        }

        return [
            PlaceDraft(
                title: query,
                locality: "Preview City",
                country: "Preview Country",
                latitude: nil,
                longitude: nil
            )
        ]
    }

    func currentLocationPlace() async throws -> PlaceDraft {
        PlaceDraft(
            title: "Current location",
            locality: "Preview City",
            country: "Preview Country",
            latitude: 40.7128,
            longitude: -74.0060
        )
    }
}

private struct ImportedPhotoMetadata {
    var capturedAt: Date?
    var location: ImportedPhotoLocation?
}

private struct NormalizedImage {
    var displayImageData: Data
    var thumbnailData: Data
    var pixelWidth: Int32
    var pixelHeight: Int32
}
