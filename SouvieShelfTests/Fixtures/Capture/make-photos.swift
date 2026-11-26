// Run with swift make-photos.swift OUTPUT_DIRECTORY, then add the JPEGs with simctl addmedia.
import Foundation
import ImageIO
import UniformTypeIdentifiers

let sourceFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Gallery")
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func write(_ file: String, date: String? = nil, latitude: Double = 0, longitude: Double = 0) throws {
    let source = sourceFolder.appendingPathComponent(file + ".jpg")
    let target = output.appendingPathComponent(file + ".jpg")
    guard let reader = CGImageSourceCreateWithURL(source as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(reader, 0, nil),
          let writer = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileReadCorruptFile) }
    var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
    if let date {
        properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: date]
        properties[kCGImagePropertyGPSDictionary] = [
            kCGImagePropertyGPSLatitude: abs(latitude), kCGImagePropertyGPSLatitudeRef: latitude < 0 ? "S" : "N",
            kCGImagePropertyGPSLongitude: abs(longitude), kCGImagePropertyGPSLongitudeRef: longitude < 0 ? "W" : "E"
        ]
    }
    CGImageDestinationAddImage(writer, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
}

try write("plate", date: "2025:05:18 12:00:00", latitude: 40.6491, longitude: 14.6115)
try write("octopus", date: "2026:02:14 12:00:00", latitude: 40.7128, longitude: -74.0060)
try write("camel")
