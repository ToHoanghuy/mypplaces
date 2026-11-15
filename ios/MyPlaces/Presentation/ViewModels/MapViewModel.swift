import Foundation
import MapKit
import SwiftData

@Observable
final class MapViewModel {
    var places: [Place] = []
    var selectedPlace: Place?
    var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 10.8231, longitude: 106.6297),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    var searchText = ""
    var searchResults: [MKMapItem] = []
    var isSearching = false
    var selectedCategory: PlaceCategory?
    var showingCreateSheet = false
    var newPlaceCoordinate: CLLocationCoordinate2D?
    
    private let placeRepository: PlaceRepository
    private let locationManager = CLLocationManager()
    
    init(modelContext: ModelContext) {
        self.placeRepository = PlaceRepository(modelContext: modelContext)
        Task {
            await loadPlaces()
        }
    }
    
    func loadPlaces() async {
        do {
            try await placeRepository.loadPlaces()
            await MainActor.run {
                self.places = placeRepository.places
                if let firstPlace = places.first {
                    region.center = CLLocationCoordinate2D(
                        latitude: firstPlace.latitude,
                        longitude: firstPlace.longitude
                    )
                }
            }
        } catch {
            print("Failed to load places: \(error)")
        }
    }
    
    func searchPlaces(query: String) async {
        guard !query.isEmpty else {
            await MainActor.run {
                searchResults = []
                isSearching = false
            }
            return
        }
        
        await MainActor.run { isSearching = true }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            await MainActor.run {
                searchResults = response.mapItems
                isSearching = false
            }
        } catch {
            await MainActor.run {
                searchResults = []
                isSearching = false
            }
        }
    }
    
    func createPlaceFromMapItem(_ mapItem: MKMapItem) {
        guard let userID = SupabaseService.shared.currentUserID else { return }
        
        let place = Place(
            ownerID: userID,
            title: mapItem.name ?? "Địa điểm mới",
            category: .other,
            latitude: mapItem.placemark.coordinate.latitude,
            longitude: mapItem.placemark.coordinate.longitude,
            address: formatAddress(mapItem.placemark)
        )
        
        Task {
            do {
                try await placeRepository.createPlace(place)
                await loadPlaces()
            } catch {
                print("Failed to create place: \(error)")
            }
        }
    }
    
    func createPlaceAt(coordinate: CLLocationCoordinate2D) {
        newPlaceCoordinate = coordinate
        showingCreateSheet = true
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func centerOnUserLocation() {
        if let location = locationManager.location {
            region.center = location.coordinate
        }
    }
    
    var filteredPlaces: [Place] {
        guard let category = selectedCategory else {
            return places
        }
        return places.filter { $0.category == category }
    }
    
    private func formatAddress(_ placemark: CLPlacemark) -> String {
        var components: [String] = []
        
        if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }
        if let locality = placemark.locality {
            components.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }
        
        return components.joined(separator: ", ")
    }
}
