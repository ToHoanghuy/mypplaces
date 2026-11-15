import Foundation
import SwiftData

@Observable
final class PlaceListViewModel {
    var places: [Place] = []
    var selectedCategory: PlaceCategory?
    var searchText = ""
    var isLoading = false
    var showingCreateSheet = false
    
    private let placeRepository: PlaceRepository
    
    init(modelContext: ModelContext) {
        self.placeRepository = PlaceRepository(modelContext: modelContext)
        Task {
            await loadPlaces()
        }
    }
    
    func loadPlaces() async {
        isLoading = true
        do {
            try await placeRepository.loadPlaces()
            await MainActor.run {
                places = placeRepository.places
                isLoading = false
            }
        } catch {
            print("Failed to load places: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    func deletePlace(_ place: Place) async {
        do {
            try await placeRepository.deletePlace(place.id)
            await loadPlaces()
        } catch {
            print("Failed to delete place: \(error)")
        }
    }
    
    var filteredPlaces: [Place] {
        var result = places
        
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.address?.lowercased().contains(query) == true ||
                $0.note?.lowercased().contains(query) == true
            }
        }
        
        return result
    }
    
    func groupedPlaces() -> [(PlaceCategory, [Place])] {
        let grouped = Dictionary(grouping: filteredPlaces) { $0.category }
        return grouped.map { ($0.key, $0.value) }
            .sorted { $0.0.displayName < $1.0.displayName }
    }
}
