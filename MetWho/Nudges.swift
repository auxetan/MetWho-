import UserNotifications

/// The one notification MetWho sends.
///
/// A contact app has an obvious and terrible notification strategy — ping about
/// every person, every week, forever. This sends one nudge, about the single
/// person you have gone longest without seeing, and only when there is somebody
/// who actually qualifies.
///
/// Everything is rescheduled from scratch on launch rather than kept in sync
/// incrementally: there are at most three pending requests, and reasoning about
/// drift between the store and the notification centre is not worth the code it
/// would take.
enum Nudges {

    private static let prefix = "metwho.refresher."

    /// Someone you saw last week is not someone you have forgotten.
    private static let staleAfterDays = 45

    static func authorize() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        let settings = await centre.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: (0..<3).map { "\(prefix)\($0)" }
        )
    }

    /// Three weekly nudges, each naming whoever is most overdue at that point.
    static func reschedule(for people: [Person]) async {
        cancelAll()

        let stale = people
            .filter { !$0.archived }
            .filter { Calendar.current.dateComponents([.day], from: $0.date, to: .now).day ?? 0 >= staleAfterDays }
            .sorted { $0.date < $1.date }
        guard !stale.isEmpty else { return }

        let centre = UNUserNotificationCenter.current()
        for (week, person) in stale.prefix(3).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = person.name
            content.body = person.summary.isEmpty
                ? "You have not looked at this one in a while."
                : person.summary
            content.sound = .default

            let delay = TimeInterval((week + 1) * 7 * 24 * 3600)
            try? await centre.add(UNNotificationRequest(
                identifier: "\(prefix)\(week)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            ))
        }
    }
}
