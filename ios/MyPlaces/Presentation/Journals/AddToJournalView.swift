import SwiftUI

/// 06e – link my places / visits to a journal (only the owner of a Place/Visit may link it, UC-08).
struct AddToJournalView: View {
    var journal: Journal
    var existingPlaces: Set<UUID>
    var existingVisits: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var query = ""
    @State private var selectedPlaces: Set<UUID> = []
    @State private var selectedVisits: Set<UUID> = []
    @State private var visits: [TimelineItem] = []
    @State private var saving = false
    @State private var error: String?
    @State private var addSeed: PlaceSeed?
    private var store: PlacesStore { PlacesStore.shared }

    var body: some View {
        VStack(spacing: 12) {
            ModalBar(title: "Thêm vào \(journal.title)", onCancel: { dismiss() }) { EmptyView() }
            HStack(spacing: 0) {
                ForEach(Array(["Địa điểm", "Lần ghé"].enumerated()), id: \.offset) { i, t in
                    Button { tab = i } label: {
                        Text(t).font(.system(size: 13, weight: tab == i ? .semibold : .regular))
                            .foregroundStyle(tab == i ? Theme.textPrimary : Theme.textSecondary)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(tab == i ? Theme.surfaceHigh : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(3).background(Theme.surface, in: Capsule()).padding(.horizontal, 16)
            SearchField(placeholder: tab == 0 ? "Tìm kiếm địa điểm..." : "Tìm kiếm lần ghé...", text: $query).padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 0) {
                    if tab == 0 {
                        Button {
                            addSeed = PlaceSeed(coordinate: LocationService.shared.lastLocation?.coordinate ?? MapClustering.hanoi.center)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "plus").foregroundStyle(Theme.textPrimary).frame(width: 40, height: 40).background(Theme.surface, in: Circle())
                                Text("Tạo địa điểm mới").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.vertical, 10)
                        }.buttonStyle(.plain)
                        Divider().overlay(Theme.hairline)
                        ForEach(placeList) { p in
                            let linked = existingPlaces.contains(p.id)
                            selectRow(title: p.title, subtitle: linked ? "Đã có trong nhật ký" : p.address, category: p.category,
                                      path: p.coverStoragePath, selected: linked || selectedPlaces.contains(p.id), disabled: linked) {
                                toggle(&selectedPlaces, p.id)
                            }
                        }
                        if placeList.isEmpty { hint("Chỉ chủ sở hữu mới thêm được địa điểm vào nhật ký.") }
                    } else {
                        ForEach(visitList) { v in
                            let linked = existingVisits.contains(v.visitId)
                            selectRow(title: v.title, subtitle: linked ? "Đã có trong nhật ký" : "\(VNFormat.weekdayDay(v.local)) · \(VNFormat.time(v.local))",
                                      category: v.placeCategory ?? .other, path: v.coverStoragePath,
                                      selected: linked || selectedVisits.contains(v.visitId), disabled: linked) {
                                toggle(&selectedVisits, v.visitId)
                            }
                        }
                        if visitList.isEmpty { hint("Chưa có lần ghé nào của bạn.") }
                    }
                }
                .padding(.horizontal, 16)
            }
            if let error { Text(error).font(.mpCaption).foregroundStyle(Theme.danger) }
            PrimaryButton(title: count == 0 ? "Chọn mục để thêm" : "Thêm \(count) mục", isLoading: saving, isEnabled: count > 0) { save() }
                .padding(.horizontal, 16).padding(.bottom, 8)
                .accessibilityIdentifier("addtojournal.save")
        }
        .screenBackground()
        .task {
            visits = ((try? await MyPlacesAPI.shared.timeline(.init(pLimit: 200))) ?? []).filter { $0.myRole == .owner }
        }
        .fullScreenCover(item: $addSeed) { seed in
            AddPlaceView(seed: seed) { id in selectedPlaces.insert(id) }
        }
    }

    private var count: Int { selectedPlaces.count + selectedVisits.count }

    private func matches(_ s: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || s.localizedCaseInsensitiveContains(q)
    }
    private var placeList: [MapPlace] { store.places.filter { $0.isOwner && matches($0.title) } }
    private var visitList: [TimelineItem] { visits.filter { matches($0.title) } }

    private func hint(_ t: String) -> some View {
        Text(t).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).padding(.vertical, 20)
    }

    private func toggle(_ set: inout Set<UUID>, _ id: UUID) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func selectRow(title: String, subtitle: String?, category: PlaceCategory, path: String?, selected: Bool, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PlaceThumb(path: path, category: category, size: 40, corner: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) { Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary); CategoryDot(category: category) }
                    if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1) }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(disabled ? Theme.textTertiary : (selected ? Theme.accent : Theme.textTertiary))
            }
            .padding(.vertical, 10)
            .opacity(disabled ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("select.\(title)")
    }

    private func save() {
        saving = true; error = nil
        Task {
            do {
                try await MyPlacesAPI.shared.linkPlaces(selectedPlaces.map { JournalPlaceInsert(journalId: journal.id, placeId: $0, sortOrder: 0) })
                try await MyPlacesAPI.shared.linkVisits(selectedVisits.map { JournalVisitInsert(journalId: journal.id, visitId: $0, sortOrder: 0) })
                AppEvents.shared.bump()
                dismiss()
            } catch {
                self.error = SyncEngine.shared.state(for: selectedPlaces.first ?? UUID()) != nil
                    ? "Địa điểm mới chưa đồng bộ xong, hãy thử lại sau giây lát." : AppError.message(error)
            }
            saving = false
        }
    }
}
