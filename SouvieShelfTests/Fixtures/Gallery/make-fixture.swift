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

func makePackage(app: URL, output: URL, name: String) throws {
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
    if name != "Empty" {
        let revisit = name == "Trips"
        let titles = revisit ? ["Amalfi Coast", "Morocco", "Kyoto in spring"] : ["Amalfi Coast", "Morocco"]
        let trips = titles.enumerated().map { index, title in
            insert("Trip", 10 + index, values: ["title": title, "library": library])
        }
        let calendar = Calendar.current
        let anniversary = calendar.date(byAdding: .year, value: -4, to: Date.now)!
        if revisit {
            trips[0].setValuesForKeys(["destinationSummary": "Ravello and Positano, Italy",
                                       "startDate": calendar.date(byAdding: .day, value: -3, to: anniversary)!,
                                       "endDate": calendar.date(byAdding: .day, value: 2, to: anniversary)!])
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
            if revisit {
                switch index {
                case 0:
                    object.setValuesForKeys(["gotItInLatitude": 40.6491, "gotItInLongitude": 14.6115,
                                             "acquiredDate": anniversary])
                case 1:
                    object.setValuesForKeys(["gotItInLatitude": 40.6280, "gotItInLongitude": 14.4850,
                                             "acquiredDate": calendar.date(byAdding: .day, value: -1, to: anniversary)!])
                case 3:
                    for key in ["gotItInCity", "gotItInCountryCode", "acquiredDate"] { object.setValue(nil, forKey: key) }
                case 4...6:
                    object.setValue(nil, forKey: "trip")
                default: break
                }
                if index == 2 || (4...6).contains(index) {
                    object.setValue(calendar.date(byAdding: .day, value: -12, to: anniversary), forKey: "acquiredDate")
                }
            }
            if let url = sample.image {
                let (display, image) = try jpeg(url, maxSide: 900)
                let thumb = try jpeg(url, maxSide: 320).0
                _ = insert("PhotoAsset", 40 + index, values: ["souvenir": object, "isPrimary": true,
                    "displayImageData": display, "thumbnailData": thumb, "pixelWidth": image.width, "pixelHeight": image.height])
                if revisit, index == 0 {
                    // A second saved photo of the same object, showing the glaze and arms in detail.
                    let part = CGRect(x: image.width / 4, y: image.height / 2,
                                      width: image.width / 2, height: image.height / 3)
                    let detail = image.cropping(to: part)!
                    let bytes = NSMutableData()
                    let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)!
                    CGImageDestinationAddImage(destination, detail, nil)
                    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
                    _ = insert("PhotoAsset", 60, values: ["souvenir": object, "sortIndex": 1,
                        "displayImageData": bytes as Data, "pixelWidth": detail.width, "pixelHeight": detail.height])
                }
            }
        }
        if revisit {
            for (offset, title) in ["Amalfi ferry ticket", "Postcard from Atrani", "Sea-glass pebble", "Handwritten recipe"].enumerated() {
                _ = insert("Souvenir", 70 + offset, values: ["title": title, "trip": trips[0], "library": library])
            }
        }
    }
    try context.save()
    try coordinator.remove(store)
    try files.moveItem(at: scratch, to: package)
    print(package.path)
}
precondition(CommandLine.arguments.count == 4, "Usage: swift make-fixture.swift <simulator.app> <output directory> <empty|populated|trips>")
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
switch CommandLine.arguments[3] {
case "empty", "populated", "trips":
    try makePackage(app: app, output: output, name: CommandLine.arguments[3].capitalized)
default: fatalError("Choose empty, populated, or trips")
}
