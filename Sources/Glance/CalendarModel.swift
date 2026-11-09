@preconcurrency import EventKit
import Foundation
import GlanceCore

/// Main-actor façade over the repository: per-month cache, coalesced
/// reloads after store changes, and change callbacks for the UI.
@MainActor
final class CalendarModel {
    enum Access: Equatable { case unknown, granted, denied, error(String) }

    let repository = EventRepository()
    private(set) var access: Access = .unknown
    private(set) var calendars: [CalendarInfo] = []
    private var cache = MonthCache<[DayKey: [EventSnapshot]]>(capacity: 12)
    private var wanted: [MonthKey] = []
    private var reloadTask: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    /// Called on the main actor whenever events or calendars change.
    var onChange: (() -> Void)?

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .autoupdatingCurrent
        c.locale = .autoupdatingCurrent
        return c
    }

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleReload() }
            })
    }

    func start() async {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--qa-access"), i + 1 < args.count {
            // QA: show an access state without touching the real permission.
            switch args[i + 1] {
            case "unknown": access = .unknown
            case "error": access = .error("The operation couldn’t be completed.")
            default: access = .denied
            }
            onChange?()
            return
        }
        switch EventRepository.authorization {
        case .fullAccess:
            access = .granted
        case .notDetermined:
            do {
                access = try await repository.requestAccess() ? .granted : .denied
            } catch {
                access = .error(error.localizedDescription)
            }
            if access == .granted { await repository.reset() }
        default:
            access = .denied
        }
        if access == .granted { await reloadCalendars() }
        onChange?()
        fetchMissing()
    }

    /// Re-check permission (e.g. after the user changes it in System Settings).
    func recheckAccess() {
        let granted = EventRepository.hasFullAccess
        if granted && access != .granted {
            access = .granted
            Task { await repository.reset(); await reloadCalendars(); reloadNow() }
        } else if !granted && access == .granted {
            access = .denied
            cache.removeAll()
            onChange?()
        }
    }

    // MARK: Events

    /// Declare which months the UI shows; fetches any that aren't cached.
    func show(_ range: VisibleRange) {
        wanted = range.months
        cache.touch(wanted)
        fetchMissing()
    }

    func events(on day: DayKey) -> [EventSnapshot] {
        cache.value(for: day.monthKey)?[day] ?? []
    }

    func eventsByDay(in range: VisibleRange) -> [DayKey: [EventSnapshot]] {
        var result: [DayKey: [EventSnapshot]] = [:]
        for m in range.months {
            guard let v = cache.value(for: m) else { continue }
            result.merge(v) { a, _ in a }
        }
        return result
    }

    private func fetchMissing() {
        guard access == .granted else { return }
        let today = DayKey(date: Date(), calendar: calendar)
        // Today and tomorrow always stay loaded for the meeting indicator.
        let months = Array(Set(wanted + [today.monthKey, today.adding(days: 1).monthKey]))
        let missing = cache.missing(for: months).sorted()
        guard !missing.isEmpty else { return }
        let generation = cache.begin(missing)
        let ids = Preferences.shared.selectedCalendarIDs
        let cal = calendar
        let repo = repository
        Task {
            for month in missing {
                let events = await repo.events(in: month, calendarIDs: ids, calendar: cal)
                self.cache.store(events, for: month, generation: generation)
            }
            self.onChange?()
        }
    }

    /// Coalesce bursts of store-change notifications (a sync can post many) into one reload.
    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self.repository.reset()
            await self.reloadCalendars()
            self.reloadNow()
        }
    }

    /// Invalidate everything and refetch the visible months.
    func reloadNow() {
        cache.invalidate()
        fetchMissing()
    }

    /// Calendar selection changed: drop cached events (they were fetched for the old selection).
    func selectionChanged() {
        cache.removeAll()
        onChange?()
        fetchMissing()
    }

    func reloadCalendars() async {
        guard access == .granted else { return }
        calendars = await repository.calendars()
    }

    var calendarGroups: [CalendarSourceGroup] { CalendarGrouping.group(calendars) }

    var writableCalendars: [CalendarInfo] { calendars.filter(\.allowsModifications) }
}
