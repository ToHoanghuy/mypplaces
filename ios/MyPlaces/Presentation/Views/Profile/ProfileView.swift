import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var authViewModel = AuthViewModel()
    
    var body: some View {
        NavigationStack {
            List {
                if let user = appState.authRepository.currentUser {
                    Section {
                        HStack {
                            if let avatarPath = user.avatarPath {
                                AsyncImage(url: URL(string: avatarPath)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .foregroundStyle(.gray)
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .foregroundStyle(.gray)
                                    .frame(width: 60, height: 60)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline)
                                Text("ID: \(user.id.uuidString.prefix(8))...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 8)
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Section("Cài đặt") {
                    NavigationLink {
                        Text("Chỉnh sửa profile")
                    } label: {
                        Label("Chỉnh sửa profile", systemImage: "person")
                    }
                    
                    NavigationLink {
                        Text("Cài đặt quyền riêng tư")
                    } label: {
                        Label("Quyền riêng tư", systemImage: "lock")
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        Task {
                            await authViewModel.signOut()
                        }
                    } label: {
                        Label("Đăng xuất", systemImage: "arrow.right.square")
                    }
                }
                
                Section {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("1.0.0 (MVP)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Cá nhân")
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState.shared)
}
