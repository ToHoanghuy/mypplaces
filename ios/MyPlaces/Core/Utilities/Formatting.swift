import Foundation

/// Vietnamese date/time copy used across the Stitch screens.
enum VNFormat {
    static let weekdays = ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]

    static func calendar(_ tz: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        c.locale = Locale(identifier: "vi_VN")
        return c
    }

    static func tz(_ id: String?) -> TimeZone { id.flatMap(TimeZone.init(identifier:)) ?? .current }

    /// "Thứ Bảy, 12 thg 10"
    static func weekdayDay(_ date: Date, tz: TimeZone = .current) -> String {
        weekdayDay(calendar(tz).dateComponents([.weekday, .day, .month], from: date))
    }
    static func weekdayDay(_ c: DateComponents) -> String {
        "\(weekdays[((c.weekday ?? 1) - 1) % 7]), \(c.day ?? 1) thg \(c.month ?? 1)"
    }
    /// "15:30"
    static func time(_ date: Date, tz: TimeZone = .current) -> String {
        time(calendar(tz).dateComponents([.hour, .minute], from: date))
    }
    static func time(_ c: DateComponents) -> String {
        String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    /// "12 thg 10"
    static func dayMonth(_ date: Date, tz: TimeZone = .current) -> String {
        let c = calendar(tz).dateComponents([.day, .month], from: date)
        return "\(c.day ?? 1) thg \(c.month ?? 1)"
    }
    /// "Tháng 10, 2026"
    static func monthYear(_ c: DateComponents) -> String { "Tháng \(c.month ?? 1), \(c.year ?? 2026)" }
    /// "01/10/2026"
    static func numeric(_ date: Date, tz: TimeZone = .current) -> String {
        let c = calendar(tz).dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d/%02d/%04d", c.day ?? 1, c.month ?? 1, c.year ?? 2026)
    }
    /// "Hôm nay, 15:30" / "Hôm qua, 08:00" / "Thứ Bảy, 12 thg 10 · 15:30"
    static func friendlyDateTime(_ date: Date, tz: TimeZone = .current) -> String {
        let cal = calendar(tz)
        if cal.isDateInToday(date) { return "Hôm nay, \(time(date, tz: tz))" }
        if cal.isDateInYesterday(date) { return "Hôm qua, \(time(date, tz: tz))" }
        return "\(weekdayDay(date, tz: tz)) · \(time(date, tz: tz))"
    }
    /// "2 giờ trước", "Hôm qua", "3 ngày trước", "2 tuần trước"
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "Vừa xong" }
        if s < 3600 { return "\(Int(s / 60)) phút trước" }
        if s < 86400 { return "\(Int(s / 3600)) giờ trước" }
        let cal = calendar()
        if cal.isDateInYesterday(date) { return "Hôm qua" }
        let days = Int(s / 86400)
        if days < 7 { return "\(days) ngày trước" }
        if days < 30 { return "\(days / 7) tuần trước" }
        if days < 365 { return "\(days / 30) tháng trước" }
        return "\(days / 365) năm trước"
    }
    /// "01 – 15 thg 10, 2026" from yyyy-MM-dd strings.
    static func dateRange(start: String?, end: String?) -> String? {
        let s = start.flatMap { DateParsing.day.date(from: $0) }
        let e = end.flatMap { DateParsing.day.date(from: $0) }
        let utc = TimeZone(identifier: "UTC")!
        let cal = calendar(utc)
        func comps(_ d: Date) -> DateComponents { cal.dateComponents([.day, .month, .year], from: d) }
        switch (s, e) {
        case let (s?, e?):
            let a = comps(s), b = comps(e)
            if a.month == b.month && a.year == b.year {
                return String(format: "%02d – %02d thg %d, %d", a.day!, b.day!, b.month!, b.year!)
            }
            if a.year == b.year {
                return String(format: "%02d thg %d – %02d thg %d, %d", a.day!, a.month!, b.day!, b.month!, b.year!)
            }
            return "\(numeric(s, tz: utc)) – \(numeric(e, tz: utc))"
        case let (s?, nil):
            let a = comps(s); return String(format: "Từ %02d thg %d, %d", a.day!, a.month!, a.year!)
        case let (nil, e?):
            let b = comps(e); return String(format: "Đến %02d thg %d, %d", b.day!, b.month!, b.year!)
        default: return nil
        }
    }
    /// "Giờ Việt Nam" etc.
    static func zoneLabel(_ id: String) -> String {
        switch id {
        case "Asia/Ho_Chi_Minh", "Asia/Saigon": return "Giờ Việt Nam"
        default:
            let name = TimeZone(identifier: id)?.localizedName(for: .shortGeneric, locale: Locale(identifier: "vi_VN"))
            return name ?? id
        }
    }
    /// "hết hạn sau 6 ngày"
    static func expiresIn(_ date: Date, now: Date = Date()) -> String {
        let s = date.timeIntervalSince(now)
        if s <= 0 { return "đã hết hạn" }
        if s < 3600 { return "hết hạn sau \(max(1, Int(s / 60))) phút" }
        if s < 86400 { return "hết hạn sau \(Int(s / 3600)) giờ" }
        return "hết hạn sau \(Int((s / 86400).rounded(.up))) ngày"
    }
}
