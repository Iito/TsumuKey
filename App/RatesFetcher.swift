import BackgroundTasks
import Foundation

/// Keeps CurrencyRates fresh while Currency conversion is on: on app launch
/// and return to the front, and from a background refresh iOS runs about
/// once a day. One small file from the ECB; nothing is sent with the request.
enum RatesFetcher {
    /// Also listed in Info.plist (BGTaskSchedulerPermittedIdentifiers).
    static let taskID = "tsumukey-rates"

    /// Fetches when on and the saved rates are older than 12 hours.
    static func refreshIfNeeded() async {
        guard KeyboardSettings.load().currencyConversion else { return }
        if let saved = CurrencyRates.load(), Date().timeIntervalSince(saved.date) < 12 * 3600 { return }
        await fetch()
        schedule()
    }

    static func fetch() async {
        var request = URLRequest(url: CurrencyRates.source, timeoutInterval: 20)
        request.setValue("TsumuKey", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rates = CurrencyRates(ecbXML: String(decoding: data, as: UTF8.self)) else { return }
        rates.save()
    }

    static func schedule() {
        guard KeyboardSettings.load().currencyConversion else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
