import SwiftUI

struct TimelineFilter: Equatable {
    enum Preset: String, CaseIterable { case all, week, month, year, custom
        var title: String {
            switch self { case .all: return "Tất cả"; case .week: return "7 ngày"; case .month: return "30 ngày"; case .year: return "Năm nay"; case .custom: return "Tùy chọn" }
        }
    }
    var preset: Preset = .all
    var from = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: Date())) ?? Date()
    var to = Date()
    var category: PlaceCategory?

    var isActive: Bool { preset != .all || category != nil }

    /// [p_from, p_to) bounds sent to rpc my_timeline.
    var bounds: (Date?, Date?) {
        let cal = Calendar.current
        switch preset {
        case .all: return (nil, nil)
        case .week: return (cal.date(byAdding: .day, value: -7, to: Date()), nil)
        case .month: return (cal.date(byAdding: .day, value: -30, to: Date()), nil)
        case .year: return (cal.date(from: cal.dateComponents([.year], from: Date())), nil)
        case .custom: return (cal.startOfDay(for: from), cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to)))
        }
    }
}

@MainActor
@Observable
final class TimelineModel {
    var items: [TimelineItem] = []
    var loading = false
    var loaded = false
    var canLoadMore = false
    var error: String?
    var filter = TimelineFilter()
    private let pageSize = 50

    func reload() async {
        loading = true
        defer { loading = false }
        do {
            let (from, to) = filter.bounds
            let rows = try await MyPlacesAPI.shared.timeline(.init(pFrom: from, pTo: to, pCategory: filter.category, pLimit: pageSize))
            items = rows
            canLoadMore = rows.count == pageSize
            error = nil
        } catch { self.error = AppError.message(error) }
        loaded = true
    }

    func loadMore() async {
        guard canLoadMore, !loading, let last = items.last else { return }
        loading = true
        defer { loading = false }
        let (from, _) = filter.bounds
        if let rows = try? await MyPlacesAPI.shared.timeline(.init(pFrom: from, pTo: last.visitedAt, pCategory: filter.category, pLimit: pageSize)) {
            items.append(contentsOf: rows.filter { r in !items.contains { $0.id == r.id } })
            canLoadMore = rows.count == pageSize
        }
    }

    /// Grouped by month of the visit's own local time (timezone_id).
    var sections: [(title: String, items: [TimelineItem])] {
        var result: [(String, [TimelineItem])] = []
        for item in items {
            let title = VNFormat.monthYear(item.local)
            if let i = result.firstIndex(where: { $0.0 == title }) { result[i].1.append(item) } else { result.append((title, [item])) }
        }
        return result
    }
}

/// 05a – personal timeline (rpc my_timeline), 05b filter.
struct TimelineView: View {
    @Environment(Router.self) private var router
    @State private var model = TimelineModel()
    @State private var showFilter = false

    var body: some View {
        VStack(spacing: 0) {
            if model.loaded && model.items.isEmpty {
                Spacer()
                EmptyStateView(icon: "clock", title: model.filter.isActive ? "Không có lần ghé phù hợp" : "Chưa có lần ghé nào",
                               message: model.filter.isActive ? "Thử đổi bộ lọc thời gian hoặc danh mục." : "Ghi lần ghé tại một địa điểm để bắt đầu dòng thời gian.")
                Spacer()
            } else if !model.loaded {
                Spacer(); ProgressView().tint(Theme.textPrimary); Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        ForEach(model.sections, id: \.title) { section in
                            Text(section.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
                                .padding(.top, 14).padding(.bottom, 10).padding(.leading, 20)
                            ForEach(section.items) { item in
                                Button { router.push(.visit(item.visitId)) } label: { row(item) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("timeline.item.\(item.title)")
                                    .onAppear { if item.id == model.items.last?.id { Task { await model.loadMore() } } }
                            }
                        }
                    }
                    .padding(.bottom, 36 + Theme.tabInset)
                }
                .refreshable { await model.reload() }
            }
        }
        .screenBackground()
        .mpTabRootTitle("Dòng thời gian")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarIconButton(systemName: model.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "slider.horizontal.3",
                                  tint: model.filter.isActive ? Theme.accent : Theme.textPrimary) { showFilter = true }
                    .accessibilityIdentifier("timeline.filter")
                    .accessibilityLabel("Lọc")
            }
        }
        .task(id: AppEvents.shared.revision) { await model.reload() }
        .onChange(of: model.filter) { _, _ in Task { await model.reload() } }
        .sheet(isPresented: $showFilter) {
            TimelineFilterSheet(filter: $model.filter)
                .presentationDetents([.height(520)])
                .mpSheetBackground(Theme.surface, cornerRadius: 32)
        }
    }

    private func row(_ item: TimelineItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle().fill(Theme.textSecondary).frame(width: 6, height: 6).padding(.top, 14)
                Rectangle().fill(Theme.hairline).frame(width: 1)
            }
            .frame(width: 8)
            Group {
                if let cover = item.coverStoragePath {
                    ZStack(alignment: .bottomLeading) {
                        StorageImage(path: cover, placeholderCategory: item.placeCategory)
                        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                        caption(item).padding(14).onPhoto()
                    }
                    .frame(height: 170)
                } else {
                    caption(item).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
            .padding(.bottom, 12)
        }
        .padding(.leading, 20).padding(.trailing, 16)
    }

    private func caption(_ item: TimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let c = item.placeCategory { CategoryDot(category: c) }
                Text(item.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if item.myRole != .owner { Image(systemName: "person.2.fill").font(.system(size: 9)).foregroundStyle(Theme.textSecondary) }
            }
            Text("\(VNFormat.weekdayDay(item.local)) · \(VNFormat.time(item.local))").font(.system(size: 12)).foregroundStyle(Theme.textPrimary.opacity(0.7))
            if let note = item.note, !note.isEmpty {
                Text(note).font(.system(size: 13)).foregroundStyle(Theme.textPrimary.opacity(0.85)).lineLimit(1)
            }
        }
    }
}

struct TimelineFilterSheet: View {
    @Binding var filter: TimelineFilter
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TimelineFilter()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Lọc").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                CircleIconButton(systemName: "xmark", size: 32, background: Theme.surfaceHigh) { dismiss() }
            }
            .padding(.top, 20)
            Text("THỜI GIAN").font(.mpSection).tracking(0.6).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach([TimelineFilter.Preset.week, .month, .year, .custom], id: \.self) { p in
                    Chip(title: p.title, selected: draft.preset == p) { draft.preset = (draft.preset == p ? .all : p) }
                }
            }
            if draft.preset == .custom {
                HStack(spacing: 10) {
                    dateField("Từ", $draft.from)
                    dateField("Đến", $draft.to)
                }
            }
            Text("DANH MỤC").font(.mpSection).tracking(0.6).foregroundStyle(Theme.textSecondary).padding(.top, 4)
            FlowLayout(spacing: 8) {
                ForEach(PlaceCategory.allCases) { c in
                    Chip(title: c.displayName, category: c, selected: draft.category == c, showCheck: true) { draft.category = (draft.category == c ? nil : c) }
                }
            }
            Spacer()
            HStack {
                Button("Đặt lại") { draft = TimelineFilter() }.font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button { filter = draft; dismiss() } label: {
                    Text("Áp dụng").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 28).frame(height: 48).background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("filter.apply")
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .onAppear { draft = filter }
    }

    private func dateField(_ label: String, _ date: Binding<Date>) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            DatePicker("", selection: date, displayedComponents: .date).labelsHidden().tint(Theme.accent)
                .environment(\.locale, Locale(identifier: "vi_VN"))
        }
        .padding(.horizontal, 12).frame(height: 44).frame(maxWidth: .infinity)
        .background(Theme.surfaceHigh, in: Capsule())
    }
}
