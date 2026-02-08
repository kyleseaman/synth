import SwiftUI

// MARK: - Calendar Sidebar View

struct CalendarSidebarView: View {
    @State private var displayedMonth = Date()
    let onSelectDate: (Date) -> Void
    let noteDates: Set<String>

    private let dayLabels = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let dayIdentifierFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            // Month/year header with navigation
            monthHeader

            // Day-of-week labels
            dayOfWeekRow

            // Day grid
            dayGrid

            Spacer()
        }
        .padding(12)
        .frame(width: 220)
        .background(Color(.textBackgroundColor).opacity(0.5))
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(Self.monthYearFormatter.string(from: displayedMonth))
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Day of Week Row

    private var dayOfWeekRow: some View {
        HStack(spacing: 0) {
            ForEach(dayLabels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Day Grid

    private var dayGrid: some View {
        let weeks = calendarWeeks()
        return VStack(spacing: 2) {
            ForEach(weeks, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { dayInfo in
                        CalendarDayCell(
                            dayInfo: dayInfo,
                            onSelect: { onSelectDate(dayInfo.date) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Calendar Computation

    private func shiftMonth(by offset: Int) {
        guard let newMonth = Calendar.current.date(
            byAdding: .month, value: offset, to: displayedMonth
        ) else { return }
        displayedMonth = newMonth
    }

    private func calendarWeeks() -> [[CalendarDayInfo]] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: components) else { return [] }
        guard let rangeOfMonth = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        // Monday = 1 in ISO calendar. Adjust weekday to Mon=0 start.
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        // Convert: Sun=1,Mon=2,...,Sat=7 => Mon=0,Tue=1,...,Sun=6
        let mondayOffset = (firstWeekday + 5) % 7

        var days: [CalendarDayInfo] = []

        // Previous month overflow
        for daysBefore in stride(from: mondayOffset - 1, through: 0, by: -1) {
            guard let prevDate = calendar.date(
                byAdding: .day, value: -(daysBefore + 1), to: firstOfMonth
            ) else { continue }
            let identifier = Self.dayIdentifierFormatter.string(from: prevDate)
            days.append(CalendarDayInfo(
                date: prevDate,
                dayNumber: calendar.component(.day, from: prevDate),
                isCurrentMonth: false,
                isToday: calendar.isDateInToday(prevDate),
                hasNote: noteDates.contains(identifier)
            ))
        }

        // Current month days
        for day in rangeOfMonth {
            guard let date = calendar.date(
                byAdding: .day, value: day - 1, to: firstOfMonth
            ) else { continue }
            let identifier = Self.dayIdentifierFormatter.string(from: date)
            days.append(CalendarDayInfo(
                date: date,
                dayNumber: day,
                isCurrentMonth: true,
                isToday: calendar.isDateInToday(date),
                hasNote: noteDates.contains(identifier)
            ))
        }

        // Next month overflow to complete final week
        let remainder = days.count % 7
        if remainder > 0 {
            let overflow = 7 - remainder
            guard let lastOfMonth = calendar.date(
                byAdding: .day, value: rangeOfMonth.count - 1, to: firstOfMonth
            ) else { return [] }
            for dayAfter in 1...overflow {
                guard let nextDate = calendar.date(
                    byAdding: .day, value: dayAfter, to: lastOfMonth
                ) else { continue }
                let identifier = Self.dayIdentifierFormatter.string(from: nextDate)
                days.append(CalendarDayInfo(
                    date: nextDate,
                    dayNumber: calendar.component(.day, from: nextDate),
                    isCurrentMonth: false,
                    isToday: calendar.isDateInToday(nextDate),
                    hasNote: noteDates.contains(identifier)
                ))
            }
        }

        // Split into weeks of 7
        var weeks: [[CalendarDayInfo]] = []
        var weekBuffer: [CalendarDayInfo] = []
        for dayInfo in days {
            weekBuffer.append(dayInfo)
            if weekBuffer.count == 7 {
                weeks.append(weekBuffer)
                weekBuffer = []
            }
        }
        if !weekBuffer.isEmpty {
            weeks.append(weekBuffer)
        }

        return weeks
    }
}

// MARK: - Calendar Day Info

struct CalendarDayInfo: Hashable {
    let date: Date
    let dayNumber: Int
    let isCurrentMonth: Bool
    let isToday: Bool
    let hasNote: Bool
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let dayInfo: CalendarDayInfo
    let onSelect: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            Text("\(dayInfo.dayNumber)")
                .font(.system(size: 12, weight: dayInfo.isToday ? .bold : .regular))
                .foregroundStyle(dayForegroundStyle)
                .frame(width: 26, height: 26)
                .background {
                    if dayInfo.isToday {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 24, height: 24)
                    } else if isHovering {
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 24, height: 24)
                    }
                }
                .overlay(alignment: .bottom) {
                    if dayInfo.hasNote && !dayInfo.isToday {
                        Circle()
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .offset(y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var dayForegroundStyle: some ShapeStyle {
        if dayInfo.isToday {
            return AnyShapeStyle(.white)
        } else if !dayInfo.isCurrentMonth {
            return AnyShapeStyle(.tertiary)
        } else {
            return AnyShapeStyle(.primary)
        }
    }
}
