import Foundation

/// Exchange rates for "100$ in €=" in the keyboard's bar. The app fetches the
/// European Central Bank's daily reference rates (only with Currency
/// conversion on) and saves them here; the keyboard only reads this copy and
/// never goes online.
struct CurrencyRates: Codable, Equatable {
    /// The ECB's date for these rates (they publish on working days, ~16:00 CET).
    var date: Date
    /// Units of each currency for one euro; EUR itself is 1.
    var perEuro: [String: Double]

    static let source = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    private static let key = "currencyRates"

    static func load() -> CurrencyRates? { SharedSettings.load(Self.self, key: key) }
    func save() { SharedSettings.save(self, key: Self.key) }  // notifies an open keyboard
    static func clear() { SharedSettings.defaults.removeObject(forKey: key) }

    /// Parses the ECB XML: <Cube time='2026-11-06'> then <Cube currency='USD' rate='1.1165'/>.
    init?(ecbXML xml: String) {
        let day = /time='(\d{4}-\d{2}-\d{2})'/
        guard let match = xml.firstMatch(of: day) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: String(match.1)) else { return nil }
        var rates = ["EUR": 1.0]
        for m in xml.matches(of: /currency='([A-Z]{3})' rate='([0-9.]+)'/) {
            if let r = Double(m.2), r > 0 { rates[String(m.1)] = r }
        }
        guard rates.count > 10 else { return nil }
        self.date = date
        self.perEuro = rates
    }
}
