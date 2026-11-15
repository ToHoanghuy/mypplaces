import SwiftUI

struct AuthView: View {
    @State private var viewModel = AuthViewModel()
    @State private var isSignUp = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                VStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                    
                    Text("MyPlaces")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Lưu giữ những địa điểm và kỷ niệm")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 32)
                
                VStack(spacing: 16) {
                    if isSignUp {
                        TextField("Tên hiển thị", text: $viewModel.displayName)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)
                            .autocapitalization(.words)
                    }
                    
                    TextField("Email", text: $viewModel.email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    SecureField("Mật khẩu", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(isSignUp ? .newPassword : .password)
                    
                    Button {
                        Task {
                            if isSignUp {
                                await viewModel.signUp()
                            } else {
                                await viewModel.signIn()
                            }
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(isSignUp ? "Đăng ký" : "Đăng nhập")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                    .disabled(viewModel.isLoading)
                    
                    if !isSignUp {
                        Button {
                            Task {
                                await viewModel.signInWithMagicLink()
                            }
                        } label: {
                            Text("Đăng nhập bằng Magic Link")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .controlSize(.large)
                        .disabled(viewModel.isLoading)
                        
                        Button {
                            Task {
                                await viewModel.resetPassword()
                            }
                        } label: {
                            Text("Quên mật khẩu?")
                                .font(.footnote)
                        }
                        .disabled(viewModel.isLoading)
                    }
                }
                .padding(.horizontal, 32)
                
                Button {
                    withAnimation {
                        isSignUp.toggle()
                        viewModel.errorMessage = nil
                    }
                } label: {
                    Text(isSignUp ? "Đã có tài khoản? Đăng nhập" : "Chưa có tài khoản? Đăng ký")
                        .font(.subheadline)
                }
                .padding(.top, 8)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Divider()
                        .padding(.horizontal, 32)
                    
                    Button {
                        // Sign in with Apple scaffolding
                    } label: {
                        Label("Đăng nhập với Apple", systemImage: "apple.logo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.horizontal, 32)
                    .disabled(true)
                }
                .padding(.bottom, 32)
            }
            .alert("Thông báo", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {
                    viewModel.showError = false
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

#Preview {
    AuthView()
}
