//
//  Library+CoreDataProperties.swift
//  
//
//  Created by Jon Galante on 4/13/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias LibraryCoreDataPropertiesSet = NSSet

extension Library {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Library> {
        return NSFetchRequest<Library>(entityName: "Library")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var souvenirs: NSSet?
    @NSManaged public var trips: NSSet?

}

// MARK: Generated accessors for souvenirs
extension Library {

    @objc(addSouvenirsObject:)
    @NSManaged public func addToSouvenirs(_ value: Souvenir)

    @objc(removeSouvenirsObject:)
    @NSManaged public func removeFromSouvenirs(_ value: Souvenir)

    @objc(addSouvenirs:)
    @NSManaged public func addToSouvenirs(_ values: NSSet)

    @objc(removeSouvenirs:)
    @NSManaged public func removeFromSouvenirs(_ values: NSSet)

}

// MARK: Generated accessors for trips
extension Library {

    @objc(addTripsObject:)
    @NSManaged public func addToTrips(_ value: Trip)

    @objc(removeTripsObject:)
    @NSManaged public func removeFromTrips(_ value: Trip)

    @objc(addTrips:)
    @NSManaged public func addToTrips(_ values: NSSet)

    @objc(removeTrips:)
    @NSManaged public func removeFromTrips(_ values: NSSet)

}

extension Library : Identifiable {

}
