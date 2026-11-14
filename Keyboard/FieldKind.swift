import StoreKit
import UIKit

/// What the text field asks for, from its keyboard type: the bottom row
/// swaps the comma for "www." (web addresses) or "@" (email), and the
/// period's long-press offers domain endings.
enum FieldKind: Equatable {
    case text, url, email

    init(_ proxy: UITextDocumentProxy?) {
        guard let proxy else { self = .text; return }
        // Safari's address bar is a web search field.
        switch proxy.keyboardType {
        case .URL, .webSearch: self = .url
        case .emailAddress: self = .email
        default:
            switch proxy.textContentType {
            case .URL?: self = .url
            case .emailAddress?: self = .email
            default: self = .text
            }
        }
    }
}

/// Domain endings and email providers, the common ones first, then the
/// ones of the user's country: the App Store's (when StoreKit answers in
/// the keyboard), else the region in Settings.
enum Domains {
    /// ISO 3166 alpha-2, uppercase.
    private(set) static var region = Locale.current.region?.identifier.uppercased() ?? "US"

    /// Asks the App Store for its country once; the next layout picks it up.
    static func loadStorefront() {
        Task {
            guard let code = await Storefront.current?.countryCode,
                  let alpha2 = alpha2[code.uppercased()] else { return }
            await MainActor.run { region = alpha2 }
        }
    }

    /// Long-press on "." in a web address field, the first nearest the finger.
    static var web: [String] {
        Array(dedupe([".com"] + (webByRegion[region] ?? []) + [".org", ".net", ".io"]).prefix(5)) + ["/"]
    }

    /// Long-press on "." in an email field ("@gmail.com" replaces a domain
    /// already started after the @).
    static var mail: [String] {
        Array(dedupe(["gmail.com", "icloud.com"] + (mailByRegion[region] ?? []) + ["outlook.com", "yahoo.com", "hotmail.com"])
            .prefix(6)).map { "@" + $0 }
    }

    private static func dedupe(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    private static let webByRegion: [String: [String]] = [
        "JP": [".jp", ".co.jp"], "GB": [".co.uk", ".uk", ".gov.uk"], "US": [".edu", ".gov"],
        "FR": [".fr"], "DE": [".de"], "ES": [".es"], "IT": [".it"], "PT": [".pt"],
        "BR": [".com.br", ".br"], "KR": [".kr", ".co.kr"], "CA": [".ca"], "AU": [".com.au", ".au"],
        "NZ": [".co.nz", ".nz"], "IE": [".ie"], "CH": [".ch"], "AT": [".at"], "BE": [".be"],
        "NL": [".nl"], "MX": [".mx", ".com.mx"], "IN": [".in", ".co.in"], "CN": [".cn"],
        "TW": [".tw", ".com.tw"],
    ]

    private static let mailByRegion: [String: [String]] = [
        "JP": ["yahoo.co.jp", "docomo.ne.jp", "ezweb.ne.jp", "softbank.ne.jp"],
        "GB": ["yahoo.co.uk", "btinternet.com"], "FR": ["orange.fr", "free.fr"],
        "DE": ["gmx.de", "web.de", "t-online.de"], "IT": ["libero.it"], "KR": ["naver.com", "daum.net"],
        "BR": ["uol.com.br", "bol.com.br"], "CN": ["qq.com", "163.com"],
    ]

    /// The App Store gives alpha-3 codes; only the regions above matter.
    private static let alpha2: [String: String] = [
        "JPN": "JP", "GBR": "GB", "USA": "US", "FRA": "FR", "DEU": "DE", "ESP": "ES", "ITA": "IT",
        "PRT": "PT", "BRA": "BR", "KOR": "KR", "CAN": "CA", "AUS": "AU", "NZL": "NZ", "IRL": "IE",
        "CHE": "CH", "AUT": "AT", "BEL": "BE", "NLD": "NL", "MEX": "MX", "IND": "IN", "CHN": "CN",
        "TWN": "TW",
    ]
}
