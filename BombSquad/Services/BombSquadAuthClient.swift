import Foundation
import Supabase

enum BombSquadAuthError: LocalizedError {
    case missingConfiguration
    case invalidSupabaseURL(String)
    case invalidEmail
    case invalidVerificationCode

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Supabase の設定が不足しています。設定値を確認してください。"
        case .invalidSupabaseURL(let value):
            return "Supabase URL が不正です: \(value)"
        case .invalidEmail:
            return "メールアドレスを入力してください。"
        case .invalidVerificationCode:
            return "認証コードを入力してください。"
        }
    }
}

final class BombSquadAuthClient {
    static let shared = BombSquadAuthClient()

    typealias AuthStateChange = (event: AuthChangeEvent, session: Session?)

    private let config: BombSquadConfig.Snapshot
    private let client: SupabaseClient?

    init(config: BombSquadConfig.Snapshot = BombSquadConfig.snapshot()) {
        self.config = config

        guard config.hasSupabaseConfig else {
            self.client = nil
            return
        }

        guard let urlString = config.supabaseURL.value else {
            self.client = nil
            return
        }

        guard let url = URL(string: urlString) else {
            self.client = nil
            return
        }

        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: config.supabaseAnonKey.value ?? "",
            options: SupabaseClientOptions(
                auth: .init(
                    autoRefreshToken: true,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    var isConfigured: Bool {
        client != nil
    }

    func authStateChanges() -> AsyncStream<AuthStateChange> {
        guard let client else {
            return AsyncStream { continuation in
                continuation.yield((.initialSession, nil))
                continuation.finish()
            }
        }
        return client.auth.authStateChanges
    }

    func currentSession() -> Session? {
        client?.auth.currentSession
    }

    func currentUserEmail() -> String? {
        client?.auth.currentUser?.email
    }

    func sendEmailOTP(email: String) async throws {
        guard let client else {
            throw missingConfigurationError()
        }

        let normalizedEmail = normalize(email)
        guard isValidEmail(normalizedEmail) else {
            throw BombSquadAuthError.invalidEmail
        }

        try await client.auth.signInWithOTP(email: normalizedEmail)
    }

    @discardableResult
    func verifyEmailOTP(email: String, token: String) async throws -> Session {
        guard let client else {
            throw missingConfigurationError()
        }

        let normalizedEmail = normalize(email)
        guard isValidEmail(normalizedEmail) else {
            throw BombSquadAuthError.invalidEmail
        }

        let normalizedToken = normalize(token)
        guard !normalizedToken.isEmpty else {
            throw BombSquadAuthError.invalidVerificationCode
        }

        let response = try await client.auth.verifyOTP(
            email: normalizedEmail,
            token: normalizedToken,
            type: .email
        )

        guard let session = response.session else {
            throw BombSquadAuthError.invalidVerificationCode
        }

        return session
    }

    @discardableResult
    func bootstrapCurrentUser() async throws -> UUID {
        guard let client else {
            throw missingConfigurationError()
        }

        let tenantID: UUID = try await client.rpc("bs_initialize_current_user").execute().value
        return tenantID
    }

    func accessToken() async throws -> String {
        guard let client else {
            throw missingConfigurationError()
        }
        return try await client.auth.session.accessToken
    }

    func signOut() async throws {
        guard let client else {
            throw missingConfigurationError()
        }
        try await client.auth.signOut()
    }

    private func missingConfigurationError() -> Error {
        if let value = config.supabaseURL.value,
           URL(string: value) == nil {
            return BombSquadAuthError.invalidSupabaseURL(value)
        }
        return BombSquadAuthError.missingConfiguration
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isValidEmail(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.contains("@") && value.contains(".")
    }
}
