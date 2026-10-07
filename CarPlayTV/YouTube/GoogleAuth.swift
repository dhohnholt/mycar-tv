import AuthenticationServices
import CryptoKit
import UIKit

/// Google OAuth 2.0 (authorization code + PKCE) through the system sign-in sheet.
/// Google blocks sign-in inside embedded web views, so this is the only supported path.
@MainActor
final class GoogleAuth: NSObject, ObservableObject {
    static let shared = GoogleAuth()
    static let scope = "https://www.googleapis.com/auth/youtube.readonly"

    private struct Tokens: Codable {
        var access: String
        var refresh: String
        var expiry: Date
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    @Published private(set) var isSignedIn = false

    private var tokens: Tokens? {
        didSet {
            Keychain.save(tokens, for: "google.tokens")
            isSignedIn = tokens != nil
        }
    }

    private var authSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
        tokens = Keychain.load(Tokens.self, for: "google.tokens")
        isSignedIn = tokens != nil
    }

    var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? "").trimmed
    }

    var isConfigured: Bool { clientID.hasSuffix(".apps.googleusercontent.com") }

    /// iOS OAuth clients use the reversed client ID as their redirect scheme.
    private var redirectScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    private var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    func signIn() async throws {
        guard isConfigured else { throw AuthError.notConfigured }

        let verifier = Self.randomURLSafe(byteCount: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = Self.randomURLSafe(byteCount: 16)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callback: .customScheme(redirectScheme)) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            authSession = session
            session.start()
        }
        authSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.invalidResponse
        }

        tokens = try await requestTokens([
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ], existingRefresh: nil)
    }

    func accessToken() async throws -> String {
        guard let current = tokens else { throw AuthError.signedOut }
        if current.expiry > Date() { return current.access }
        do {
            let refreshed = try await requestTokens([
                "refresh_token": current.refresh,
                "client_id": clientID,
                "grant_type": "refresh_token",
            ], existingRefresh: current.refresh)
            tokens = refreshed
            return refreshed.access
        } catch AuthError.rejected {
            tokens = nil
            throw AuthError.signedOut
        }
    }

    func signOut() {
        if let token = tokens?.refresh {
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody(["token": token])
            Task { _ = try? await Net.session.data(for: request) }
        }
        tokens = nil
    }

    private func requestTokens(_ params: [String: String], existingRefresh: String?) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(params)

        let (data, response) = try await Net.session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 400 || http.statusCode == 401 {
            throw AuthError.rejected
        }
        try Net.check(response)
        let body = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = body.refresh_token ?? existingRefresh else { throw AuthError.invalidResponse }
        return Tokens(access: body.access_token, refresh: refresh, expiry: Date().addingTimeInterval(body.expires_in - 60))
    }

    private static func formBody(_ params: [String: String]) -> Data? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
    }

    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncoded
    }
}

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.session.role == .windowApplication }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}

enum AuthError: LocalizedError {
    case notConfigured, cancelled, invalidResponse, rejected, signedOut

    var errorDescription: String? {
        switch self {
        case .notConfigured: "No Google client ID is configured. See the README."
        case .cancelled: "Sign-in was cancelled."
        case .invalidResponse: "Google returned an unexpected response."
        case .rejected: "Google rejected the request."
        case .signedOut: "Your YouTube sign-in expired. Sign in again on your iPhone."
        }
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
