import Foundation
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "GoalAvatar" asset catalog image resource.
    static let goalAvatar = DeveloperToolsSupport.ImageResource(name: "GoalAvatar", bundle: resourceBundle)

    /// The "GoalBottle" asset catalog image resource.
    static let goalBottle = DeveloperToolsSupport.ImageResource(name: "GoalBottle", bundle: resourceBundle)

    /// The "GoalBowl" asset catalog image resource.
    static let goalBowl = DeveloperToolsSupport.ImageResource(name: "GoalBowl", bundle: resourceBundle)

    /// The "GoalCamel" asset catalog image resource.
    static let goalCamel = DeveloperToolsSupport.ImageResource(name: "GoalCamel", bundle: resourceBundle)

    /// The "GoalKyoto" asset catalog image resource.
    static let goalKyoto = DeveloperToolsSupport.ImageResource(name: "GoalKyoto", bundle: resourceBundle)

    /// The "GoalLantern" asset catalog image resource.
    static let goalLantern = DeveloperToolsSupport.ImageResource(name: "GoalLantern", bundle: resourceBundle)

    /// The "GoalMug" asset catalog image resource.
    static let goalMug = DeveloperToolsSupport.ImageResource(name: "GoalMug", bundle: resourceBundle)

    /// The "GoalPlate" asset catalog image resource.
    static let goalPlate = DeveloperToolsSupport.ImageResource(name: "GoalPlate", bundle: resourceBundle)

    /// The "GoalPouch" asset catalog image resource.
    static let goalPouch = DeveloperToolsSupport.ImageResource(name: "GoalPouch", bundle: resourceBundle)

    /// The "GoalRecentTripAmalfi" asset catalog image resource.
    static let goalRecentTripAmalfi = DeveloperToolsSupport.ImageResource(name: "GoalRecentTripAmalfi", bundle: resourceBundle)

    /// The "GoalRugs" asset catalog image resource.
    static let goalRugs = DeveloperToolsSupport.ImageResource(name: "GoalRugs", bundle: resourceBundle)

    /// The "SouvieShelfMark" asset catalog image resource.
    static let souvieShelfMark = DeveloperToolsSupport.ImageResource(name: "SouvieShelfMark", bundle: resourceBundle)

}

