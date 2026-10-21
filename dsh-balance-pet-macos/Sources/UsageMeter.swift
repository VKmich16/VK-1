import Foundation

/// Counts observed balance declines. Top-ups and local demos are excluded.
final class UsageMeter {
    private let url: URL
    private var day: String = ""
    private var last: (cents: Int, time: Date)?
    private(set) var todayCents = 0
    private(set) var hourlyRate = 0.0
    init(url: URL = PetPaths.support.appendingPathComponent("usage.json")) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let key = o["day"] as? String, let amount = o["cents"] as? Int, amount >= 0 {
            day = key; todayCents = amount
        }
    }
    private func dayKey(_ date: Date) -> String {
        let c = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    func observe(cents: Int, at date: Date = Date()) {
        let key = dayKey(date)
        let sameDay = key == day
        if !sameDay { day = key; todayCents = 0; hourlyRate = 0 }
        if sameDay, let previous = last, cents < previous.cents {
            let (spent, overflow) = previous.cents.subtractingReportingOverflow(cents)
            if !overflow {
                let (sum, excess) = todayCents.addingReportingOverflow(spent)
                if !excess { todayCents = sum }
                let seconds = date.timeIntervalSince(previous.time)
                if seconds >= 1 { hourlyRate = Double(spent)/100*3600/seconds }
            }
        } else { hourlyRate = 0 }
        last = (cents, date)
        if let data = try? JSONSerialization.data(withJSONObject: ["day": day, "cents": todayCents]) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
    func resetBaseline() { last = nil; hourlyRate = 0 }
}
