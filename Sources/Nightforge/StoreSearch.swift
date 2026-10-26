import Foundation

/// Searches the Steam store, without login or API key. Two public endpoints together: the store's
/// own search with the "games only" filter decides which hits are games (no DLC, soundtracks or
/// tools), and the store search API adds price, platforms and Metacritic score where it has them.
/// Both are undocumented; if either fails, the library search simply shows no store hits.
actor StoreSearch {
    static let shared = StoreSearch()

    struct Hit: Hashable {
        let appID: Int
        let name: String
        var price: String?
        var macNative: Bool?
        var metascore: Int?
        var controller: ControllerSupport?
    }

    private var results: [String: [Hit]] = [:]
    private var details: [Int: Hit] = [:]

    private static let maxHits = 12

    func search(_ term: String) async -> [Hit] {
        let key = term.lowercased()
        if let cached = results[key] { return cached }

        async let gamesOnly = Self.gameHits(term)
        async let withDetails = Self.detailedHits(term)
        let (games, detailed) = await (gamesOnly, withDetails)
        guard let games else { return [] }  // offline or changed: no store hits, nothing breaks

        let known = Dictionary((detailed ?? []).map { ($0.appID, $0) }, uniquingKeysWith: { first, _ in first })
        let hits = games.prefix(Self.maxHits).map { known[$0.appID] ?? $0 }
        results[key] = hits
        return hits
    }

    /// Price, platforms and score for one game, for hits the search API didn't cover.
    func details(for appID: Int) async -> Hit? {
        if let cached = details[appID] { return cached }
        var components = URLComponents(string: "https://store.steampowered.com/api/appdetails")!
        components.queryItems = [
            URLQueryItem(name: "appids", value: String(appID)),
            URLQueryItem(name: "filters", value: "basic,price_overview,platforms,metacritic,release_date"),
        ] + Self.regionItems
        guard let json = await Self.json(components.url),
              let entry = (json as? [String: Any])?[String(appID)] as? [String: Any],
              entry["success"] as? Bool == true,
              let data = entry["data"] as? [String: Any],
              let name = data["name"] as? String
        else { return nil }

        var hit = Hit(appID: appID, name: name)
        if data["is_free"] as? Bool == true {
            hit.price = L10n.t("Free")
        } else if let price = data["price_overview"] as? [String: Any] {
            hit.price = price["final_formatted"] as? String
        } else if (data["release_date"] as? [String: Any])?["coming_soon"] as? Bool == true {
            hit.price = L10n.t("Coming soon")
        }
        hit.macNative = (data["platforms"] as? [String: Any])?["mac"] as? Bool
        hit.metascore = (data["metacritic"] as? [String: Any])?["score"] as? Int
        hit.controller = (data["controller_support"] as? String).flatMap { ControllerSupport(rawValue: $0.lowercased()) } ?? ControllerSupport.none
        details[appID] = hit
        return hit
    }

    // MARK: - Requests

    /// "Games only" store search: names and app IDs, in the store's relevance order.
    private static func gameHits(_ term: String) async -> [Hit]? {
        var components = URLComponents(string: "https://store.steampowered.com/search/results/")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "category1", value: "998"),  // games
            URLQueryItem(name: "json", value: "1"),
        ] + regionItems
        guard let items = (await json(components.url) as? [String: Any])?["items"] as? [[String: Any]] else { return nil }
        // Only apps (bundles and packages have no app ID); the ID sits in the image URL.
        return items.compactMap { item in
            guard let name = item["name"] as? String, let logo = item["logo"] as? String,
                  let range = logo.range(of: #"/apps/(\d+)/"#, options: .regularExpression)
            else { return nil }
            let digits = logo[range].dropFirst("/apps/".count).dropLast()
            return Int(digits).map { Hit(appID: $0, name: name) }
        }
    }

    /// The search API: up to ten hits of any type, with price, platforms and score.
    private static func detailedHits(_ term: String) async -> [Hit]? {
        var components = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
        components.queryItems = [URLQueryItem(name: "term", value: term)] + regionItems
        guard let items = (await json(components.url) as? [String: Any])?["items"] as? [[String: Any]] else { return nil }
        return items.compactMap { item in
            guard let id = item["id"] as? Int, let name = item["name"] as? String else { return nil }
            var hit = Hit(appID: id, name: name)
            if let price = item["price"] as? [String: Any], let cents = price["final"] as? Int,
               let currency = price["currency"] as? String {
                hit.price = (Double(cents) / 100).formatted(.currency(code: currency).locale(L10n.locale))
            }
            hit.macNative = (item["platforms"] as? [String: Any])?["mac"] as? Bool
            hit.metascore = (item["metascore"] as? String).flatMap { Int($0) }
            return hit
        }
    }

    /// Prices for the Mac's region, texts in the app's language.
    private static var regionItems: [URLQueryItem] {
        [
            URLQueryItem(name: "cc", value: Locale.current.region?.identifier ?? "US"),
            URLQueryItem(name: "l", value: AppLanguage.current.resolved == .german ? "german" : "english"),
        ]
    }

    private static func json(_ url: URL?) async -> Any? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
