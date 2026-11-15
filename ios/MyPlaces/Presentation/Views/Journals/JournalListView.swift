import SwiftUI

struct JournalListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Hành trình",
                systemImage: "book.closed",
                description: Text("Tính năng này sẽ được phát triển trong phiên bản tiếp theo")
            )
            .navigationTitle("Hành trình")
        }
    }
}

#Preview {
    JournalListView()
}
