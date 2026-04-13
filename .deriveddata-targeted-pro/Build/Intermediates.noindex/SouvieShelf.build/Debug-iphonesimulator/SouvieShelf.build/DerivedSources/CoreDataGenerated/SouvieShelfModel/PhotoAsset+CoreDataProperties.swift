//
//  PhotoAsset+CoreDataProperties.swift
//  
//
//  Created by Jon Galante on 4/13/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias PhotoAssetCoreDataPropertiesSet = NSSet

extension PhotoAsset {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PhotoAsset> {
        return NSFetchRequest<PhotoAsset>(entityName: "PhotoAsset")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var displayImageData: Data?
    @NSManaged public var id: UUID?
    @NSManaged public var isPrimary: Bool
    @NSManaged public var pixelHeight: Int32
    @NSManaged public var pixelWidth: Int32
    @NSManaged public var sortIndex: Int16
    @NSManaged public var thumbnailData: Data?
    @NSManaged public var souvenir: Souvenir?

}

extension PhotoAsset : Identifiable {

}
