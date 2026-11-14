import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    /// One state per process, reused by every controller iOS creates on
    /// each opening, so nothing per-opening can pile up (see installHost).
    private let state = KeyboardState.shared
    private var heightConstraint: NSLayoutConstraint?
    private var host: UIHostingController<AnyView>?
    override func viewDidLoad() {
        super.viewDidLoad()
        startWatchingSettings()
        state.controller = self

        installHost()
        // 999, not required: iOS adds its own height constraint while the
        // keyboard animates in, and a required one would conflict with it.
        let height = view.heightAnchor.constraint(
            equalToConstant: Metrics.totalHeight(state.settings))
        height.priority = UILayoutPriority(999)
        heightConstraint = height
        height.isActive = true
        // Views default to single-touch, and iOS silently drops a second
        // finger unless every view on the way allows multi-touch. Fast
        // two-thumb typing overlaps constantly, so this lost real taps.
        view.isMultipleTouchEnabled = true
    }

    /// The SwiftUI keyboard. Built on open and torn down on close: iOS keeps
    /// a closed keyboard's view tree alive after its controller is gone,
    /// which added ~1-3 MB per opening until the extension was killed.
    private func installHost() {
        let host = UIHostingController(rootView: AnyView(KeyboardView(state: state)))
        self.host = host
        // Not .clear: iOS never delivers a keyboard extension touches that
        // land on fully transparent pixels, so taps in the gaps between key
        // rows were silently lost. 1% opacity is invisible but counts.
        host.view.backgroundColor = UIColor(white: 0.5, alpha: 0.01)
        // Keyboards sit above the home indicator already; extra safe-area
        // padding from SwiftUI would just shrink the keys.
        host.safeAreaRegions = []
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        host.view.isMultipleTouchEnabled = true
    }

    private func removeHost() {
        guard let host else { return }
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        host.rootView = AnyView(EmptyView())
        self.host = nil
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Phones with a home indicator show the globe below the keyboard
        // themselves, so we only draw one when iOS says it's needed.
        if state.showGlobe != needsInputModeSwitchKey {
            state.showGlobe = needsInputModeSwitchKey
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if host == nil {
            installHost()
            Domains.loadStorefront()
        }
        state.emojiSearch = nil
        state.tonePicker = nil
        // Pick up any changes made in the app since the keyboard last opened.
        applySettings()
        state.inAppField = SharedSettings.defaults.bool(forKey: SharedSettings.inAppFieldKey)
        state.setupNote = hasFullAccess ? nil : "Turn on Full Access in Settings to use your TsumuKey settings"
        KeyboardReport(build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
                       openedAt: Date(), fullAccess: hasFullAccess,
                       settingsFound: SharedSettings.defaults.data(forKey: "keyboardSettings") != nil,
                       layout: state.settings.layout.rawValue).save()
        state.mode = state.textMode
        state.textChanged()
    }

    /// Rereads the shared settings: on appear, and while open whenever the app
    /// changes them (Darwin notification, see startWatchingSettings).
    private func applySettings() {
        let settings = KeyboardSettings.load()
        CurrencyResult.rates = settings.currencyConversion ? CurrencyRates.load() : nil
        if settings != state.settings { state.settings = settings }
        heightConstraint?.constant = Metrics.totalHeight(settings)
        // Day/night: the key colours are dynamic, so overriding the style
        // repaints the whole keyboard, background included.
        view.overrideUserInterfaceStyle = settings.theme.style
        state.backspace.timing = DeleteTiming.load()
        state.loadEngines()
    }

    /// Darwin callbacks get this box, not the controller: it only points to the
    /// controller weakly, so a notification that lands while iOS tears the
    /// keyboard down finds nil instead of freed memory.
    private final class Observer {
        weak var controller: KeyboardViewController?
        init(_ controller: KeyboardViewController) { self.controller = controller }
    }
    private lazy var observer = Observer(self)

    private func startWatchingSettings() {
        let box = Unmanaged.passUnretained(observer).toOpaque()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), box, { _, box, _, _, _ in
            guard let box else { return }
            let observer = Unmanaged<Observer>.fromOpaque(box).takeUnretainedValue()
            DispatchQueue.main.async { [weak observer] in
                guard let vc = observer?.controller,
                      vc.viewIfLoaded?.window != nil else { return }  // reread on next appear instead
                vc.applySettings()
                vc.state.textChanged()
            }
        }, SharedSettings.changed, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), box, { _, box, _, _, _ in
            guard let box else { return }
            let observer = Unmanaged<Observer>.fromOpaque(box).takeUnretainedValue()
            DispatchQueue.main.async { [weak observer] in
                observer?.controller?.state.inAppField = SharedSettings.defaults.bool(forKey: SharedSettings.inAppFieldKey)
            }
        }, SharedSettings.inAppField, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                                Unmanaged.passUnretained(observer).toOpaque())
    }

    /// Opens the TsumuKey app. Extensions aren't given `UIApplication.open`,
    /// so this finds the app object on the responder chain and calls it
    /// through the Objective-C runtime, the same workaround other keyboards use.
    func openContainingApp() {
        guard let url = URL(string: "tsumukey://settings") else { return }
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            // UIScene has a method with the same name but different argument
            // types, so only call it on the application itself.
            if current is UIApplication, let method = current.method(for: selector) {
                typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                unsafeBitCast(method, to: OpenURL.self)(current, selector, url as NSURL, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // iOS watches the screen edges for system swipes and holds back any
        // touch there until it rules a swipe out (~60 ms). On a keyboard that
        // makes the outer keys (q, a, p, o…) lag, and a quick next tap can
        // get lost. Keyboards don't need those swipes, so stop the delay.
        var v: UIView? = view
        while let current = v {
            for recognizer in current.gestureRecognizers ?? [] {
                if recognizer.delaysTouchesBegan {
                    recognizer.delaysTouchesBegan = false
                }
            }
            v = current.superview
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        state.commitComposition()
        KanaConverter.shared.save()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeHost()
    }

    private var lastReset = Date.distantPast

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // iOS sends these often, even with plenty left, and kills the keyboard
        // near 76 MB (iPhone 15), falling back to the previous keyboard. Below
        // 25 MB left, the model and the kana dictionary are dropped and loaded
        // fresh, which also clears whatever they had built up. At most once a
        // minute: warnings come in bursts.
        guard Memory.availableMB() < 25, Date().timeIntervalSince(lastReset) > 60 else { return }
        lastReset = Date()
        state.predictor.unload()
        KanaConverter.shared.unload()
        state.loadEngines()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        state.textChanged()
    }
}

