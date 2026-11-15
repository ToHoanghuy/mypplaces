import XCTest
import SwiftData
@testable import MyPlaces

final class ModelMappingTests: XCTestCase {
    
    func testPlaceToDomainMapping() throws {
        let placeID = UUID()
        let ownerID = UUID()
        
        let localPlace = LocalPlace(
            id: placeID,
            ownerID: ownerID,
            title: "Test Place",
            category: PlaceCategory.cafe.rawValue,
            latitude: 10.8231,
            longitude: 106.6297,
            address: "Ho Chi Minh City",
            note: "Great coffee",
            visitedAt: Date(),
            syncState: SyncState.synced.rawValue
        )
        
        let domainPlace = localPlace.toDomain()
        
        XCTAssertEqual(domainPlace.id, placeID)
        XCTAssertEqual(domainPlace.ownerID, ownerID)
        XCTAssertEqual(domainPlace.title, "Test Place")
        XCTAssertEqual(domainPlace.category, .cafe)
        XCTAssertEqual(domainPlace.latitude, 10.8231)
        XCTAssertEqual(domainPlace.longitude, 106.6297)
        XCTAssertEqual(domainPlace.address, "Ho Chi Minh City")
        XCTAssertEqual(domainPlace.note, "Great coffee")
        XCTAssertNotNil(domainPlace.visitedAt)
    }
    
    func testPlaceFromDomainMapping() throws {
        let placeID = UUID()
        let ownerID = UUID()
        let visitedAt = Date()
        
        let domainPlace = Place(
            id: placeID,
            ownerID: ownerID,
            title: "Test Place",
            category: .food,
            latitude: 10.8231,
            longitude: 106.6297,
            address: "Test Address",
            note: "Test Note",
            visitedAt: visitedAt
        )
        
        let localPlace = LocalPlace.fromDomain(domainPlace, syncState: .pending)
        
        XCTAssertEqual(localPlace.id, placeID)
        XCTAssertEqual(localPlace.ownerID, ownerID)
        XCTAssertEqual(localPlace.title, "Test Place")
        XCTAssertEqual(localPlace.category, PlaceCategory.food.rawValue)
        XCTAssertEqual(localPlace.latitude, 10.8231)
        XCTAssertEqual(localPlace.longitude, 106.6297)
        XCTAssertEqual(localPlace.address, "Test Address")
        XCTAssertEqual(localPlace.note, "Test Note")
        XCTAssertEqual(localPlace.visitedAt, visitedAt)
        XCTAssertEqual(localPlace.syncState, SyncState.pending.rawValue)
    }
    
    func testPlaceRoundTripMapping() throws {
        let originalPlace = Place(
            id: UUID(),
            ownerID: UUID(),
            title: "Round Trip Test",
            category: .travel,
            latitude: 10.7769,
            longitude: 106.7009,
            address: "Test Address",
            note: "Test Note",
            visitedAt: Date()
        )
        
        let localPlace = LocalPlace.fromDomain(originalPlace)
        let mappedPlace = localPlace.toDomain()
        
        XCTAssertEqual(mappedPlace.id, originalPlace.id)
        XCTAssertEqual(mappedPlace.ownerID, originalPlace.ownerID)
        XCTAssertEqual(mappedPlace.title, originalPlace.title)
        XCTAssertEqual(mappedPlace.category, originalPlace.category)
        XCTAssertEqual(mappedPlace.latitude, originalPlace.latitude)
        XCTAssertEqual(mappedPlace.longitude, originalPlace.longitude)
        XCTAssertEqual(mappedPlace.address, originalPlace.address)
        XCTAssertEqual(mappedPlace.note, originalPlace.note)
    }
    
    func testPlaceCategoryMapping() throws {
        for category in PlaceCategory.allCases {
            let place = Place(
                id: UUID(),
                ownerID: UUID(),
                title: "Test",
                category: category,
                latitude: 0,
                longitude: 0
            )
            
            let localPlace = LocalPlace.fromDomain(place)
            let mappedPlace = localPlace.toDomain()
            
            XCTAssertEqual(mappedPlace.category, category, "Category \(category) should map correctly")
        }
    }
    
    func testPlaceOptionalFields() throws {
        let place = Place(
            id: UUID(),
            ownerID: UUID(),
            title: "Minimal Place",
            category: .other,
            latitude: 0,
            longitude: 0,
            address: nil,
            note: nil,
            visitedAt: nil
        )
        
        let localPlace = LocalPlace.fromDomain(place)
        let mappedPlace = localPlace.toDomain()
        
        XCTAssertNil(mappedPlace.address)
        XCTAssertNil(mappedPlace.note)
        XCTAssertNil(mappedPlace.visitedAt)
    }
    
    func testLatitudeLongitudeValidation() throws {
        let validPlace = Place(
            id: UUID(),
            ownerID: UUID(),
            title: "Valid Coordinates",
            category: .other,
            latitude: 45.0,
            longitude: -122.0
        )
        
        XCTAssertTrue((-90...90).contains(validPlace.latitude))
        XCTAssertTrue((-180...180).contains(validPlace.longitude))
    }
}
