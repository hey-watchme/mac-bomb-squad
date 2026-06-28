import Foundation

/// Runtime config for product-facing services that will replace local-only API
/// keys as auth and the shared backend come online.
enum BombSquadConfig {
    struct Entry {
        let key: String
        let value: String?

        var isConfigured: Bool {
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var redactedValue: String {
            guard let value, isConfigured else { return "未設定" }
            if value.count <= 10 { return value }
            return "\(value.prefix(6))...\(value.suffix(4))"
        }
    }

    struct Snapshot {
        let apiBaseURL: Entry
        let supabaseURL: Entry
        let supabaseAnonKey: Entry

        var hasSupabaseConfig: Bool {
            supabaseURL.isConfigured && supabaseAnonKey.isConfigured
        }

        var hasBackendConfig: Bool {
            apiBaseURL.isConfigured
        }
    }

    static let apiBaseURLKey = "BOMB_SQUAD_API_BASE_URL"
    static let supabaseURLKey = "BOMB_SQUAD_SUPABASE_URL"
    static let supabaseAnonKey = "BOMB_SQUAD_SUPABASE_ANON_KEY"

    static func snapshot(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> Snapshot {
        Snapshot(
            apiBaseURL: entry(for: apiBaseURLKey, bundle: bundle, environment: environment),
            supabaseURL: entry(for: supabaseURLKey, bundle: bundle, environment: environment),
            supabaseAnonKey: entry(for: supabaseAnonKey, bundle: bundle, environment: environment)
        )
    }

    private static func entry(for key: String, bundle: Bundle, environment: [String: String]) -> Entry {
        let environmentValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentValue, !environmentValue.isEmpty {
            return Entry(key: key, value: environmentValue)
        }

        let plistValue = (bundle.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let plistValue, !plistValue.isEmpty {
            return Entry(key: key, value: plistValue)
        }

        return Entry(key: key, value: nil)
    }
}
