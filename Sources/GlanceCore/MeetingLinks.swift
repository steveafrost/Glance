import Foundation

public enum MeetingProvider: String, Sendable, CaseIterable {
    case zoom, googleMeet, teams, webex, facetime, jitsi, chime, gotoMeeting, whereby, slack

    public var displayName: String {
        switch self {
        case .zoom: "Zoom"
        case .googleMeet: "Google Meet"
        case .teams: "Microsoft Teams"
        case .webex: "Webex"
        case .facetime: "FaceTime"
        case .jitsi: "Jitsi Meet"
        case .chime: "Amazon Chime"
        case .gotoMeeting: "GoTo Meeting"
        case .whereby: "Whereby"
        case .slack: "Slack Huddle"
        }
    }
}

public struct MeetingLink: Hashable, Sendable {
    public var url: URL
    public var provider: MeetingProvider
}

public enum MeetingLinkParser {
    private static let detector: NSDataDetector? =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// First meeting link in location, then URL, then notes.
    public static func firstLink(location: String?, url: URL?, notes: String?) -> MeetingLink? {
        if let location, let link = firstLink(in: location) { return link }
        if let url, let link = classify(url) { return link }
        if let notes, let link = firstLink(in: notes) { return link }
        return nil
    }

    /// First meeting link anywhere in free text.
    public static func firstLink(in text: String) -> MeetingLink? {
        guard !text.isEmpty, let detector else { return nil }
        var found: MeetingLink?
        let ns = text as NSString
        detector.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) { result, _, stop in
            if let url = result?.url, let link = classify(url) {
                found = link
                stop.pointee = true
            }
        }
        return found
    }

    /// Classify by scheme and host (never by substring, so
    /// `https://evil.example/zoom.us/j/1` is not a Zoom link).
    public static func classify(_ url: URL) -> MeetingLink? {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let path = url.path

        func hostIs(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        func web(_ p: MeetingProvider) -> MeetingLink? {
            (scheme == "https" || scheme == "http") ? MeetingLink(url: url, provider: p) : nil
        }

        switch scheme {
        case "zoommtg", "zoomus": return MeetingLink(url: url, provider: .zoom)
        case "msteams": return MeetingLink(url: url, provider: .teams)
        case "webex", "wbx": return MeetingLink(url: url, provider: .webex)
        case "chime": return MeetingLink(url: url, provider: .chime)
        default: break
        }

        if hostIs("zoom.us") || hostIs("zoomgov.com") {
            let prefixes = ["/j/", "/s/", "/w/", "/my/", "/wc/join/"]
            return prefixes.contains(where: path.hasPrefix) ? web(.zoom) : nil
        }
        if host == "meet.google.com" {
            // meet.google.com/abc-defg-hij (or /lookup/…); not the bare landing page.
            let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return trimmed.isEmpty || trimmed == "landing" ? nil : web(.googleMeet)
        }
        if hostIs("teams.microsoft.com") || hostIs("teams.live.com") {
            let prefixes = ["/l/meetup-join/", "/meet/", "/l/meet/", "/v2/"]
            return prefixes.contains(where: path.hasPrefix) ? web(.teams) : nil
        }
        if hostIs("webex.com") {
            return path.count > 1 ? web(.webex) : nil
        }
        if host == "facetime.apple.com", path.hasPrefix("/join") { return web(.facetime) }
        if host == "meet.jit.si" { return path.count > 1 ? web(.jitsi) : nil }
        if hostIs("chime.aws") { return path.count > 1 ? web(.chime) : nil }
        if hostIs("gotomeeting.com") || hostIs("gotomeet.me") || hostIs("meet.goto.com") {
            return path.count > 1 ? web(.gotoMeeting) : nil
        }
        if host == "whereby.com" { return path.count > 1 ? web(.whereby) : nil }
        if hostIs("slack.com"), path.contains("/huddle/") { return web(.slack) }
        return nil
    }

    /// Native-app variant of a web link when the app is installed, else the link itself.
    /// `canOpen` answers whether an app handles the given scheme URL.
    public static func preferredURL(for link: MeetingLink, canOpen: (URL) -> Bool) -> URL {
        let url = link.url
        guard url.scheme == "https" || url.scheme == "http",
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        switch link.provider {
        case .zoom:
            // https://zoom.us/j/123?pwd=x -> zoommtg://zoom.us/join?confno=123&pwd=x
            let parts = url.path.split(separator: "/")
            guard parts.count >= 2, ["j", "s", "w"].contains(String(parts[0])),
                  let probe = URL(string: "zoommtg://"), canOpen(probe) else { return url }
            let confno = String(parts[1])
            comps.scheme = "zoommtg"
            comps.path = "/join"
            comps.queryItems = [URLQueryItem(name: "confno", value: confno)] + (comps.queryItems ?? [])
            return comps.url ?? url
        case .teams:
            guard let probe = URL(string: "msteams://"), canOpen(probe) else { return url }
            comps.scheme = "msteams"
            return comps.url ?? url
        default:
            return url
        }
    }
}

/// Whether a meeting is current or imminent, and when that next changes.
public enum MeetingSchedule {
    public struct State: Equatable, Sendable {
        /// The meeting that is current or starts within the lead time, if any.
        public var activeEventID: String?
        /// When `activeEventID` may next change; nil if nothing is coming up.
        public var nextChange: Date?
    }

    /// Events must have a meeting link and not be all-day. An event is
    /// active from `lead` before its start until its end. When several are
    /// active, the one starting soonest after now wins (so the next call
    /// replaces one that is ending), else the most recently started.
    public static func state(events: [EventSnapshot], now: Date, lead: TimeInterval) -> State {
        let candidates = events.filter { $0.meetingURL != nil && !$0.isAllDay && $0.end > now }
        let active = candidates.filter { $0.start.addingTimeInterval(-lead) <= now }
        let chosen = active.min { a, b in
            let aUpcoming = a.start > now, bUpcoming = b.start > now
            if aUpcoming != bUpcoming { return aUpcoming }
            return aUpcoming ? a.start < b.start : a.start > b.start
        }
        var changes: [Date] = []
        for e in candidates {
            let opens = e.start.addingTimeInterval(-lead)
            if opens > now { changes.append(opens) }
            if e.start > now { changes.append(e.start) }
            changes.append(e.end)
        }
        return State(activeEventID: chosen?.id, nextChange: changes.filter { $0 > now }.min())
    }
}
