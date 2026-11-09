import Foundation

/// Per-month event cache with generation tracking.
///
/// * `missing(for:)` says which months still need a fetch.
/// * `invalidate()` (store changed) bumps the generation and marks every
///   month stale, but keeps the old values so the UI never flashes empty.
/// * `store(_:for:generation:)` drops results from an older generation,
///   so a slow fetch that started before a change can't overwrite fresher data.
/// * Holds at most `capacity` months, evicting the least recently used.
public struct MonthCache<Value: Sendable>: Sendable {
    public private(set) var generation: Int = 0
    public let capacity: Int
    private var entries: [MonthKey: Entry] = [:]
    private var inFlight: [MonthKey: Int] = [:]
    private var clock: Int = 0

    private struct Entry: Sendable {
        var value: Value
        var generation: Int
        var lastUse: Int
    }

    public init(capacity: Int = 12) { self.capacity = max(1, capacity) }

    public func value(for month: MonthKey) -> Value? { entries[month]?.value }

    public func isFresh(_ month: MonthKey) -> Bool { entries[month]?.generation == generation }

    /// Months that are neither fresh nor already being fetched this generation.
    public func missing(for months: [MonthKey]) -> [MonthKey] {
        months.filter { !isFresh($0) && inFlight[$0] != generation }
    }

    /// Record that fetches for `months` have started; returns the generation to pass back to `store`.
    public mutating func begin(_ months: [MonthKey]) -> Int {
        for m in months { inFlight[m] = generation }
        return generation
    }

    /// Returns false (and stores nothing) if the result is from a stale generation.
    @discardableResult
    public mutating func store(_ value: Value, for month: MonthKey, generation g: Int) -> Bool {
        if inFlight[month] == g { inFlight[month] = nil }
        guard g == generation else { return false }
        clock += 1
        entries[month] = Entry(value: value, generation: g, lastUse: clock)
        evict(keeping: [month])
        return true
    }

    /// Mark months as used so eviction prefers others.
    public mutating func touch(_ months: [MonthKey]) {
        for m in months where entries[m] != nil {
            clock += 1
            entries[m]!.lastUse = clock
        }
    }

    public mutating func invalidate() {
        generation += 1
        inFlight.removeAll()
    }

    public mutating func removeAll() {
        entries.removeAll()
        invalidate()
    }

    public var count: Int { entries.count }

    private mutating func evict(keeping keep: Set<MonthKey>) {
        while entries.count > capacity {
            guard let victim = entries.filter({ !keep.contains($0.key) })
                .min(by: { $0.value.lastUse < $1.value.lastUse })?.key else { return }
            entries[victim] = nil
        }
    }
}

/// Which days the popover needs events for.
public struct VisibleRange: Equatable, Sendable {
    public var first: DayKey
    public var last: DayKey

    public init(first: DayKey, last: DayKey) {
        self.first = min(first, last)
        self.last = max(first, last)
    }

    /// The month grid plus the agenda's days (selected day + `agendaDays` - 1).
    public init(grid: MonthGrid, selected: DayKey, agendaDays: Int) {
        let agendaEnd = selected.adding(days: max(1, agendaDays) - 1)
        self.init(first: min(grid.firstDay, selected), last: max(grid.lastDay, agendaEnd))
    }

    public var months: [MonthKey] { MonthKey.months(covering: first, last) }
}
