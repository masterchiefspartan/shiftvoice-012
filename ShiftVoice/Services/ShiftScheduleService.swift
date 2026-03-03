import Foundation

nonisolated struct ShiftScheduleService: Sendable {

    static func resolveShiftType(for location: Location?, at date: Date = Date()) -> ShiftType {
        guard let location else { return .unscheduled }

        let tz = TimeZone(identifier: location.timezone) ?? .current
        var cal = Calendar.current
        cal.timeZone = tz

        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let currentMinutes = hour * 60 + minute

        guard let openingMinutes = parseTimeString(location.openingTime),
              let midMinutes = parseTimeString(location.midTime),
              let closingMinutes = parseTimeString(location.closingTime) else {
            return .unscheduled
        }

        let shifts: [(type: ShiftType, start: Int, end: Int)] = buildShiftWindows(
            opening: openingMinutes,
            mid: midMinutes,
            closing: closingMinutes
        )

        guard !shifts.isEmpty else { return .unscheduled }

        var bestShift: ShiftType = .unscheduled
        var bestDistance = Int.max

        for shift in shifts {
            if isTimeInWindow(currentMinutes, start: shift.start, end: shift.end) {
                let center = shiftCenter(start: shift.start, end: shift.end)
                let distance = circularDistance(currentMinutes, center)
                if distance < bestDistance {
                    bestDistance = distance
                    bestShift = shift.type
                }
            }
        }

        if bestShift == .unscheduled {
            for shift in shifts {
                let center = shiftCenter(start: shift.start, end: shift.end)
                let distance = circularDistance(currentMinutes, center)
                if distance < bestDistance {
                    bestDistance = distance
                    bestShift = shift.type
                }
            }
        }

        return bestShift
    }

    static func resolveShiftTypeString(for location: Location?, at date: Date = Date()) -> String {
        resolveShiftType(for: location, at: date).rawValue.lowercased()
    }

    private static func parseTimeString(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              h >= 0, h < 24, m >= 0, m < 60 else { return nil }
        return h * 60 + m
    }

    private static func buildShiftWindows(opening: Int, mid: Int, closing: Int) -> [(type: ShiftType, start: Int, end: Int)] {
        var windows: [(type: ShiftType, start: Int, end: Int)] = []
        windows.append((.opening, opening, mid))
        windows.append((.mid, mid, closing))
        windows.append((.closing, closing, opening))
        return windows
    }

    private static func isTimeInWindow(_ time: Int, start: Int, end: Int) -> Bool {
        if start <= end {
            return time >= start && time < end
        }
        return time >= start || time < end
    }

    private static func shiftCenter(start: Int, end: Int) -> Int {
        let totalMinutesInDay = 1440
        if start <= end {
            return (start + end) / 2
        }
        let duration = (totalMinutesInDay - start) + end
        let center = (start + duration / 2) % totalMinutesInDay
        return center
    }

    private static func circularDistance(_ a: Int, _ b: Int) -> Int {
        let totalMinutesInDay = 1440
        let diff = abs(a - b)
        return min(diff, totalMinutesInDay - diff)
    }
}
