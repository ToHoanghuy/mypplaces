import XCTest
import SwiftData
@testable import MyPlaces

final class OutboxTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    
    override func setUp() async throws {
        let schema = Schema([
            OutboxOperation.self,
            LocalPlace.self
        ])
        
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        
        modelContainer = try ModelContainer(
            for: schema,
            configurations: [config]
        )
        
        modelContext = ModelContext(modelContainer)
    }
    
    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
    }
    
    func testOutboxOperationCreation() throws {
        let resourceID = UUID()
        let operation = OutboxOperation(
            operationType: .create,
            resourceType: .place,
            resourceID: resourceID
        )
        
        XCTAssertEqual(operation.operationType, OutboxOperation.OperationType.create.rawValue)
        XCTAssertEqual(operation.resourceType, OutboxOperation.ResourceType.place.rawValue)
        XCTAssertEqual(operation.resourceID, resourceID)
        XCTAssertEqual(operation.attemptCount, 0)
        XCTAssertEqual(operation.maxAttempts, 5)
        XCTAssertEqual(operation.state, OutboxOperation.OperationState.pending.rawValue)
        XCTAssertNil(operation.lastAttemptAt)
        XCTAssertNil(operation.nextRetryAt)
    }
    
    func testOutboxOperationWithPayload() throws {
        let place = Place(
            id: UUID(),
            ownerID: UUID(),
            title: "Test Place",
            category: .cafe,
            latitude: 10.8231,
            longitude: 106.6297
        )
        
        let payload = try JSONEncoder().encode(place)
        
        let operation = OutboxOperation(
            operationType: .create,
            resourceType: .place,
            resourceID: place.id,
            payload: payload
        )
        
        XCTAssertNotNil(operation.payload)
        
        let decodedPlace = try JSONDecoder().decode(Place.self, from: operation.payload!)
        XCTAssertEqual(decodedPlace.id, place.id)
        XCTAssertEqual(decodedPlace.title, place.title)
    }
    
    func testOutboxOperationStates() throws {
        let operation = OutboxOperation(
            operationType: .update,
            resourceType: .place,
            resourceID: UUID()
        )
        
        XCTAssertEqual(operation.state, OutboxOperation.OperationState.pending.rawValue)
        
        operation.state = OutboxOperation.OperationState.processing.rawValue
        XCTAssertEqual(operation.state, OutboxOperation.OperationState.processing.rawValue)
        
        operation.state = OutboxOperation.OperationState.completed.rawValue
        XCTAssertEqual(operation.state, OutboxOperation.OperationState.completed.rawValue)
        
        operation.state = OutboxOperation.OperationState.failed.rawValue
        XCTAssertEqual(operation.state, OutboxOperation.OperationState.failed.rawValue)
    }
    
    func testOutboxAttemptTracking() throws {
        let operation = OutboxOperation(
            operationType: .create,
            resourceType: .place,
            resourceID: UUID()
        )
        
        modelContext.insert(operation)
        try modelContext.save()
        
        operation.attemptCount += 1
        operation.lastAttemptAt = Date()
        
        XCTAssertEqual(operation.attemptCount, 1)
        XCTAssertNotNil(operation.lastAttemptAt)
        
        operation.attemptCount += 1
        XCTAssertEqual(operation.attemptCount, 2)
        XCTAssertTrue(operation.attemptCount < operation.maxAttempts)
    }
    
    func testOutboxRetryLogic() throws {
        let operation = OutboxOperation(
            operationType: .create,
            resourceType: .place,
            resourceID: UUID(),
            maxAttempts: 3
        )
        
        modelContext.insert(operation)
        try modelContext.save()
        
        for attempt in 1...operation.maxAttempts {
            operation.attemptCount = attempt
            operation.lastAttemptAt = Date()
            operation.nextRetryAt = Date().addingTimeInterval(pow(2.0, Double(attempt)) * 4.0)
        }
        
        XCTAssertEqual(operation.attemptCount, operation.maxAttempts)
        XCTAssertNotNil(operation.nextRetryAt)
    }
    
    func testSyncStateTransitions() throws {
        let place = LocalPlace(
            id: UUID(),
            ownerID: UUID(),
            title: "Test Place",
            category: PlaceCategory.other.rawValue,
            latitude: 0,
            longitude: 0,
            syncState: SyncState.pending.rawValue
        )
        
        modelContext.insert(place)
        try modelContext.save()
        
        XCTAssertEqual(place.syncState, SyncState.pending.rawValue)
        
        place.syncState = SyncState.syncing.rawValue
        XCTAssertEqual(place.syncState, SyncState.syncing.rawValue)
        
        place.syncState = SyncState.synced.rawValue
        XCTAssertEqual(place.syncState, SyncState.synced.rawValue)
        
        place.syncState = SyncState.failedRetryable.rawValue
        XCTAssertEqual(place.syncState, SyncState.failedRetryable.rawValue)
    }
    
    func testMultipleOperationsOrdering() throws {
        let place1ID = UUID()
        let place2ID = UUID()
        
        let op1 = OutboxOperation(
            operationType: .create,
            resourceType: .place,
            resourceID: place1ID
        )
        
        Thread.sleep(forTimeInterval: 0.01)
        
        let op2 = OutboxOperation(
            operationType: .update,
            resourceType: .place,
            resourceID: place2ID
        )
        
        modelContext.insert(op1)
        modelContext.insert(op2)
        try modelContext.save()
        
        let descriptor = FetchDescriptor<OutboxOperation>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        let operations = try modelContext.fetch(descriptor)
        
        XCTAssertEqual(operations.count, 2)
        XCTAssertTrue(operations[0].createdAt <= operations[1].createdAt)
    }
    
    func testOperationFiltering() throws {
        let placeOp = OutboxOperation(
            operationType: .create,
            resourceType: .place,
            resourceID: UUID()
        )
        
        let journalOp = OutboxOperation(
            operationType: .create,
            resourceType: .journal,
            resourceID: UUID()
        )
        
        modelContext.insert(placeOp)
        modelContext.insert(journalOp)
        try modelContext.save()
        
        let descriptor = FetchDescriptor<OutboxOperation>(
            predicate: #Predicate { $0.resourceType == "PLACE" }
        )
        
        let placeOperations = try modelContext.fetch(descriptor)
        
        XCTAssertEqual(placeOperations.count, 1)
        XCTAssertEqual(placeOperations[0].resourceType, OutboxOperation.ResourceType.place.rawValue)
    }
}
