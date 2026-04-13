//
//  Souvenir+CoreDataProperties.swift
//  
//
//  Created by Jon Galante on 4/13/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias SouvenirCoreDataPropertiesSet = NSSet

extension Souvenir {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Souvenir> {
        return NSFetchRequest<Souvenir>(entityName: "Souvenir")
    }

    @NSManaged public var acquiredDate: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var fromCity: String?
    @NSManaged public var fromCountryCode: String?
    @NSManaged public var fromLatitude: Double
    @NSManaged public var fromLongitude: Double
    @NSManaged public var fromName: String?
    @NSManaged public var gotItInCity: String?
    @NSManaged public var gotItInCountryCode: String?
    @NSManaged public var gotItInLatitude: Double
    @NSManaged public var gotItInLongitude: Double
    @NSManaged public var gotItInName: String?
    @NSManaged public var id: UUID?
    @NSManaged public var story: String?
    @NSManaged public var title: String?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var library: Library?
    @NSManaged public var photos: NSSet?
    @NSManaged public var trip: Trip?

}

// MARK: Generated accessors for photos
extension Souvenir {

    @objc(addPhotosObject:)
    @NSManaged public func addToPhotos(_ value: PhotoAsset)

    @objc(removePhotosObject:)
    @NSManaged public func removeFromPhotos(_ value: PhotoAsset)

    @objc(addPhotos:)
    @NSManaged public func addToPhotos(_ values: NSSet)

    @objc(removePhotos:)
    @NSManaged public func removeFromPhotos(_ values: NSSet)

}

extension Souvenir : Identifiable {

}
