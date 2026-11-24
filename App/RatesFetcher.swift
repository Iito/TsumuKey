import BackgroundTasks
import Foundation

/// Keeps CurrencyRates fresh while Currency conversion is on: on app launch
/// and return to the front, and from a background refresh iOS runs about
/// once a day. One small file from the ECB; nothing is sent with the request.
enum RatesFetcher {
    /// Also listed in Info.plist (BGTaskSchedulerPermittedIdentifiers).
    static let taskID = "tsumukey-rates"

    enum FetchResult: Equatable {
        case saved
        /// Not on Wi-Fi and the user hasn't allowed mobile data for this download.
        case blockedOnMobileData
        case failed
    }

    /// Fetches when on and the saved rates are older than 12 hours. Automatic
    /// fetches never use mobile data; the user taps Download for that.
    static func refreshIfNeeded() async {
        guard KeyboardSettings.load().currencyConversion else { return }
        if let saved = CurrencyRates.load(), Date().timeIntervalSince(saved.date) < 12 * 3600 { return }
        _ = await fetch(allowCellular: false)
        schedule()
    }

    /// `allowCellular` false: iOS refuses the request on mobile data, which
    /// comes back as `.blockedOnMobileData` so the caller can ask first.
    static func fetch(allowCellular: Bool) async -> FetchResult {
        var request = URLRequest(url: CurrencyRates.source, timeoutInterval: 20)
        request.setValue("TsumuKey", forHTTPHeaderField: "User-Agent")
        request.allowsCellularAccess = allowCellular
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let rates = CurrencyRates(ecbXML: String(decoding: data, as: UTF8.self)) else { return .failed }
            rates.save()
            return .saved
        } catch let error as URLError where error.code == .dataNotAllowed {
            return .blockedOnMobileData
        } catch {
            return .failed
        }
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
