import Foundation
import SwiftData

@Model
final class OutboxOperation {
    @Attribute(.unique) var id: UUID
    var operationType: String
    var resourceType: String
    var resourceID: UUID
    var payload: Data?
    var attemptCount: Int
    var maxAttempts: Int
    var state: String
    var errorMessage: String?
    var createdAt: Date
    var lastAttemptAt: Date?
    var nextRetryAt: Date?
    
    init(
        id: UUID = UUID(),
        operationType: OperationType,
        resourceType: ResourceType,
        resourceID: UUID,
        payload: Data? = nil,
        maxAttempts: Int = 5,
        state: OperationState = .pending
    ) {
        self.id = id
        self.operationType = operationType.rawValue
        self.resourceType = resourceType.rawValue
        self.resourceID = resourceID
        self.payload = payload
        self.attemptCount = 0
        self.maxAttempts = maxAttempts
        self.state = state.rawValue
        self.createdAt = Date()
    }
    
    enum OperationType: String, Codable {
        case create = "CREATE"
        case update = "UPDATE"
        case delete = "DELETE"
    }
    
    enum ResourceType: String, Codable {
        case place = "PLACE"
        case journal = "JOURNAL"
    }
    
    enum OperationState: String, Codable {
        case pending = "PENDING"
        case processing = "PROCESSING"
        case completed = "COMPLETED"
        case failed = "FAILED"
    }
}
