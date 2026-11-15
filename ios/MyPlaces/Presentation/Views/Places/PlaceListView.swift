import SwiftUI
import SwiftData

struct PlaceListView: View {
    @State private var viewModel: PlaceListViewModel
    @State private var selectedPlace: Place?
    
    init(modelContext: ModelContext) {
        _viewModel = State(initialValue: PlaceListViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.filteredPlaces.isEmpty {
                    ContentUnavailableView(
                        "Chưa có địa điểm",
                        systemImage: "mappin.slash",
                        description: Text("Thêm địa điểm đầu tiên của bạn")
                    )
                } else {
                    List {
                        ForEach(viewModel.groupedPlaces(), id: \.0) { category, places in
                            Section(header: Text(category.displayName)) {
                                ForEach(places) { place in
                                    PlaceRowView(place: place)
                                        .onTapGesture {
                                            selectedPlace = place
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                Task {
                                                    await viewModel.deletePlace(place)
                                                }
                                            } label: {
                                                Label("Xóa", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await viewModel.loadPlaces()
                    }
                }
            }
            .navigationTitle("Địa điểm")
            .searchable(
                text: $viewModel.searchText,
                prompt: "Tìm kiếm địa điểm"
            )
            .toolbar {
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
                        viewModel.showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedPlace) { place in
                PlaceDetailView(place: place)
            }
            .sheet(isPresented: $viewModel.showingCreateSheet) {
                Text("Create Place Sheet - To be implemented")
            }
        }
    }
}

struct PlaceRowView: View {
    let place: Place
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.category.icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(place.title)
                    .font(.headline)
                
                if let address = place.address {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                if let visitedAt = place.visitedAt {
                    Text(visitedAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
