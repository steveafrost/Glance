import XCTest
@testable import GlanceCore

final class MeetingLinkTests: XCTestCase {
    func provider(_ s: String) -> MeetingProvider? { MeetingLinkParser.firstLink(in: s)?.provider }

    func testRecognisesMainProviders() {
        XCTAssertEqual(provider("https://us02web.zoom.us/j/81234567890?pwd=abc"), .zoom)
        XCTAssertEqual(provider("Join: https://zoomgov.com/j/123"), .zoom)
        XCTAssertEqual(provider("https://meet.google.com/abc-defg-hij"), .googleMeet)
        XCTAssertEqual(provider("https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d"), .teams)
        XCTAssertEqual(provider("https://teams.live.com/meet/9876543210"), .teams)
        XCTAssertEqual(provider("https://acme.webex.com/acme/j.php?MTID=m123"), .webex)
        XCTAssertEqual(provider("https://acme.webex.com/meet/jdoe"), .webex)
    }

    func testFindsLinkInsideProse() {
        let notes = """
        Hi team,
        ──────────
        Join Zoom Meeting
        https://shopify.zoom.us/j/99999999999?pwd=xyz (passcode 1234).
        Dial in: +1 555 0100
        """
        let link = MeetingLinkParser.firstLink(in: notes)
        XCTAssertEqual(link?.provider, .zoom)
        XCTAssertEqual(link?.url.absoluteString, "https://shopify.zoom.us/j/99999999999?pwd=xyz")
    }

    func testAngleBracketedOutlookLink() {
        let notes = "Microsoft Teams meeting <https://teams.microsoft.com/l/meetup-join/abc>"
        XCTAssertEqual(provider(notes), .teams)
    }

    func testRejectsLookalikes() {
        XCTAssertNil(provider("https://evil.example/zoom.us/j/123"))
        XCTAssertNil(provider("https://zoom.us.evil.example/j/123"))
        XCTAssertNil(provider("https://notzoom.us/j/123"))
        XCTAssertNil(provider("https://zoom.us/pricing"))
        XCTAssertNil(provider("https://meet.google.com/"))
        XCTAssertNil(provider("https://teams.microsoft.com/downloads"))
        XCTAssertNil(provider("https://example.com"))
        XCTAssertNil(provider(""))
    }

    func testAppSchemes() {
        XCTAssertEqual(MeetingLinkParser.classify(URL(string: "zoommtg://zoom.us/join?confno=1")!)?.provider, .zoom)
        XCTAssertEqual(MeetingLinkParser.classify(URL(string: "msteams://teams.microsoft.com/l/meetup-join/x")!)?.provider, .teams)
    }

    func testFieldPriorityLocationThenURLThenNotes() {
        let link = MeetingLinkParser.firstLink(
            location: "Room 4",
            url: URL(string: "https://meet.google.com/aaa-bbbb-ccc"),
            notes: "https://zoom.us/j/1")
        XCTAssertEqual(link?.provider, .googleMeet)
        let fromLocation = MeetingLinkParser.firstLink(location: "https://zoom.us/j/1", url: nil, notes: nil)
        XCTAssertEqual(fromLocation?.provider, .zoom)
        XCTAssertNil(MeetingLinkParser.firstLink(location: nil, url: URL(string: "https://example.com"), notes: "none"))
    }

    func testZoomAppRewriteWhenInstalled() {
        let link = MeetingLinkParser.classify(URL(string: "https://acme.zoom.us/j/123456?pwd=s3cret")!)!
        let app = MeetingLinkParser.preferredURL(for: link) { _ in true }
        XCTAssertEqual(app.absoluteString, "zoommtg://acme.zoom.us/join?confno=123456&pwd=s3cret")
        let web = MeetingLinkParser.preferredURL(for: link) { _ in false }
        XCTAssertEqual(web, link.url)
    }

    func testPersonalZoomLinksStayWeb() {
        let link = MeetingLinkParser.classify(URL(string: "https://zoom.us/my/jdoe")!)!
        XCTAssertEqual(MeetingLinkParser.preferredURL(for: link) { _ in true }, link.url)
    }

    func testTeamsAppRewrite() {
        let link = MeetingLinkParser.classify(URL(string: "https://teams.microsoft.com/l/meetup-join/abc")!)!
        XCTAssertEqual(MeetingLinkParser.preferredURL(for: link) { _ in true }.absoluteString,
                       "msteams://teams.microsoft.com/l/meetup-join/abc")
    }
}

final class MeetingScheduleTests: XCTestCase {
    let cal = gregorian()

    func testInactiveBeforeLeadWindowWithNextChange() {
        let e = event("standup", date(2026, 11, 9, 10), date(2026, 11, 9, 10, 15), meeting: "https://zoom.us/j/1")
        let s = MeetingSchedule.state(events: [e], now: date(2026, 11, 9, 9, 30), lead: 300)
        XCTAssertNil(s.activeEventID)
        XCTAssertEqual(s.nextChange, date(2026, 11, 9, 9, 55))
    }

    func testActiveDuringLeadAndMeeting() {
        let e = event("standup", date(2026, 11, 9, 10), date(2026, 11, 9, 10, 15), meeting: "https://zoom.us/j/1")
        let imminent = MeetingSchedule.state(events: [e], now: date(2026, 11, 9, 9, 57), lead: 300)
        XCTAssertEqual(imminent.activeEventID, e.id)
        XCTAssertEqual(imminent.nextChange, date(2026, 11, 9, 10))
        let during = MeetingSchedule.state(events: [e], now: date(2026, 11, 9, 10, 5), lead: 300)
        XCTAssertEqual(during.activeEventID, e.id)
        XCTAssertEqual(during.nextChange, date(2026, 11, 9, 10, 15))
        let after = MeetingSchedule.state(events: [e], now: date(2026, 11, 9, 10, 15), lead: 300)
        XCTAssertNil(after.activeEventID)
        XCTAssertNil(after.nextChange)
    }

    func testIgnoresAllDayAndLinklessEvents() {
        let allDay = event("offsite", date(2026, 11, 9), date(2026, 11, 10), allDay: true, meeting: "https://zoom.us/j/1")
        let noLink = event("lunch", date(2026, 11, 9, 12), date(2026, 11, 9, 13))
        let s = MeetingSchedule.state(events: [allDay, noLink], now: date(2026, 11, 9, 12, 30), lead: 300)
        XCTAssertNil(s.activeEventID)
    }

    func testUpcomingMeetingBeatsOneThatIsEnding() {
        let ending = event("a", date(2026, 11, 9, 9), date(2026, 11, 9, 10), meeting: "https://zoom.us/j/1")
        let next = event("b", date(2026, 11, 9, 10), date(2026, 11, 9, 11), meeting: "https://meet.google.com/x-y-z")
        let s = MeetingSchedule.state(events: [ending, next], now: date(2026, 11, 9, 9, 58), lead: 300)
        XCTAssertEqual(s.activeEventID, next.id)
    }
}
