import Cocoa
import Ikemen
import NorthLayout
import WebKit

struct Live: Equatable {
    var episode: Int
    var song: String
    var start: Double?
    var end: Double?
    var anitv: String?
}
extension Live {
    var anitvURL: URL? {return anitv.flatMap {URL(string: $0)}}
}

class ViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, WKNavigationDelegate {
    // TODO: fetch lives from pripara DB
    private var lives: [Live] = [
        Live(episode: 1, song: "レディー・アクション！", start: 1009, end: 1136, anitv: "https://ch.ani.tv/episodes/13143"),
        Live(episode: 5, song: "ワン・ツー・スウィーツ", start: 1142.8, end: 1236.2, anitv: "https://ch.ani.tv/episodes/13710"),
        Live(episode: 6, song: "スキスキセンサー", start: 1073.8, end: 1174.7, anitv: "https://ch.ani.tv/episodes/14089"),
        Live(episode: 52, song: "TOKIMEKIハート・ジュエル♪", start: 1130, end: 1252, anitv: "https://ch.ani.tv/episodes/18716"),
        Live(episode: 2, song: "song 2", start: 1000, end: 1060, anitv: nil),
        Live(episode: 2, song: "song 3", start: 1000, end: 1060, anitv: nil),
        Live(episode: 3, song: "song 4", start: 1000, end: 1060, anitv: nil),
        Live(episode: 4, song: "song 5", start: 1000, end: 1060, anitv: nil),
        Live(episode: 4, song: "song 6", start: 1000, end: 1060, anitv: nil),
    ]
    private var currentLive: Live? {
        didSet {
            guard let url = currentLive?.anitvURL else { return }
            if let index = (currentLive.flatMap {lives.firstIndex(of: $0)}),
                index != tableView.selectedRow {
                tableView.selectRowIndexes([index], byExtendingSelection: false)
            }
            webView.load(URLRequest(url: url))
        }
    }

    private lazy var tableView: NSTableView = .init() ※ { tv in
        tv.addTableColumn(episodeColumn)
        tv.addTableColumn(liveColumn)
        tv.dataSource = self
        tv.delegate = self
        tv.target = self
        tv.doubleAction = #selector(openInAniTV(_:))
        tv.autosaveName = "Lives"
        tv.autosaveTableColumns = true
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
                $0.documentView = tableView
            },
            "web": webView])
        autolayout("H:|[table(==256)]-[web(>=769)]|") // anitv webview must be >= 768 for playback
        autolayout("H:[next]-40-[web]")
        autolayout("V:|-[next]-[table(>=256)]|")
        autolayout("V:|[web]|")
        tableView.setContentHuggingPriority(.fittingSizeCompression, for: .vertical)
        webView.setContentHuggingPriority(.fittingSizeCompression, for: .vertical)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return lives.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let live = lives[row]
        switch tableColumn {
        case episodeColumn: return live.episode
        case liveColumn: return live.song
        default: fatalError()
        }
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return false
    }

    @objc func openInAniTV(_ sender: AnyObject?) {
        let row = tableView.clickedRow
        guard 0 <= row,
            row < lives.count else { return }
        currentLive = lives[row]
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
