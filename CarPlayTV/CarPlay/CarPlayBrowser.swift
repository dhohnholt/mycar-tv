import CarPlay
import Combine
import CoreMedia
import UIKit

/// The CarPlay video-app UI: a tab bar with TV, Movies, YouTube and Recent, list and search templates
/// pushed on top, and the shared Now Playing template. Every playable row carries a video playback
/// configuration, so when it's selected iOS presents the video on the car display if the car allows it
/// (typically only while parked) and shows Now Playing otherwise.
@available(iOS 27.0, *)
@MainActor
final class CarPlayBrowser: NSObject {
    private let interfaceController: CPInterfaceController
    private let player = PlayerController.shared
    private let library = LibraryStore.shared
    private let history = HistoryStore.shared
    private var cancellables: Set<AnyCancellable> = []
    private var lastSearchText = ""

    private let tvTab = CPListTemplate(title: "TV", sections: [])
    private let moviesTab = CPListTemplate(title: "Movies", sections: [])
    private let youTubeTab = CPListTemplate(title: "YouTube", sections: [])
    private let recentTab = CPListTemplate(title: "Recent", sections: [])

    private var maxItems: Int { CPListTemplate.maximumItemCount }

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    func makeRootTemplate() -> CPTabBarTemplate {
        configureTab(tvTab, symbol: "tv")
        configureTab(moviesTab, symbol: "film")
        configureTab(youTubeTab, symbol: "play.rectangle")
        configureTab(recentTab, symbol: "clock.arrow.circlepath")

        // @Published sends the new value before the property changes, so use the value passed in.
        library.$liveGroups
            .sink { [weak self] groups in self?.reloadChannelTab(.live, groups: groups) }
            .store(in: &cancellables)
        library.$movieGroups
            .sink { [weak self] groups in self?.reloadChannelTab(.movie, groups: groups) }
            .store(in: &cancellables)
        library.$isLoading
            .sink { [weak self] loading in
                guard let self else { return }
                self.reloadChannelTab(.live, groups: self.library.liveGroups, loading: loading)
                self.reloadChannelTab(.movie, groups: self.library.movieGroups, loading: loading)
            }
            .store(in: &cancellables)
        history.$items
            .sink { [weak self] items in self?.reloadRecentTab(items) }
            .store(in: &cancellables)
        GoogleAuth.shared.$isSignedIn
            .sink { [weak self] signedIn in self?.reloadYouTubeTab(signedIn: signedIn) }
            .store(in: &cancellables)

        return CPTabBarTemplate(templates: [tvTab, moviesTab, youTubeTab, recentTab])
    }

    private func configureTab(_ tab: CPListTemplate, symbol: String) {
        tab.tabImage = UIImage(systemName: symbol)
        tab.trailingNavigationBarButtons = [searchButton()]
    }

    private func searchButton() -> CPBarButton {
        CPBarButton(image: UIImage(systemName: "magnifyingglass") ?? UIImage()) { [weak self] _ in
            self?.showSearch()
        }
    }

    // MARK: TV and Movies

    private func reloadChannelTab(_ kind: Channel.Kind, groups: [ChannelGroup], loading: Bool? = nil) {
        let tab = kind == .live ? tvTab : moviesTab
        let isLoading = loading ?? library.isLoading
        let items = groups.prefix(maxItems).map { group in
            let item = CPListItem(text: group.name, detailText: "\(group.channels.count)")
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.showChannels(group)
                completion()
            }
            return item
        }
        tab.emptyViewTitleVariants = [isLoading ? "Loading…" : (kind == .live ? "No channels" : "No movies")]
        tab.emptyViewSubtitleVariants = isLoading ? [] : ["No playlist has been added yet."]
        tab.updateSections(items.isEmpty ? [] : [CPListSection(items: items)])
    }

    private func showChannels(_ group: ChannelGroup) {
        var items = group.channels.prefix(maxItems).map { playableItem(.stream($0)) }
        if group.channels.count > items.count {
            items.removeLast()
            items.append(CPListItem(text: "\(group.channels.count - items.count) more — use Search", detailText: nil))
        }
        let template = CPListTemplate(title: group.name, sections: [CPListSection(items: items)])
        template.trailingNavigationBarButtons = [searchButton()]
        push(template)
    }

    // MARK: Recent

    private func reloadRecentTab(_ items: [MediaItem]) {
        recentTab.emptyViewTitleVariants = ["Nothing watched yet"]
        let rows = items.prefix(maxItems).map(playableItem)
        recentTab.updateSections(rows.isEmpty ? [] : [CPListSection(items: rows)])
    }

    // MARK: YouTube

    private func reloadYouTubeTab(signedIn: Bool) {
        guard signedIn else {
            youTubeTab.emptyViewTitleVariants = ["Not signed in to YouTube"]
            youTubeTab.emptyViewSubtitleVariants = ["YouTube isn't connected to Car TV."]
            youTubeTab.updateSections([])
            return
        }
        let items = [
            menuItem("Search", symbol: "magnifyingglass") { [weak self] in self?.showSearch() },
            menuItem("Liked videos", symbol: "hand.thumbsup") { [weak self] in
                self?.showVideos(title: "Liked videos") { try await YouTubeAPI.liked() }
            },
            menuItem("Subscriptions", symbol: "person.2") { [weak self] in
                self?.showPlaylists(title: "Subscriptions") { try await YouTubeAPI.subscriptions() }
            },
            menuItem("Playlists", symbol: "list.bullet") { [weak self] in
                self?.showPlaylists(title: "Playlists") { try await YouTubeAPI.playlists() }
            },
        ]
        youTubeTab.updateSections([CPListSection(items: items)])
    }

    private func showPlaylists(title: String, load: @escaping () async throws -> [YouTubePlaylist]) {
        showLoadingList(title: title) { [weak self] in
            guard let self else { return [] }
            return try await load().prefix(self.maxItems).map { playlist in
                let item = CPListItem(text: playlist.title, detailText: nil)
                item.accessoryType = .disclosureIndicator
                item.handler = { [weak self] _, completion in
                    self?.showVideos(title: playlist.title) { try await YouTubeAPI.playlistVideos(playlist.id) }
                    completion()
                }
                self.loadImage(playlist.thumbnailURL, into: item)
                return item
            }
        }
    }

    private func showVideos(title: String, load: @escaping () async throws -> [YouTubeVideo]) {
        showLoadingList(title: title) { [weak self] in
            guard let self else { return [] }
            return try await load().prefix(self.maxItems).map { self.playableItem(.youtube($0)) }
        }
    }

    /// Pushes an empty list immediately, then fills it once `load` finishes.
    private func showLoadingList(title: String, load: @escaping () async throws -> [CPListItem]) {
        let template = CPListTemplate(title: title, sections: [])
        template.emptyViewTitleVariants = ["Loading…"]
        push(template)
        Task {
            do {
                let items = try await load()
                template.emptyViewTitleVariants = ["Nothing here"]
                template.updateSections(items.isEmpty ? [] : [CPListSection(items: items)])
            } catch {
                template.emptyViewTitleVariants = ["Couldn't load"]
                template.emptyViewSubtitleVariants = [error.localizedDescription]
                template.updateSections([])
            }
        }
    }

    // MARK: Search

    private func showSearch() {
        let template = CPSearchTemplate()
        template.delegate = self
        push(template)
    }

    private func searchYouTube(_ query: String) {
        guard GoogleAuth.shared.isSignedIn else {
            return showAlert("YouTube isn't connected to Car TV.")
        }
        showVideos(title: query) { try await YouTubeAPI.search(query) }
    }

    // MARK: Helpers

    /// A row that plays `media` when selected. The playback configuration tells iOS to present the
    /// video on the car display when available.
    private func playableItem(_ media: MediaItem) -> CPListItem {
        let item = CPListItem(text: media.title, detailText: media.subtitle)
        item.playbackConfiguration = CPPlaybackConfiguration(
            preferredPresentation: .video,
            playbackAction: .play,
            elapsedTime: .zero,
            duration: .zero // unknown or live
        )
        item.handler = { [weak self] _, completion in
            self?.player.play(media)
            completion()
        }
        loadImage(media.artworkURL, into: item)
        return item
    }

    private func push(_ template: CPTemplate) {
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func showAlert(_ message: String) {
        let alert = CPAlertTemplate(titleVariants: [message], actions: [
            CPAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                self?.interfaceController.dismissTemplate(animated: true, completion: nil)
            },
        ])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }

    private func menuItem(_ title: String, symbol: String, action: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: title, detailText: nil, image: UIImage(systemName: symbol))
        item.accessoryType = .disclosureIndicator
        item.handler = { _, completion in
            action()
            completion()
        }
        return item
    }

    private func loadImage(_ url: URL?, into item: CPListItem) {
        guard let url else { return }
        Task {
            if let image = await ImageCache.shared.image(for: url, fitting: CPListItem.maximumImageSize) {
                item.setImage(image)
            }
        }
    }
}

@available(iOS 27.0, *)
extension CarPlayBrowser: CPSearchTemplateDelegate {
    func searchTemplate(_ searchTemplate: CPSearchTemplate, updatedSearchText searchText: String,
                        completionHandler: @escaping ([CPListItem]) -> Void) {
        let query = searchText.trimmed
        lastSearchText = query
        guard query.count >= 2 else { return completionHandler([]) }

        // Channel/movie matches are local and free; YouTube search costs API quota, so it's one tap away.
        let matches = (library.live + library.movies)
            .lazy
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .prefix(12)
        var items: [CPListItem] = matches.map { channel in
            let item = CPListItem(text: channel.name, detailText: channel.group)
            item.userInfo = MediaItem.stream(channel)
            return item
        }
        if GoogleAuth.shared.isSignedIn {
            let youtube = CPListItem(text: "Search YouTube for “\(query)”", detailText: nil,
                                     image: UIImage(systemName: "play.rectangle"))
            youtube.userInfo = query
            items.insert(youtube, at: 0)
        }
        completionHandler(items)
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate, selectedResult item: CPListItem,
                        completionHandler: @escaping () -> Void) {
        if let media = item.userInfo as? MediaItem {
            player.play(media)
        } else if let query = item.userInfo as? String {
            searchYouTube(query)
        }
        completionHandler()
    }

    func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {
        if lastSearchText.count >= 2 { searchYouTube(lastSearchText) }
    }
}
