import Cocoa
import Ikemen
import NorthLayout
import WebKit
import BrightFutures

class ViewController: NSViewController, NSOutlineViewDelegate, NSOutlineViewDataSource, WKNavigationDelegate {
    private let prismdb = PrismDB()
    private var episodesAndLives: ([PrismDB.Episode], [PrismDB.Live]) = ([], []) {
        didSet {
            outlineView.reloadData()
            outlineView.expandItem(nil, expandChildren: true)
        }
    }
    private var episodes: [PrismDB.Episode] {
        episodesAndLives.0
    }
    private var lives: [PrismDB.Live] {
        let episodeIRIs = self.episodes.map {$0.iri}
        return episodesAndLives.1.filter {episodeIRIs.contains($0.episodeIRI)}
    }
    private var currentEpisode: PrismDB.Episode? {
        didSet {
            guard let url = currentEpisode?.anitvURL else { return }
            webView.load(URLRequest(url: url))
        }
    }
    private var currentLive: PrismDB.Live? {
        didSet {
            let row = outlineView.row(forItem: currentLive)
            if row >= 0 {
                if row != outlineView.selectedRow {
                    outlineView.selectRowIndexes([row], byExtendingSelection: false)
                    outlineView.scrollRowToVisible(row)
                }
            } else {
                outlineView.deselectAll(nil)
            }

            guard let currentLive = currentLive else { return }
            if currentLive.episodeIRI != currentEpisode?.iri {
                currentEpisode = episodes.first {$0.iri == currentLive.episodeIRI}
            } else {
                waitLoadAndPlay(seeking: currentLive.start, waiting: currentLive.end)
            }
        }
    }

    private lazy var outlineView: NSOutlineView = .init() ※ { ov in
        ov.addTableColumn(liveColumn)
        ov.outlineTableColumn = liveColumn
        ov.dataSource = self
        ov.delegate = self
        ov.target = self
        ov.doubleAction = #selector(openInAniTV(_:))
        ov.autosaveName = "Lives"
        ov.autosaveTableColumns = true
        ov.usesAutomaticRowHeights = true
    }

    private let episodeColumn: NSTableColumn = .init(identifier: .init(rawValue: "episode")) ※ { c in
        c.title = "#"
    }
    private let liveColumn: NSTableColumn = .init(identifier: .init("live")) ※ { c in
        c.title = "Live"
    }

    private lazy var webView: WKWebView = .init(frame: .zero, configuration: .init()) ※ { w in
        w.navigationDelegate = self
        w.configuration.preferences.plugInsEnabled = false
        w.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1 Safari/605.1.15" // imitate Safari
        w.allowsMagnification = true
        w.allowsBackForwardNavigationGestures = false
    }

    private lazy var nextButton: NSButton = .init() ※ { b in
        b.title = "Next"
        b.bezelStyle = .rounded
        b.target = self
        b.action = #selector(playNext)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let autolayout = view.northLayoutFormat([:], [
            "next": nextButton,
            "table": NSScrollView() ※ {
                $0.documentView = outlineView
                $0.hasVerticalScroller = true
            },
            "web": webView])
        autolayout("H:|[table(==256)]-[web(>=769)]|") // anitv webview must be >= 768 for playback
        autolayout("H:[next]-40-[web]")
        autolayout("V:|-[next]-[table(>=256)]|")
        autolayout("V:|[web]|")
        outlineView.setContentHuggingPriority(.fittingSizeCompression, for: .vertical)
        webView.setContentHuggingPriority(.fittingSizeCompression, for: .vertical)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updatePrismDB()
    }

    private func updatePrismDB() {
        prismdb.episodes().zip(prismdb.lives())
            .onSuccess { (episodes, lives) in
                let episodeIRIs = episodes.map {$0.iri}
                self.episodesAndLives = (episodes, lives.filter {episodeIRIs.contains($0.episodeIRI)})
        }
            .onFailure {NSLog("%@", "\(String(describing: $0))")}
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        switch item {
        case nil: return episodes.count
        case let episode as PrismDB.Episode: return lives.filter {
            $0.episodeIRI == episode.iri}.count
        default: return 0
        }
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        switch item {
        case nil: return episodes[index]
        case let episode as PrismDB.Episode: return lives.filter {
            $0.episodeIRI == episode.iri}[index]
        default: fatalError()
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        switch item {
        case is PrismDB.Episode: return true
        case is PrismDB.Live: return false
        default: fatalError()
        }
    }

    func outlineView(_ outlineView: NSOutlineView, shouldEdit tableColumn: NSTableColumn?, item: Any) -> Bool {
        false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        switch item {
        case let episode as PrismDB.Episode:
            return NSView() ※ {
                let autolayout = $0.northLayoutFormat([:], [
                    "title": AutolayoutLabel() ※ {
                        $0.stringValue = episode.label + "\n「" + episode.subtitle + "」"
                        $0.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
                    }])
                autolayout("H:|-[title]-|")
                autolayout("V:|-[title]-|")
            }
        case let live as PrismDB.Live:
            return NSView() ※ {
                let df = DateFormatter()
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = "mm:ss"
                let start = live.start.flatMap {df.string(from: Date(timeIntervalSince1970: $0))}
                let autolayout = $0.northLayoutFormat([:], ["title": AutolayoutLabel() ※ {
                    $0.stringValue = (start.map {"[\($0)]: "} ?? "") + "\(live.song) (\(live.performer))"}])
                autolayout("H:|[title]-|")
                autolayout("V:|-[title]-|")
            }
        default: fatalError()
        }
    }

    @objc func openInAniTV(_ sender: AnyObject?) {
        switch outlineView.item(atRow: outlineView.clickedRow) {
        case let episode as PrismDB.Episode:
            currentEpisode = episode
        case let live as PrismDB.Live:
            currentLive = live
        default: return
        }
    }

    @objc func playNext() {
        let index = currentLive.flatMap {lives.firstIndex(of: $0)} ?? 0
        let nextIndex = (index + 1) % lives.count
        guard nextIndex < lives.count else { return }
        currentLive = lives[nextIndex]
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.waitLoadAndPlay(seeking: self.currentLive?.start, waiting: self.currentLive?.end)
            self.hideSideMenu()
        }
    }

    private let playerJS = "$(\"#player-embed-videoid_html5_api\")[0]"
    private let playButtonJS = "$(\"#player-ctrl-play\")"

    func hideSideMenu() {
        webView.evaluateJavaScript("$(\"nav\").remove()")
        webView.evaluateJavaScript("$(\"#contents\").css({\"cssText\": \"margin-left: 0 !important\"})")
        webView.evaluateJavaScript("$(\".movie-content-movie .video-js\").css({\"cssText\": \"margin: 0 !important\"})")
        webView.evaluateJavaScript("$(\"#player-ctrl-block\").css({\"cssText\": \"margin: 0 !important\"})")
    }

    func waitLoadAndPlay(seeking start: TimeInterval?, waiting end: TimeInterval?) {
        webView.evaluateJavaScript(playerJS + ".readyState") { [weak self] r, e in
            guard let `self` = self else { return }

            guard let v = r as? Int else { return }
            switch v {
            case 0: self.clickPlay(seeking: start, waiting: end, completion: {
                self.playNext()
            })
            case 1,2,3,4: self.play(seeking: start, waiting: end, completion: {
                self.playNext()
            })
            default:
                NSLog("%@", "unknown readyState = \(v)")
                self.clickPlay(seeking: start, waiting: end, completion: {
                    self.playNext()
                })
            }
        }
    }

    func waitReadyStateAndDo(_ block: @escaping () -> Void) {
        let currentLive = self.currentLive
        webView.evaluateJavaScript(playerJS + ".readyState") { [weak self] r, e in
            NSLog("%@", "readyState = \(String(describing: r)), error = \(String(describing: e))")
            guard let `self` = self,
                let v = r as? Int else { return }
            if v == 4 {
                block()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard currentLive == self?.currentLive else { return }
                    self?.waitReadyStateAndDo(block)
                }
            }
        }
    }

    func waitCurrentTimeBecome(greaterThan time: TimeInterval, _ block: @escaping () -> Void) {
        let currentLive = self.currentLive
        webView.evaluateJavaScript(playerJS + ".currentTime") { [weak self] r, e in
            NSLog("%@", "currentTime = \(String(describing: r)), error = \(String(describing: e))")
            guard let `self` = self,
                let v = r as? Double else { return }
            if v > time {
                block()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard currentLive == self?.currentLive else { return }
                    self?.waitCurrentTimeBecome(greaterThan: time, block)
                }
            }
        }
    }

    func clickPlay(seeking start: TimeInterval?, waiting end: TimeInterval?, completion: (() -> Void)?) {
        webView.evaluateJavaScript(playButtonJS + ".click()") { [weak self] _, _ in
            guard let start = start else { return }
            self?.waitReadyStateAndDo {
                self?.seek(to: start)
                if let end = end {
                    self?.waitCurrentTimeBecome(greaterThan: end, completion ?? {})
                }
            }
        }
    }

    func play(seeking start: TimeInterval?, waiting end: TimeInterval?, completion: (() -> Void)?) {
        webView.evaluateJavaScript(playerJS + ".play()") { [weak self] _, _ in
            guard let start = start else { return }
            self?.waitReadyStateAndDo {
                self?.seek(to: start)
                if let end = end {
                    self?.waitCurrentTimeBecome(greaterThan: end, completion ?? {})
                }
            }
        }
    }

    func seek(to time: TimeInterval) {
        webView.evaluateJavaScript(playerJS + ".currentTime = \(time)", completionHandler: nil)
    }
}
