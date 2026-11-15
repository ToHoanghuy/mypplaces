import SwiftUI
import MapKit

struct PlaceDetailView: View {
    let place: Place
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Map(initialPosition: .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(
                                latitude: place.latitude,
                                longitude: place.longitude
                            ),
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )) {
                        Annotation(
                            place.title,
                            coordinate: CLLocationCoordinate2D(
                                latitude: place.latitude,
                                longitude: place.longitude
                            )
                        ) {
                            Image(systemName: place.category.icon)
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.blue)
                                .clipShape(Circle())
                        }
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label(place.category.displayName, systemImage: place.category.icon)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            if let visitedAt = place.visitedAt {
                                Text(visitedAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        
                        if let address = place.address {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Địa chỉ")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(address)
                                    .font(.body)
                            }
                        }
                        
                        if let note = place.note {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ghi chú")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(note)
                                    .font(.body)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tọa độ")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.6f, %.6f", place.latitude, place.longitude))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(place.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Text("Sửa")
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                EditPlaceView(place: place)
            }
        }
    }
}
