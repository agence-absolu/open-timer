import Foundation

struct OpenProjectError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Client minimal de l'API REST v3 d'OpenProject.
/// Authentification par token : Basic base64("apikey:<token>").
struct OpenProjectAPI {
    let baseURL: URL
    let token: String

    private var authHeader: String {
        "Basic " + Data("apikey:\(token)".utf8).base64EncodedString()
    }

    // MARK: - Endpoints

    /// Utilisateur courant — sert aussi de test de connexion.
    func currentUser() async throws -> String {
        let data = try await send(request(path: "api/v3/users/me"))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["name"] as? String) ?? "Utilisateur inconnu"
    }

    /// Work packages assignés à l'utilisateur courant et dont le statut est ouvert.
    func myWorkPackages() async throws -> [WorkPackage] {
        try await fetchWorkPackages(filters: [
            ["assignee": ["operator": "=", "values": ["me"]]],
            ["status": ["operator": "o", "values": []]],
        ])
    }

    /// Recherche parmi tous les WP ouverts — assignés ou non. Sert à travailler sur un
    /// work package assigné à quelqu'un d'autre.
    ///
    /// Saisie purement numérique (avec « # » optionnel) → recherche par **id exact**
    /// (le filtre plein-texte `**` ne matche pas les identifiants) ; on ne restreint
    /// alors pas au statut ouvert, pour retrouver le WP même s'il est clos. Sinon,
    /// recherche plein-texte (libellé…) sur les WP ouverts.
    func searchWorkPackages(matching query: String, limit: Int = 50) async throws -> [WorkPackage] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        if !digits.isEmpty, digits.allSatisfy(\.isNumber) {
            return try await fetchWorkPackages(filters: [
                ["id": ["operator": "=", "values": [digits]]],
            ], pageSize: limit)
        }

        return try await fetchWorkPackages(filters: [
            ["search": ["operator": "**", "values": [trimmed]]],
            ["status": ["operator": "o", "values": []]],
        ], pageSize: limit)
    }

    /// Requête `work_packages` filtrée, triée par mise à jour décroissante.
    private func fetchWorkPackages(filters: [[String: Any]], pageSize: Int = 100) async throws -> [WorkPackage] {
        let filtersJSON = String(decoding: try JSONSerialization.data(withJSONObject: filters), as: UTF8.self)
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/v3/work_packages"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(name: "filters", value: filtersJSON),
            URLQueryItem(name: "sortBy", value: #"[["updatedAt","desc"]]"#),
        ]
        // URLComponents encode l'espace en '+' dans la query ; OpenProject veut %2B.
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        let data = try await send(request(url: comps.url!))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let elements = (obj?["_embedded"] as? [String: Any])?["elements"] as? [[String: Any]] ?? []
        return elements.compactMap { el in
            guard let id = el["id"] as? Int, let subject = el["subject"] as? String else { return nil }
            let project = (el["_links"] as? [String: Any])?["project"] as? [String: Any]
            return WorkPackage(id: id, subject: subject, projectName: project?["title"] as? String)
        }
    }

    /// Activités de temps autorisées pour un work package, via le formulaire de création.
    func activities(forWorkPackageHref href: String) async throws -> [Activity] {
        let body = try JSONSerialization.data(
            withJSONObject: ["_links": ["workPackage": ["href": href]]]
        )
        let data = try await send(request(path: "api/v3/time_entries/form", method: "POST", body: body))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let schema = (obj?["_embedded"] as? [String: Any])?["schema"] as? [String: Any]
        let activity = schema?["activity"] as? [String: Any]
        let allowed = (activity?["_embedded"] as? [String: Any])?["allowedValues"] as? [[String: Any]] ?? []
        return allowed.compactMap { value in
            let selfLink = (value["_links"] as? [String: Any])?["self"] as? [String: Any]
            guard let href = selfLink?["href"] as? String else { return nil }
            let name = (value["name"] as? String) ?? (selfLink?["title"] as? String) ?? "Activité"
            return Activity(href: href, name: name)
        }
    }

    /// Crée un time entry. `hours` est une durée ISO 8601 (ex. "PT1H23M").
    func createTimeEntry(
        workPackageHref: String,
        hours: String,
        spentOn: String,
        comment: String,
        activityHref: String?
    ) async throws {
        var links: [String: Any] = ["workPackage": ["href": workPackageHref]]
        if let activityHref { links["activity"] = ["href": activityHref] }

        var payload: [String: Any] = [
            "hours": hours,
            "spentOn": spentOn,
            "_links": links,
        ]
        if !comment.isEmpty { payload["comment"] = ["raw": comment] }

        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await send(request(path: "api/v3/time_entries", method: "POST", body: body))
    }

    /// Dernières saisies de temps de l'utilisateur courant (plus récentes d'abord).
    func recentTimeEntries(limit: Int = 20) async throws -> [TimeEntry] {
        let filters = #"[{"user":{"operator":"=","values":["me"]}}]"#
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/v3/time_entries"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "pageSize", value: "\(limit)"),
            URLQueryItem(name: "filters", value: filters),
            URLQueryItem(name: "sortBy", value: #"[["spentOn","desc"],["createdAt","desc"]]"#),
        ]
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        let data = try await send(request(url: comps.url!))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let elements = (obj?["_embedded"] as? [String: Any])?["elements"] as? [[String: Any]] ?? []
        return elements.compactMap(Self.parseTimeEntry)
    }

    /// Met à jour une saisie (durée, date, commentaire, + heures début/fin si supportées).
    func updateTimeEntry(
        id: Int,
        seconds: Int,
        spentOn: String,
        comment: String,
        lockVersion: Int?,
        startTimeUTC: String? = nil,
        endTimeUTC: String? = nil
    ) async throws {
        var payload: [String: Any] = [
            "hours": Self.isoDurationPrecise(seconds: seconds),
            "spentOn": spentOn,
            "comment": ["raw": comment],
        ]
        if let startTimeUTC { payload["startTime"] = startTimeUTC }
        if let endTimeUTC { payload["endTime"] = endTimeUTC }
        if let lockVersion { payload["lockVersion"] = lockVersion }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await send(request(path: "api/v3/time_entries/\(id)", method: "PATCH", body: body))
    }

    /// Supprime une saisie.
    func deleteTimeEntry(id: Int) async throws {
        _ = try await send(request(path: "api/v3/time_entries/\(id)", method: "DELETE"))
    }

    private static func parseTimeEntry(_ el: [String: Any]) -> TimeEntry? {
        guard let id = el["id"] as? Int else { return nil }
        let links = el["_links"] as? [String: Any]
        let wp = links?["workPackage"] as? [String: Any]
        let project = links?["project"] as? [String: Any]
        let comment = (el["comment"] as? [String: Any])?["raw"] as? String ?? ""
        let spentOn = el["spentOn"] as? String ?? ""
        let hours = el["hours"] as? String ?? "PT0S"
        return TimeEntry(
            id: id,
            workPackageTitle: wp?["title"] as? String,
            workPackageHref: wp?["href"] as? String,
            projectTitle: project?["title"] as? String,
            comment: comment,
            spentOn: spentOn,
            seconds: seconds(fromISODuration: hours),
            startTime: parseUTC(el["startTime"] as? String),
            endTime: parseUTC(el["endTime"] as? String),
            lockVersion: el["lockVersion"] as? Int
        )
    }

    /// Indique si l'instance autorise les heures de début/fin (option admin
    /// `allow_tracking_start_and_end_times`), lu depuis le schéma du formulaire.
    func startEndSupported(forWorkPackageHref href: String?) async -> Bool {
        do {
            let payload: [String: Any] = href.map { ["_links": ["workPackage": ["href": $0]]] } ?? [:]
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await send(request(path: "api/v3/time_entries/form", method: "POST", body: body))
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let schema = (obj?["_embedded"] as? [String: Any])?["schema"] as? [String: Any]
            guard let start = schema?["startTime"] as? [String: Any] else { return false }
            return (start["writable"] as? Bool) ?? false
        } catch {
            return false
        }
    }

    // MARK: - Bas niveau

    private func request(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        request(url: baseURL.appendingPathComponent(path), method: method, body: body)
    }

    private func request(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OpenProjectError(message: "Réponse invalide du serveur.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let detail = Self.errorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw OpenProjectError(message: detail)
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
    }

    // MARK: - Utilitaires

    /// Convertit une durée en secondes vers une durée ISO 8601 arrondie à la minute (min. 1 min).
    static func isoDuration(seconds: Int) -> String {
        let totalMinutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        var out = "PT"
        if h > 0 { out += "\(h)H" }
        if m > 0 || h == 0 { out += "\(m)M" }
        return out
    }

    /// Durée ISO 8601 précise (heures/minutes/secondes exactes), pour l'édition.
    static func isoDurationPrecise(seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var out = "PT"
        if h > 0 { out += "\(h)H" }
        if m > 0 { out += "\(m)M" }
        if sec > 0 || (h == 0 && m == 0) { out += "\(sec)S" }
        return out
    }

    /// Parse une date-heure ISO 8601 UTC (avec ou sans fraction de seconde).
    static func parseUTC(_ text: String?) -> Date? {
        guard let text else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime]
        if let d = f1.date(from: text) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f2.date(from: text)
    }

    /// Sérialise un instant en date-heure ISO 8601 UTC (ex. "2026-07-27T17:32:00Z").
    static func utcString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Parse une durée ISO 8601 (ex. "PT1H30M15S") en secondes. Ignore les mois/années.
    static func seconds(fromISODuration text: String) -> Int {
        guard text.hasPrefix("P") else { return 0 }
        var total = 0
        var number = ""
        var inTime = false
        for ch in text.dropFirst() {
            switch ch {
            case "T":
                inTime = true
            case "0"..."9", ".":
                number.append(ch)
            case "D":
                total += Int(Double(number) ?? 0) * 86400; number = ""
            case "H":
                total += Int(Double(number) ?? 0) * 3600; number = ""
            case "M":
                if inTime { total += Int(Double(number) ?? 0) * 60 }  // sinon = mois, ignoré
                number = ""
            case "S":
                total += Int(Double(number) ?? 0); number = ""
            default:
                number = ""
            }
        }
        return total
    }
}
