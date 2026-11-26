// Run on macOS with the built simulator .app and a fresh output directory as arguments.
// Produces synthetic .xcappdata packages without opening an installed app's store.
import CoreData
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Sample {
    let title: String?
    let story: String?
    let place: String?
    let trip: Int?
    let image: URL?
}

let files = FileManager.default
let samplesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let project = samplesDirectory.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let assets = project.appendingPathComponent("App/Media.xcassets")
func catalogImage(_ set: String, _ file: String) -> URL {
    assets.appendingPathComponent("LibraryHome\(set).imageset/\(file).jpg")
}
let samples = [
    Sample(title: "Ceramic octopus", story: "We went back for him after lunch. The potter wrapped each little arm in a scrap of newspaper.", place: "Ravello", trip: 0, image: samplesDirectory.appendingPathComponent("octopus.jpg")),
    Sample(title: "Lemon plate", story: "A little lemon for the kitchen wall.", place: "Positano", trip: 0, image: samplesDirectory.appendingPathComponent("plate.jpg")),
    Sample(title: "Carved camel", story: nil, place: "Marrakesh", trip: 1, image: samplesDirectory.appendingPathComponent("camel.jpg")),
    Sample(title: "Blue coffee cup", story: nil, place: "Ravello", trip: 0, image: catalogImage("Grid01BlueCeramicMug", "grid-01-blue-ceramic-mug")),
    Sample(title: "Woven wool", story: nil, place: "Marrakesh", trip: 1, image: catalogImage("Grid04FoldedRugs", "grid-04-folded-rugs")),
    Sample(title: "Brass lantern", story: nil, place: "Marrakesh", trip: 1, image: catalogImage("Grid06MoroccanLantern", "grid-06-moroccan-lantern")),
    Sample(title: "Painted bowl", story: nil, place: "Marrakesh", trip: 1, image: catalogImage("Grid08SelectedBowl", "grid-08-selected-bowl")),
    Sample(title: nil, story: nil, place: nil, trip: nil, image: nil)
]

func jpeg(_ url: URL, maxSide: Int) throws -> (Data, CGImage) {
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                    kCGImageSourceCreateThumbnailWithTransform: true,
                                    kCGImageSourceThumbnailMaxPixelSize: maxSide]
    guard let source, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
    }
    let bytes = NSMutableData()
    let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return (bytes as Data, image)
}

func makePackage(app: URL, output: URL, populated: Bool) throws {
    let name = populated ? "Populated" : "Empty"
    let package = output.appendingPathComponent("\(name).xcappdata")
    guard !files.fileExists(atPath: package.path) else { throw CocoaError(.fileWriteFileExists) }
    let scratch = output.appendingPathComponent(UUID().uuidString)
    defer { try? files.removeItem(at: scratch) }
    let directory = scratch.appendingPathComponent("AppData/Library/Application Support/SouvieShelf")
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    let info = ["CFBundleIdentifier": "com.example.SouvieShelf", "ApplicationBundleIdentifier": "com.example.SouvieShelf"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: scratch.appendingPathComponent("AppDataInfo.plist"))
    let model = NSManagedObjectModel(contentsOf: app.appendingPathComponent("SouvieShelfModel.momd"))!
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    let store = try coordinator.addPersistentStore(type: .sqlite, configuration: "Private",
        at: directory.appendingPathComponent("SouvieShelf-Private.sqlite"),
        options: [NSPersistentHistoryTrackingKey: true])
    let context = NSManagedObjectContext(.mainQueue)
    context.persistentStoreCoordinator = coordinator
    let date = Date(timeIntervalSince1970: 1_747_742_400)
    func insert(_ entity: String, _ number: Int, values: [String: Any]) -> NSManagedObject {
        let object = NSManagedObject(entity: model.entitiesByName[entity]!, insertInto: context)
        let id = String(format: "A0000000-0000-4000-8000-%012d", number)
        object.setValue(UUID(uuidString: id)!, forKey: "id")
        object.setValue(date.addingTimeInterval(Double(-number)), forKey: "createdAt")
        if entity != "PhotoAsset" { object.setValue(date.addingTimeInterval(Double(-number)), forKey: "updatedAt") }
        object.setValuesForKeys(values)
        return object
    }
    let library = insert("Library", 1, values: ["title": "Our Library"])
    if populated {
        let trips = ["Amalfi Coast", "Morocco"].enumerated().map { index, title in
            insert("Trip", 10 + index, values: ["title": title, "library": library])
        }
        for (index, sample) in samples.enumerated() {
            let object = insert("Souvenir", 20 + index, values: ["library": library])
            object.setValue(sample.title, forKey: "title")
            object.setValue(sample.story, forKey: "story")
            object.setValue(sample.place, forKey: "gotItInCity")
            if let trip = sample.trip {
                object.setValue(trips[trip], forKey: "trip")
                object.setValue(trip == 0 ? "IT" : "MA", forKey: "gotItInCountryCode")
                object.setValue(date, forKey: "acquiredDate")
            }
            if let url = sample.image {
                let (display, image) = try jpeg(url, maxSide: 900)
                let thumb = try jpeg(url, maxSide: 320).0
                _ = insert("PhotoAsset", 40 + index, values: ["souvenir": object, "isPrimary": true,
                    "displayImageData": display, "thumbnailData": thumb, "pixelWidth": image.width, "pixelHeight": image.height])
            }
        }
    }
    try context.save()
    try coordinator.remove(store)
    try files.moveItem(at: scratch, to: package)
    print(package.path)
}
precondition(CommandLine.arguments.count == 4, "Usage: swift make-fixture.swift <simulator.app> <output directory> <empty|populated>")
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
switch CommandLine.arguments[3] {
case "empty": try makePackage(app: app, output: output, populated: false)
case "populated": try makePackage(app: app, output: output, populated: true)
default: fatalError("Choose empty or populated")
}
