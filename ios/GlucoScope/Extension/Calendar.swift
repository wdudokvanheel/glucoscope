import Foundation

extension Calendar {
    /// Returns the start of the hour for a given date.
    func startOfHour(for date: Date) -> Date {
        return self.date(from: dateComponents([.year, .month, .day, .hour], from: date))!
    }
}
