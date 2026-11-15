import Foundation
import SwiftData
import Supabase
import Combine

@Observable
final class PlaceRepository {
    private let supabase: SupabaseClient
    private let modelContext: ModelContext
    private var syncTimer: Timer?
    
    var places: [Place] = []
    var isLoading = false
    var error: Error?
    
    init(
        supabase: SupabaseClient = SupabaseService.shared.client,
        modelContext: ModelContext
    ) {
        self.supabase = supabase
        self.modelContext = modelContext
        startSyncTimer()
    }
    
    deinit {
        syncTimer?.invalidate()
    }
    
    func loadPlaces() async throws {
        await MainActor.run { isLoading = true }
        
        do {
            let fetchedPlaces: [Place] = try await supabase.database
                .from("places")
                .select()
                .is("deleted_at", value: "null")
                .order("created_at", ascending: false)
                .execute()
                .value
            
            await MainActor.run {
                self.places = fetchedPlaces
                self.isLoading = false
            }
            
            syncToLocal(places: fetchedPlaces)
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            loadFromLocal()
            throw error
        }
    }
    
    func createPlace(_ place: Place) async throws {
        let localPlace = LocalPlace.fromDomain(place, syncState: .pending)
        modelContext.insert(localPlace)
        try modelContext.save()
        
        let operation = OutboxOperation(
            operationType: .create,
            resourceType: .place,
            resourceID: place.id,
            payload: try? JSONEncoder().encode(place)
        )
        modelContext.insert(operation)
        try modelContext.save()
        
        await MainActor.run {
            if let index = places.firstIndex(where: { $0.id == place.id }) {
                places[index] = place
            } else {
                places.insert(place, at: 0)
            }
        }
        
        Task {
            await syncPendingOperations()
        }
    }
    
    func updatePlace(_ place: Place) async throws {
        guard let localPlace = try modelContext.fetch(
            FetchDescriptor<LocalPlace>(
                predicate: #Predicate { $0.id == place.id }
            )
        ).first else {
            throw PlaceError.notFound
        }
        
        localPlace.title = place.title
        localPlace.category = place.category.rawValue
        localPlace.latitude = place.latitude
        localPlace.longitude = place.longitude
        localPlace.address = place.address
        localPlace.note = place.note
        localPlace.visitedAt = place.visitedAt
        localPlace.updatedAt = Date()
        localPlace.syncState = SyncState.pending.rawValue
        
        try modelContext.save()
        
        let operation = OutboxOperation(
            operationType: .update,
            resourceType: .place,
            resourceID: place.id,
            payload: try? JSONEncoder().encode(place)
        )
        modelContext.insert(operation)
        try modelContext.save()
        
        await MainActor.run {
            if let index = places.firstIndex(where: { $0.id == place.id }) {
                places[index] = place
            }
        }
        
        Task {
            await syncPendingOperations()
        }
    }
    
    func deletePlace(_ placeID: UUID) async throws {
        guard let localPlace = try modelContext.fetch(
            FetchDescriptor<LocalPlace>(
                predicate: #Predicate { $0.id == placeID }
            )
        ).first else {
            throw PlaceError.notFound
        }
        
        localPlace.deletedAt = Date()
        localPlace.syncState = SyncState.pending.rawValue
        try modelContext.save()
        
        let operation = OutboxOperation(
            operationType: .delete,
            resourceType: .place,
            resourceID: placeID
        )
        modelContext.insert(operation)
        try modelContext.save()
        
        await MainActor.run {
            places.removeAll { $0.id == placeID }
        }
        
        Task {
            await syncPendingOperations()
        }
    }
    
    func syncPendingOperations() async {
        let descriptor = FetchDescriptor<OutboxOperation>(
            predicate: #Predicate { operation in
                operation.state == "PENDING" && operation.resourceType == "PLACE"
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        guard let operations = try? modelContext.fetch(descriptor) else {
            return
        }
        
        for operation in operations {
            await syncOperation(operation)
        }
    }
    
    private func syncOperation(_ operation: OutboxOperation) async {
        operation.state = OutboxOperation.OperationState.processing.rawValue
        operation.attemptCount += 1
        operation.lastAttemptAt = Date()
        
        do {
            try modelContext.save()
            
            guard let payload = operation.payload,
                  let place = try? JSONDecoder().decode(Place.self, from: payload) else {
                operation.state = OutboxOperation.OperationState.failed.rawValue
                operation.errorMessage = "Invalid payload"
                try? modelContext.save()
                return
            }
            
            switch OutboxOperation.OperationType(rawValue: operation.operationType) {
            case .create:
                try await createPlaceRemote(place)
            case .update:
                try await updatePlaceRemote(place)
            case .delete:
                try await deletePlaceRemote(place.id)
            case .none:
                break
            }
            
            operation.state = OutboxOperation.OperationState.completed.rawValue
            
            if let localPlace = try modelContext.fetch(
                FetchDescriptor<LocalPlace>(
                    predicate: #Predicate { $0.id == place.id }
                )
            ).first {
                localPlace.syncState = SyncState.synced.rawValue
                localPlace.syncError = nil
            }
            
            try modelContext.save()
        } catch {
            operation.errorMessage = error.localizedDescription
            
            if operation.attemptCount >= operation.maxAttempts {
                operation.state = OutboxOperation.OperationState.failed.rawValue
                
                if let localPlace = try? modelContext.fetch(
                    FetchDescriptor<LocalPlace>(
                        predicate: #Predicate { $0.id == operation.resourceID }
                    )
                ).first {
                    localPlace.syncState = SyncState.failedFinal.rawValue
                    localPlace.syncError = error.localizedDescription
                }
            } else {
                operation.state = OutboxOperation.OperationState.pending.rawValue
                operation.nextRetryAt = Date().addingTimeInterval(
                    pow(2.0, Double(operation.attemptCount)) * 4.0
                )
                
                if let localPlace = try? modelContext.fetch(
                    FetchDescriptor<LocalPlace>(
                        predicate: #Predicate { $0.id == operation.resourceID }
                    )
                ).first {
                    localPlace.syncState = SyncState.failedRetryable.rawValue
                    localPlace.syncError = error.localizedDescription
                }
            }
            
            try? modelContext.save()
        }
    }
    
    private func createPlaceRemote(_ place: Place) async throws {
        let placeDict: [String: Any] = [
            "id": place.id.uuidString,
            "owner_id": place.ownerID.uuidString,
            "title": place.title,
            "category": place.category.rawValue,
            "latitude": place.latitude,
            "longitude": place.longitude,
            "address": place.address as Any,
            "note": place.note as Any,
            "visited_at": place.visitedAt?.iso8601String as Any,
            "created_at": place.createdAt.iso8601String,
            "updated_at": place.updatedAt.iso8601String
        ]
        
        try await supabase.database
            .from("places")
            .insert(placeDict)
            .execute()
    }
    
    private func updatePlaceRemote(_ place: Place) async throws {
        let updates: [String: Any] = [
            "title": place.title,
            "category": place.category.rawValue,
            "latitude": place.latitude,
            "longitude": place.longitude,
            "address": place.address as Any,
            "note": place.note as Any,
            "visited_at": place.visitedAt?.iso8601String as Any,
            "updated_at": Date().iso8601String
        ]
        
        try await supabase.database
            .from("places")
            .update(updates)
            .eq("id", value: place.id.uuidString)
            .execute()
    }
    
    private func deletePlaceRemote(_ placeID: UUID) async throws {
        let updates: [String: Any] = [
            "deleted_at": Date().iso8601String
        ]
        
        try await supabase.database
            .from("places")
            .update(updates)
            .eq("id", value: placeID.uuidString)
            .execute()
    }
    
    private func syncToLocal(places: [Place]) {
        for place in places {
            let descriptor = FetchDescriptor<LocalPlace>(
                predicate: #Predicate { $0.id == place.id }
            )
            
            if let existingPlace = try? modelContext.fetch(descriptor).first {
                existingPlace.title = place.title
                existingPlace.category = place.category.rawValue
                existingPlace.latitude = place.latitude
                existingPlace.longitude = place.longitude
                existingPlace.address = place.address
                existingPlace.note = place.note
                existingPlace.visitedAt = place.visitedAt
                existingPlace.updatedAt = place.updatedAt
                existingPlace.deletedAt = place.deletedAt
                existingPlace.syncState = SyncState.synced.rawValue
            } else {
                let localPlace = LocalPlace.fromDomain(place, syncState: .synced)
                modelContext.insert(localPlace)
            }
        }
        
        try? modelContext.save()
    }
    
    private func loadFromLocal() {
        let descriptor = FetchDescriptor<LocalPlace>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        if let localPlaces = try? modelContext.fetch(descriptor) {
            Task { @MainActor in
                self.places = localPlaces.map { $0.toDomain() }
            }
        }
    }
    
    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                await self?.syncPendingOperations()
            }
        }
    }
}

enum PlaceError: LocalizedError {
    case notFound
    case syncFailed
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Không tìm thấy địa điểm"
        case .syncFailed:
            return "Đồng bộ không thành công"
        }
    }
}

extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
