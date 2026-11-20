import SwiftUI

enum Companion: Hashable, Identifiable {
    case user(CompanionSuggestion)
    case guest(String)
    var id: String {
        switch self { case .user(let u): return "u-\(u.userId)"; case .guest(let n): return "g-\(n.lowercased())" }
    }
    var name: String {
        switch self { case .user(let u): return u.displayName; case .guest(let n): return n }
    }
}

/// 04a – log a visit: photos, time (in the device timezone, stored as timezone_id), note, companions.
/// Saved through the outbox (works offline, BR-HY-01/02).
struct LogVisitView: View {
    var place: MapPlace
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [PreparedPhoto] = []
    @State private var visitedAt = Date()
    @State private var note = ""
    @State private var companions: [Companion] = []
    @State private var showCompanions = false
    @State private var showDate = false
    @State private var saving = false
    @State private var error: String?
    private let timezoneId = TimeZone.current.identifier

    var body: some View {
        VStack(spacing: 0) {
            ModalBar(title: "Lần ghé mới", onCancel: { dismiss() }) { EmptyView() }
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        PlaceThumb(path: place.coverStoragePath, category: place.category, size: 28, corner: 14)
                        Text(place.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        CategoryDot(category: place.category)
                        Spacer()
                    }
                    .padding(.horizontal, 12).frame(height: 48)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos) { p in
                                PhotoTile(photo: p, width: 160, height: 160) { photos.removeAll { $0.id == p.id } }
                            }
                            PhotoPickButton(maxCount: 10 - photos.count, onPicked: { photos.append(contentsOf: $0) }) {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [6]))
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(width: photos.isEmpty ? 330 : 120, height: 160)
                                    .overlay(VStack(spacing: 6) {
                                        Image(systemName: "plus").font(.system(size: 22))
                                        if photos.isEmpty { Text("Thêm ảnh").font(.mpCaption) }
                                    }.foregroundStyle(Theme.textSecondary))
                            }
                            .accessibilityIdentifier("visit.addPhoto")
                        }
                    }

                    Button { withAnimation { showDate.toggle() } } label: {
                        HStack {
                            Text("Thời gian").font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(VNFormat.friendlyDateTime(visitedAt)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                Text(VNFormat.zoneLabel(timezoneId)).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .padding(.horizontal, 14).frame(height: 62)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    if showDate {
                        DatePicker("", selection: $visitedAt, in: ...Date().addingTimeInterval(300), displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical).labelsHidden().tint(Theme.accent)
                            .environment(\.locale, Locale(identifier: "vi_VN"))
                            .padding(8).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    TextField("", text: $note, prompt: Text("Ghi chú ngắn…").foregroundColor(Theme.textTertiary), axis: .vertical)
                        .lineLimit(3...6).font(.system(size: 15)).foregroundStyle(Theme.textPrimary).tint(Theme.accent)
                        .padding(14).frame(minHeight: 90, alignment: .topLeading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityIdentifier("visit.note")

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Người đi cùng").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 14) {
                            ForEach(companions) { c in
                                VStack(spacing: 4) {
                                    Avatar(name: c.name, path: { if case .user(let u) = c { return u.avatarPath } else { return nil } }(), size: 40)
                                    Text(c.name.split(separator: " ").last.map(String.init) ?? c.name).font(.system(size: 11)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                }
                                .frame(width: 48)
                            }
                            Button { showCompanions = true } label: {
                                Image(systemName: "plus").foregroundStyle(Theme.textSecondary)
                                    .frame(width: 40, height: 40).overlay(Circle().stroke(Theme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 18)
                            .accessibilityIdentifier("visit.addCompanion")
                            Spacer()
                        }
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let error { Text(error).font(.mpCaption).foregroundStyle(Theme.danger) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            PrimaryButton(title: "Lưu lần ghé", isLoading: saving, isEnabled: note.count <= 1000) { save() }
                .padding(.horizontal, 16).padding(.bottom, 8)
                .accessibilityIdentifier("visit.save")
        }
        .screenBackground()
        .sheet(isPresented: $showCompanions) {
            CompanionPickerSheet(placeTitle: place.title, selection: $companions)
                .presentationDetents([.large])
                .presentationBackground(Theme.background)
        }
    }

    private func save() {
        saving = true; error = nil
        let visitId = UUID()
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts: [ParticipantInsert] = companions.map { c in
            switch c {
            case .user(let u): return ParticipantInsert(id: UUID(), visitId: visitId, userId: u.userId, displayNameSnapshot: String(u.displayName.prefix(40)))
            case .guest(let n): return ParticipantInsert(id: UUID(), visitId: visitId, userId: nil, displayNameSnapshot: String(n.prefix(40)))
            }
        }
        do {
            for p in photos { try p.data.write(to: OutboxFiles.url(p.id), options: .atomic) }
            let payload = VisitDraftPayload(
                visit: VisitInsert(id: visitId, placeId: place.id, visitedAt: visitedAt, timezoneId: timezoneId, note: trimmed.isEmpty ? nil : trimmed),
                participants: parts, memoryId: UUID(),
                photos: photos.map { .init(id: $0.id, width: $0.width, height: $0.height) })
            try SyncEngine.shared.enqueue(.visitCreate, resourceID: visitId, label: "Lần ghé · \(place.title)", payload: payload)
            AppEvents.shared.bump()
            Task {
                await SyncEngine.shared.syncNow()
                await PlacesStore.shared.refresh()
                AppEvents.shared.bump()
            }
            dismiss()
        } catch {
            self.error = AppError.message(error)
        }
        saving = false
    }
}

/// 04b – companions: co-member suggestions (rpc list_companion_suggestions) + free-text names.
/// Picking someone never invites them and grants nothing (ERD-01).
struct CompanionPickerSheet: View {
    var placeTitle: String
    @Binding var selection: [Companion]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var suggestions: [CompanionSuggestion] = []
    @State private var loading = true

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Theme.textTertiary).frame(width: 36, height: 4).padding(.top, 8)
            Text("Người đi cùng").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("", text: $query, prompt: Text("Tìm hoặc nhập tên").foregroundColor(Theme.textSecondary))
                    .foregroundStyle(Theme.textPrimary).tint(Theme.accent).submitLabel(.done)
                    .onSubmit(addGuest)
                    .accessibilityIdentifier("companion.query")
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Thêm", action: addGuest)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 14).frame(height: 30).background(Theme.accent, in: Capsule())
                        .accessibilityIdentifier("companion.addGuest")
                }
            }
            .padding(.leading, 14).padding(.trailing, 6).frame(height: 44)
            .background(Theme.surface, in: Capsule())

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let guests = selection.filter { if case .guest = $0 { return true } else { return false } }
                    if !guests.isEmpty {
                        Text("Đã thêm").font(.mpCaption).foregroundStyle(Theme.textSecondary).padding(.vertical, 8)
                        ForEach(guests) { g in row(name: g.name, path: nil, selected: true) { toggle(g) } }
                    }
                    Text("Người đã chia sẻ với bạn").font(.mpCaption).foregroundStyle(Theme.textSecondary).padding(.vertical, 8)
                    if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                    else if filtered.isEmpty {
                        Text(query.isEmpty ? "Chưa có ai. Nhập tên rồi bấm Thêm để ghi người đi cùng." : "Không có ai khớp. Bấm Thêm để ghi tên “\(query)”.")
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).padding(.vertical, 8)
                    }
                    ForEach(filtered) { s in
                        let c = Companion.user(s)
                        row(name: s.displayName, path: s.avatarPath, selected: selection.contains(c)) { toggle(c) }
                    }
                }
            }
            InfoNote(text: "Không gửi lời mời và không cấp quyền xem")
            PrimaryButton(title: "Xong", tone: .white) { dismiss() }.accessibilityIdentifier("companion.done")
        }
        .padding(.horizontal, 20).padding(.bottom, 8)
        .task {
            suggestions = (try? await MyPlacesAPI.shared.companionSuggestions()) ?? []
            loading = false
        }
    }

    private var filtered: [CompanionSuggestion] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? suggestions : suggestions.filter { $0.displayName.lowercased().contains(q) }
    }

    private func row(name: String, path: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Avatar(name: name, path: path, size: 40)
                Text(name).font(.system(size: 15)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ c: Companion) {
        if let i = selection.firstIndex(of: c) { selection.remove(at: i) } else { selection.append(c) }
    }

    private func addGuest() {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard (1...40).contains(name.count) else { return }
        if let match = suggestions.first(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) {
            if !selection.contains(.user(match)) { selection.append(.user(match)) }
        } else if !selection.contains(.guest(name)) {
            selection.append(.guest(name))
        }
        query = ""
    }
}
