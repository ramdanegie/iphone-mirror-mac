import Foundation

public enum ScreenshotNaming {
    /// "Cermin 2026-11-03 09.41.05.png" (PRD §F4).
    public static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Cermin \(f.string(from: date)).png"
    }

    /// Appends " 2", " 3"… when two screenshots land in the same second.
    public static func uniqueURL(in folder: URL, fileName: String, exists: (URL) -> Bool) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var url = folder.appendingPathComponent(fileName)
        var n = 2
        while exists(url) {
            url = folder.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }
}
