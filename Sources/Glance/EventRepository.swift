@preconcurrency import EventKit
import Foundation
import GlanceCore

/// Owns the EKEventStore. All EventKit work happens on this actor, off the
/// main thread; callers get Sendable snapshots back.
actor EventRepository {
    private let store = EKEventStore()

    nonisolated static var authorization: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    nonisolated static var hasFullAccess: Bool { authorization == .fullAccess }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    /// Forget cached EventKit objects (after a store change or permission grant).
    func reset() { store.reset() }

    func refreshSources() { store.refreshSourcesIfNecessary() }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event).map(Self.info)
    }

    func defaultCalendarID() -> String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    /// Events for one month, bucketed by day and clipped to the month.
    func events(in month: MonthKey, calendarIDs: Set<String>?, calendar: Calendar) -> [DayKey: [EventSnapshot]] {
        let all = store.calendars(for: .event)
        let cals = calendarIDs.map { ids in all.filter { ids.contains($0.calendarIdentifier) } } ?? all
        guard !cals.isEmpty else { return [:] }
        let start = month.firstDay.startDate(in: calendar)
        let end = month.lastDay.adding(days: 1).startDate(in: calendar)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        let snapshots = store.events(matching: predicate).compactMap { event -> EventSnapshot? in
            if Self.isDeclined(event) { return nil }
            return Self.snapshot(event)
        }
        return EventBucketing.bucket(snapshots, calendar: calendar, range: month.firstDay...month.lastDay)
    }

    func draft(for snapshot: EventSnapshot) -> EventDraft? {
        guard let e = occurrence(id: snapshot.eventIdentifier, start: snapshot.occurrenceStart) else { return nil }
        return EventDraft(eventIdentifier: e.eventIdentifier, occurrenceStart: e.startDate,
                          isRecurring: e.hasRecurrenceRules || e.isDetached,
                          title: e.title ?? "", isAllDay: e.isAllDay, start: e.startDate, end: e.endDate,
                          calendarID: e.calendar?.calendarIdentifier, location: e.location ?? "",
                          urlText: e.url?.absoluteString ?? "", notes: e.notes ?? "")
    }

    enum RepositoryError: LocalizedError {
        case eventNotFound
        case calendarNotFound

        var errorDescription: String? {
            switch self {
            case .eventNotFound: "This event no longer exists. It may have been deleted on another device."
            case .calendarNotFound: "The chosen calendar is no longer available. Choose another calendar."
            }
        }
    }

    /// Save a draft. `futureEvents` applies a change to a recurring event's later occurrences too.
    func save(_ draft: EventDraft, futureEvents: Bool, calendar: Calendar) throws {
        let event: EKEvent
        if let id = draft.eventIdentifier {
            guard let existing = occurrence(id: id, start: draft.occurrenceStart) else { throw RepositoryError.eventNotFound }
            event = existing
        } else {
            event = EKEvent(eventStore: store)
        }
        guard let calID = draft.calendarID, let cal = store.calendar(withIdentifier: calID) else {
            throw RepositoryError.calendarNotFound
        }
        let dates = draft.normalizedDates(calendar: calendar)
        event.title = draft.trimmedTitle
        event.isAllDay = draft.isAllDay
        event.startDate = dates.start
        // EventKit stores all-day end dates inclusively.
        event.endDate = draft.isAllDay ? dates.end.addingTimeInterval(-1) : dates.end
        event.calendar = cal
        event.location = draft.location.isEmpty ? nil : draft.location
        event.url = draft.url
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        if event.timeZone == nil, !draft.isAllDay { event.timeZone = calendar.timeZone }
        try store.save(event, span: futureEvents ? .futureEvents : .thisEvent, commit: true)
    }

    func delete(eventIdentifier: String, occurrenceStart: Date, futureEvents: Bool) throws {
        guard let e = occurrence(id: eventIdentifier, start: occurrenceStart) else { throw RepositoryError.eventNotFound }
        try store.remove(e, span: futureEvents ? .futureEvents : .thisEvent, commit: true)
    }

    // MARK: - Helpers

    /// The specific occurrence of a (possibly recurring) event.
    private func occurrence(id: String, start: Date?) -> EKEvent? {
        guard let first = store.event(withIdentifier: id) else { return nil }
        guard let start, first.startDate != start else { return first }
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-1),
                                                 end: start.addingTimeInterval(86_400 * 2),
                                                 calendars: first.calendar.map { [$0] })
        return store.events(matching: predicate).first { $0.eventIdentifier == id && $0.startDate == start } ?? first
    }

    private static func isDeclined(_ e: EKEvent) -> Bool {
        guard e.hasAttendees, let me = e.attendees?.first(where: \.isCurrentUser) else { return false }
        return me.participantStatus == .declined
    }

    private static func snapshot(_ e: EKEvent) -> EventSnapshot {
        let link = MeetingLinkParser.firstLink(location: e.location, url: e.url, notes: e.hasNotes ? e.notes : nil)
        return EventSnapshot(
            eventIdentifier: e.eventIdentifier ?? UUID().uuidString, occurrenceStart: e.startDate,
            title: (e.title?.isEmpty == false ? e.title : nil) ?? "Untitled",
            start: e.startDate, end: e.endDate.addingTimeInterval(e.isAllDay ? 1 : 0), isAllDay: e.isAllDay,
            calendarID: e.calendar?.calendarIdentifier ?? "", calendarTitle: e.calendar?.title ?? "",
            color: e.calendar.map { NSColorBridge.rgba($0.cgColor) } ?? RGBA(hex: 0x888888),
            location: e.location, url: e.url, notes: e.hasNotes ? e.notes : nil,
            meetingURL: link?.url, isRecurring: e.hasRecurrenceRules || e.isDetached,
            isEditable: e.calendar?.allowsContentModifications ?? false)
    }

    private static func info(_ c: EKCalendar) -> CalendarInfo {
        CalendarInfo(id: c.calendarIdentifier, title: c.title, sourceTitle: c.source?.title ?? "Other",
                     color: NSColorBridge.rgba(c.cgColor), allowsModifications: c.allowsContentModifications)
    }
}

enum NSColorBridge {
    static func rgba(_ cg: CGColor?) -> RGBA {
        guard let cg, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let c = cg.converted(to: srgb, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return RGBA(hex: 0x888888) }
        return RGBA(r: Double(comps[0]), g: Double(comps[1]), b: Double(comps[2]), a: Double(c.alpha))
    }
}
