import SwiftUI
import MapKit
import SwiftData

struct MapView: View {
    @State private var viewModel: MapViewModel
    @State private var showingSearch = false
    
    init(modelContext: ModelContext) {
        _viewModel = State(initialValue: MapViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: .constant(.region(viewModel.region))) {
                    ForEach(viewModel.filteredPlaces) { place in
                        Annotation(
                            place.title,
                            coordinate: CLLocationCoordinate2D(
                                latitude: place.latitude,
                                longitude: place.longitude
                            )
                        ) {
                            PlaceAnnotationView(place: place)
                                .onTapGesture {
                                    viewModel.selectedPlace = place
                                }
                        }
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .onTapGesture { location in
                    // Long press will be handled separately
                }
                
                if showingSearch {
                    SearchOverlayView(
                        viewModel: viewModel,
                        isPresented: $showingSearch
                    )
                }
            }
            .navigationTitle("Bản đồ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showingSearch.toggle()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.selectedCategory = nil
                        } label: {
                            Label("Tất cả", systemImage: "square.grid.2x2")
                        }
                        
                        Divider()
                        
                        ForEach(PlaceCategory.allCases, id: \.self) { category in
                            Button {
                                viewModel.selectedCategory = category
                            } label: {
                                Label(category.displayName, systemImage: category.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    
                    Button {
                        viewModel.requestLocationPermission()
                        viewModel.centerOnUserLocation()
                    } label: {
                        Image(systemName: "location")
                    }
                }
            }
            .sheet(item: $viewModel.selectedPlace) { place in
                PlaceDetailView(place: place)
            }
            .sheet(isPresented: $viewModel.showingCreateSheet) {
                if let coordinate = viewModel.newPlaceCoordinate {
                    CreatePlaceView(
                        coordinate: coordinate,
                        onSave: { newPlace in
                            Task {
                                try? await viewModel.placeRepository.createPlace(newPlace)
                                await viewModel.loadPlaces()
                            }
                        }
                    )
                }
            }
        }
    }
}

struct PlaceAnnotationView: View {
    let place: Place
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: place.category.icon)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue)
                .clipShape(Circle())
            
            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.blue)
                .offset(y: -4)
        }
    }
}

struct SearchOverlayView: View {
    @Bindable var viewModel: MapViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Tìm kiếm địa điểm...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.searchText) { oldValue, newValue in
                        Task {
                            await viewModel.searchPlaces(query: newValue)
                        }
                    }
                
                Button("Hủy") {
                    isPresented = false
                    viewModel.searchText = ""
                    viewModel.searchResults = []
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            if viewModel.isSearching {
                ProgressView()
                    .padding()
                Spacer()
            } else if !viewModel.searchResults.isEmpty {
                List(viewModel.searchResults, id: \.self) { mapItem in
                    Button {
                        viewModel.createPlaceFromMapItem(mapItem)
                        isPresented = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mapItem.name ?? "")
                                .font(.headline)
                            if let address = mapItem.placemark.title {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            } else if !viewModel.searchText.isEmpty {
                VStack {
                    Spacer()
                    Text("Không tìm thấy kết quả")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}
