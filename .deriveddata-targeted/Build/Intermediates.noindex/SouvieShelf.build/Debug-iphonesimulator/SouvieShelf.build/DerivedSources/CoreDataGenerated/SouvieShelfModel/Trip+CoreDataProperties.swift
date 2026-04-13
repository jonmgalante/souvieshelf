//
//  Trip+CoreDataProperties.swift
//  
//
//  Created by Jon Galante on 4/13/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias TripCoreDataPropertiesSet = NSSet

extension Trip {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Trip> {
        return NSFetchRequest<Trip>(entityName: "Trip")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var destinationSummary: String?
    @NSManaged public var endDate: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var startDate: Date?
    @NSManaged public var title: String?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var library: Library?
    @NSManaged public var souvenirs: NSSet?

}

// MARK: Generated accessors for souvenirs
extension Trip {

    @objc(addSouvenirsObject:)
    @NSManaged public func addToSouvenirs(_ value: Souvenir)

    @objc(removeSouvenirsObject:)
    @NSManaged public func removeFromSouvenirs(_ value: Souvenir)

    @objc(addSouvenirs:)
    @NSManaged public func addToSouvenirs(_ values: NSSet)

    @objc(removeSouvenirs:)
    @NSManaged public func removeFromSouvenirs(_ values: NSSet)

}

extension Trip : Identifiable {

}
