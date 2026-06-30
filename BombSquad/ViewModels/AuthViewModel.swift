import Foundation
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var signedInEmail: String?
    @Published var authMethodLabel: String?
    @Published var tenantID: UUID?
    @Published var accountSummary: BombSquadAccountSummary?
    @Published var isBusy = false
    @Published var hasSession = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let authClient: BombSquadAuthClient
    private var authStateTask: Task<Void, Never>?
    private var initializedUserID: UUID?

    init(authClient: BombSquadAuthClient = .shared) {
        self.authClient = authClient
        start()
    }

    deinit {
        authStateTask?.cancel()
    }

    var isConfigured: Bool {
        authClient.isConfigured
    }

    var canSendMagicLink: Bool {
        isConfigured && !isBusy && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSignInWithGoogle: Bool {
        isConfigured && !isBusy
    }

    func sendMagicLink() {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        statusMessage = nil

        Task {
            do {
                try await authClient.sendMagicLink(email: email)
                await MainActor.run {
                    self.email = self.email.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.statusMessage = "ログイン用メールを送信しました。この Mac でメール内のリンクを開いてください。"
                    self.isBusy = false
                }
            } catch {
                await present(error)
                await MainActor.run {
                    self.isBusy = false
                }
            }
        }
    }

    func signInWithGoogle() {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        statusMessage = nil

        Task {
            do {
                let session = try await authClient.signInWithGoogle()
                try await refreshState(session: session, shouldBootstrap: true)
                await MainActor.run {
                    self.statusMessage = "Google でログインしました。"
                    self.isBusy = false
                }
            } catch {
                await present(error)
                await MainActor.run {
                    self.isBusy = false
                }
            }
        }
    }

    func signOut() {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        statusMessage = nil

        Task {
            do {
                try await authClient.signOut()
                await MainActor.run {
                    self.initializedUserID = nil
                    self.tenantID = nil
                    self.accountSummary = nil
                    self.signedInEmail = nil
                    self.hasSession = false
                    self.statusMessage = "ログアウトしました。"
                    self.isBusy = false
                }
            } catch {
                await present(error)
                await MainActor.run {
                    self.isBusy = false
                }
            }
        }
    }

    private func start() {
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await change in authClient.authStateChanges() {
                if Task.isCancelled { break }
                await self.handleAuthStateChange(change)
            }
        }
    }

    private func handleAuthStateChange(_ change: BombSquadAuthClient.AuthStateChange) async {
        do {
            switch change.event {
            case .initialSession:
                try await refreshState(session: change.session, shouldBootstrap: change.session != nil)
            case .signedIn:
                try await refreshState(session: change.session, shouldBootstrap: true)
                statusMessage = authMethodLabel.map { "\($0)でログインしました。" } ?? "ログインしました。"
            case .tokenRefreshed, .userUpdated, .mfaChallengeVerified, .passwordRecovery:
                try await refreshState(session: change.session, shouldBootstrap: false)
            case .signedOut, .userDeleted:
                initializedUserID = nil
                tenantID = nil
                accountSummary = nil
                signedInEmail = nil
                authMethodLabel = nil
                hasSession = false
            }
        } catch {
            await present(error)
        }
    }

    private func refreshState(session: Session?, shouldBootstrap: Bool) async throws {
        guard let session else {
            initializedUserID = nil
            tenantID = nil
            signedInEmail = nil
            authMethodLabel = nil
            hasSession = false
            return
        }

        hasSession = true
        signedInEmail = session.user.email ?? authClient.currentUserEmail()
        authMethodLabel = authMethodLabel(for: session)
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let signedInEmail {
            email = signedInEmail
        }

        if shouldBootstrap && initializedUserID != session.user.id {
            tenantID = try await authClient.bootstrapCurrentUser()
            initializedUserID = session.user.id
        }

        accountSummary = try await authClient.fetchAccountSummary()
    }

    private func present(_ error: Error) async {
        await MainActor.run {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func authMethodLabel(for session: Session) -> String? {
        if let provider = session.user.appMetadata["provider"]?.stringValue {
            return providerLabel(for: provider)
        }

        if let provider = session.user.identities?.first?.provider {
            return providerLabel(for: provider)
        }

        if session.user.email != nil {
            return "メール"
        }

        return nil
    }

    private func providerLabel(for provider: String) -> String {
        switch provider.lowercased() {
        case "google":
            return "Google"
        case "apple":
            return "Apple"
        case "email":
            return "メール"
        default:
            return provider
        }
    }
}
