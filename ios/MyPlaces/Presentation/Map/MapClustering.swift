import MapKit

struct PlaceCluster: Identifiable, Hashable {
    var representative: MapPlace
    var members: [MapPlace]
    var id: UUID { representative.id }
    var coordinate: CLLocationCoordinate2D { representative.coordinate }
    var count: Int { members.count }
}

/// Screen-space greedy clustering (MapKit's SwiftUI Map has no built-in clustering).
/// Places closer than `radius` points on screen merge; the newest place with a photo
/// represents the cluster (BR-02 photo pins, §11.1).
enum MapClustering {
    static func clusters(_ places: [MapPlace], region: MKCoordinateRegion?, size: CGSize, radius: CGFloat = 46) -> [PlaceCluster] {
        let ordered = places.sorted { a, b in
            let pa = a.coverStoragePath != nil, pb = b.coverStoragePath != nil
            if pa != pb { return pa }
            return (a.lastVisitedAt ?? a.updatedAt ?? .distantPast) > (b.lastVisitedAt ?? b.updatedAt ?? .distantPast)
        }
        guard let region, size.width > 0, region.span.longitudeDelta > 0, region.span.latitudeDelta > 0 else {
            return ordered.map { PlaceCluster(representative: $0, members: [$0]) }
        }
        func point(_ c: CLLocationCoordinate2D) -> CGPoint {
            let x = (c.longitude - (region.center.longitude - region.span.longitudeDelta / 2)) / region.span.longitudeDelta * size.width
            let y = ((region.center.latitude + region.span.latitudeDelta / 2) - c.latitude) / region.span.latitudeDelta * size.height
            return CGPoint(x: x, y: y)
        }
        var result: [(center: CGPoint, cluster: PlaceCluster)] = []
        for p in ordered {
            let pt = point(p.coordinate)
            if let i = result.firstIndex(where: { hypot($0.center.x - pt.x, $0.center.y - pt.y) < radius }) {
                result[i].cluster.members.append(p)
            } else {
                result.append((pt, PlaceCluster(representative: p, members: [p])))
            }
        }
        return result.map(\.cluster)
    }

    static func region(fitting coords: [CLLocationCoordinate2D], minSpan: Double = 0.01) -> MKCoordinateRegion? {
        guard let first = coords.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.6, minSpan), longitudeDelta: max((maxLon - minLon) * 1.6, minSpan))
        return MKCoordinateRegion(center: center, span: span)
    }

    static let hanoi = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542),
                                          span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03))
}
