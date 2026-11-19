import Foundation
import Supabase

/// Maps backend / network errors to short Vietnamese messages (BRD error contract: PostgREST
/// raises a stable code in `message`, e.g. INVITATION_EXPIRED with SQLSTATE PT410).
enum AppError {
    static func code(_ error: Error) -> String? {
        if let e = error as? PostgrestError { return e.message }
        return nil
    }

    static func isNetwork(_ error: Error) -> Bool {
        if error is URLError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain
    }

    /// Unique-violation: the row already exists (idempotent retry of a create).
    static func isDuplicate(_ error: Error) -> Bool {
        if let e = error as? PostgrestError { return e.code == "23505" }
        let text = String(describing: error).lowercased()
        return text.contains("duplicate") || text.contains("already exists")
    }

    static func message(_ error: Error) -> String {
        if isNetwork(error) { return "Không có kết nối mạng. Vui lòng thử lại." }
        if let code = code(error) {
            switch code {
            case "INVITATION_EXPIRED": return "Lời mời đã hết hạn."
            case "INVITATION_REVOKED": return "Lời mời đã bị thu hồi."
            case "INVITATION_DECLINED": return "Lời mời đã bị từ chối."
            case "INVITATION_USED": return "Lời mời đã được sử dụng."
            case "INVITATION_NOT_FOUND": return "Không tìm thấy lời mời."
            case "FORBIDDEN": return "Bạn không có quyền thực hiện thao tác này."
            case "ALREADY_MEMBER": return "Người này đã là thành viên."
            case "ALREADY_OWNER": return "Bạn là chủ sở hữu của mục này."
            case "CANNOT_INVITE_SELF": return "Bạn không thể mời chính mình."
            case "INVALID_EMAIL": return "Email không hợp lệ."
            case "INVALID_EXPIRY": return "Thời hạn lời mời không hợp lệ."
            case "RESOURCE_UNAVAILABLE", "RESOURCE_NOT_FOUND": return "Mục này không còn khả dụng."
            case "OWNER_MUST_TRANSFER", "OWNER_CANNOT_BE_REMOVED": return "Chủ sở hữu cần chuyển quyền trước."
            case "AUTH_REQUIRED": return "Vui lòng đăng nhập lại."
            default: break
            }
            if let e = error as? PostgrestError {
                if e.code == "42501" { return "Bạn không có quyền thực hiện thao tác này." }
                if e.code == "23514" { return "Dữ liệu không hợp lệ." }
            }
        }
        let text = String(describing: error).lowercased()
        if text.contains("invalid login credentials") { return "Email hoặc mật khẩu không đúng." }
        if text.contains("email not confirmed") { return "Email chưa được xác nhận. Hãy mở liên kết trong email." }
        if text.contains("already registered") || text.contains("user_already_exists") { return "Email này đã được đăng ký." }
        if text.contains("password") && text.contains("6") { return "Mật khẩu quá ngắn." }
        if text.contains("rate limit") || text.contains("over_email_send_rate_limit") { return "Bạn thao tác quá nhanh, hãy thử lại sau ít phút." }
        if text.contains("invalid") && text.contains("email") { return "Email không hợp lệ." }
        return "Đã có lỗi xảy ra. Vui lòng thử lại."
    }
}
