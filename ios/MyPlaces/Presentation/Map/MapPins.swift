import SwiftUI

/// Photo pin (visit photo) or a small category pin for places without photos ("muốn đến").
struct PlacePinView: View {
    var cluster: PlaceCluster
    var selected: Bool

    var body: some View {
        let place = cluster.representative
        ZStack(alignment: .topTrailing) {
            if place.coverStoragePath != nil {
                StorageImage(path: place.coverStoragePath, placeholderCategory: place.category)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(selected ? Theme.accent : Theme.textPrimary, lineWidth: selected ? 3 : 2.5))
                    .overlay(alignment: .bottomTrailing) {
                        CategoryDot(category: place.category, size: 10)
                            .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                            .offset(x: 1, y: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if place.isShared {
                            Image(systemName: "person.2.fill").font(.system(size: 7)).foregroundStyle(Theme.textPrimary)
                                .frame(width: 15, height: 15).background(Theme.surfaceHigh, in: Circle())
                                .overlay(Circle().stroke(Theme.textPrimary, lineWidth: 1))
                                .offset(x: -2, y: -2)
                        }
                    }
            } else {
                Image(systemName: place.category.icon)
                    .font(.mp(13, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: selected ? 40 : 32, height: selected ? 40 : 32)
                    .background(place.category.color.opacity(place.visitStatus == .visited ? 0.95 : 0.7), in: Circle())
                    .overlay(Circle().stroke(selected ? Theme.accent : Theme.textPrimary.opacity(0.85), lineWidth: selected ? 3 : 1.5))
            }
            if cluster.count > 1 {
                Text("+\(cluster.count - 1)")
                    .font(.mp(10, .bold)).foregroundStyle(Theme.background)
                    .padding(.horizontal, 5).frame(height: 17)
                    .background(Theme.textPrimary, in: Capsule())
                    .offset(x: 8, y: -6)
            }
        }
        .onPhoto()
        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        .animation(.spring(duration: 0.25), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(place.title)
        .accessibilityIdentifier("pin.\(place.title)")
        .accessibilityAddTraits(.isButton)
    }

    private var size: CGFloat { selected ? 58 : 46 }
}

/// 02b – bottom preview of the selected pin.
struct PlacePreviewCard: View {
    var place: MapPlace
    var body: some View {
        HStack(spacing: 12) {
            PlaceThumb(path: place.coverStoragePath, category: place.category, size: 58, corner: 14)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(place.title).font(.mp(16, .semibold)).foregroundStyle(Theme.textPrimary).mpLineLimit(large: 3)
                    CategoryDot(category: place.category)
                }
                Text(PlaceCopy.visitSummary(place)).font(.mp(12)).foregroundStyle(Theme.textSecondary)
                if let a = place.address, !a.isEmpty {
                    Text(a).font(.mp(12)).foregroundStyle(Theme.textSecondary).mpLineLimit(large: 2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.mp(13, .semibold)).foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(Theme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("map.preview")
    }
}

enum PlaceCopy {
    /// "4 lần ghé · gần nhất 12 thg 10" / "Chưa ghé · muốn đến"
    static func visitSummary(_ p: MapPlace) -> String {
        guard p.visitCount > 0 else { return "Chưa ghé · muốn đến" }
        var s = "\(p.visitCount) lần ghé"
        if let last = p.lastVisitedAt { s += " · gần nhất \(VNFormat.dayMonth(last))" }
        return s
    }
    static func visitCount(_ p: MapPlace) -> String {
        p.visitCount > 0 ? "\(p.visitCount) lần ghé" : "Chưa ghé"
    }
}
