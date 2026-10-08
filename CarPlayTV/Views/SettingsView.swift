import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var auth: GoogleAuth
    @ObservedObject private var history = HistoryStore.shared

    @State private var newPlaylist = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var authError: String?

    var body: some View {
        NavigationStack {
            Form {
                playlistsSection
                xtreamSection
                librarySection
                youTubeSection
                MirroringSection()
                Section("Privacy") {
                    Text("Playlists, logins, YouTube tokens and watch history are stored only in this iPhone's Keychain and never sync or back up. The app has no analytics or third-party SDKs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Clear watch history", role: .destructive) { history.clear() }
                        .disabled(history.items.isEmpty)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Settings")
            .onAppear(perform: loadXtreamFields)
        }
    }

    private var playlistsSection: some View {
        Section("M3U playlists") {
            ForEach(library.sources.playlistURLs, id: \.self) { url in
                Text(Self.redacted(url)).lineLimit(1)
            }
            .onDelete { offsets in
                library.sources.playlistURLs.remove(atOffsets: offsets)
                Task { await library.reload() }
            }
            HStack {
                TextField("https://…/playlist.m3u", text: $newPlaylist)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addPlaylist)
                Button("Add", action: addPlaylist)
                .buttonStyle(.borderless)
                .disabled(newPlaylist.trimmed.isEmpty)
            }
        }
    }

    private var xtreamSection: some View {
        Section {
            TextField("Server (http://host:port)", text: $server)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
            Button("Save") {
                var address = server.trimmed
                if !address.contains("://") { address = "http://" + address }
                guard let url = URL(string: address), !username.trimmed.isEmpty else { return }
                library.sources.xtream = XtreamAccount(server: url, username: username.trimmed, password: password)
                Task { await library.reload() }
            }
            if library.sources.xtream != nil {
                Button("Remove Xtream login", role: .destructive) {
                    library.sources.xtream = nil
                    server = ""; username = ""; password = ""
                    Task { await library.reload() }
                }
            }
        } header: {
            Text("Xtream Codes")
        }
    }

    private var librarySection: some View {
        Section {
            Button("Reload library") { Task { await library.reload() } }
                .disabled(library.isLoading)
            if library.isLoading {
                ProgressView()
            } else {
                LabeledContent("Loaded", value: "\(library.live.count) channels · \(library.movies.count) movies")
            }
            if let error = library.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var youTubeSection: some View {
        Section("YouTube") {
            if !auth.isConfigured {
                Text("Add your Google OAuth client ID (GOOGLE_CLIENT_ID in project.yml) to enable YouTube.")
                    .font(.footnote)
            } else if auth.isSignedIn {
                LabeledContent("Status", value: "Signed in")
                Button("Sign out", role: .destructive) { auth.signOut() }
            } else {
                Button("Sign in with Google") {
                    Task {
                        do { try await auth.signIn() } catch { authError = error.localizedDescription }
                    }
                }
            }
            if let authError {
                Text(authError).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func addPlaylist() {
        guard let url = URL(string: newPlaylist.trimmed), url.scheme?.hasPrefix("http") == true else { return }
        library.sources.playlistURLs.append(url)
        newPlaylist = ""
        Task { await library.reload() }
    }

    private func loadXtreamFields() {
        guard let account = library.sources.xtream, server.isEmpty else { return }
        server = account.server.absoluteString
        username = account.username
        password = account.password
    }

    /// Hides credentials that are often embedded in playlist URLs.
    private static func redacted(_ url: URL) -> String {
        "\(url.scheme ?? "http")://\(url.host() ?? "")/…"
    }
}
