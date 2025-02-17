import UIKit
import WebKit
import SoraFoundation
import SoraUI

final class DAppBrowserViewController: UIViewController, ViewHolder {
    typealias RootViewType = DAppBrowserViewLayout

    let presenter: DAppBrowserPresenterProtocol

    private var viewModel: DAppBrowserModel?

    private var urlObservation: NSKeyValueObservation?
    private var goBackObservation: NSKeyValueObservation?
    private var goForwardObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var isDesktop: Bool = false
    private var transports: [DAppTransportModel] = []
    private var scriptMessageHandlers: [String: DAppBrowserScriptHandler] = [:]

    private let localizationManager: LocalizationManagerProtocol
    private let localRouter: URLLocalRouting
    private let deviceOrientationManager: DeviceOrientationManaging

    private var scrollYOffset: CGFloat = 0
    private var barsHideOffset: CGFloat = 20
    private lazy var slidingAnimator = BlockViewAnimator(duration: 0.2, delay: 0, options: [.curveLinear])
    private var isBarHidden: Bool = false

    private var selectedLocale: Locale {
        localizationManager.selectedLocale
    }

    var isLandscape: Bool {
        view.frame.size.width > view.frame.size.height
    }

    init(
        presenter: DAppBrowserPresenterProtocol,
        localRouter: URLLocalRouting,
        deviceOrientationManager: DeviceOrientationManaging,
        localizationManager: LocalizationManagerProtocol
    ) {
        self.presenter = presenter
        self.localRouter = localRouter
        self.deviceOrientationManager = deviceOrientationManager
        self.localizationManager = localizationManager

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        urlObservation?.invalidate()
        goBackObservation?.invalidate()
        goForwardObservation?.invalidate()
        titleObservation?.invalidate()
    }

    override func loadView() {
        view = DAppBrowserViewLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if #available(iOS 16.0, *) {
            deviceOrientationManager.enableLandscape()
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let isOldLandscape = view.frame.size.width > view.frame.size.height

        super.viewWillTransition(to: size, with: coordinator)

        let isNewLandscape = size.width > size.height

        if !isOldLandscape, isNewLandscape {
            hideBars()
        } else if isOldLandscape, !isNewLandscape {
            showBars()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configure()

        presenter.setup()
    }

    private func configure() {
        navigationItem.titleView = rootView.urlBar

        navigationItem.leftItemsSupplementBackButton = false
        navigationItem.leftBarButtonItem = rootView.closeBarItem

        rootView.closeBarItem.target = self
        rootView.closeBarItem.action = #selector(actionClose)

        rootView.webView.uiDelegate = self
        rootView.webView.navigationDelegate = self
        rootView.webView.scrollView.delegate = self
        rootView.webView.allowsBackForwardNavigationGestures = true

        configureObservers()
        configureHandlers()
    }

    private func configureObservers() {
        urlObservation = rootView.webView.observe(\.url, options: [.initial, .new]) { [weak self] _, change in
            guard let newValue = change.newValue, let url = newValue else {
                return
            }

            self?.didChangeUrl(url)
        }

        goBackObservation = rootView.webView.observe(
            \.canGoBack,
            options: [.initial, .new]
        ) { [weak self] _, change in
            guard let newValue = change.newValue else {
                return
            }

            self?.didChangeGoBack(newValue)
        }

        goForwardObservation = rootView.webView.observe(
            \.canGoForward,
            options: [.initial, .new]
        ) { [weak self] _, change in
            guard let newValue = change.newValue else {
                return
            }

            self?.didChangeGoForward(newValue)
        }

        titleObservation = rootView.webView.observe(
            \.title,
            options: [.initial, .new]
        ) { [weak self] _, change in
            guard let newValue = change.newValue, let title = newValue else {
                return
            }

            self?.didChangeTitle(title)
        }
    }

    private func configureHandlers() {
        rootView.goBackBarItem.target = self
        rootView.goBackBarItem.action = #selector(actionGoBack)

        rootView.goForwardBarItem.target = self
        rootView.goForwardBarItem.action = #selector(actionGoForward)

        rootView.refreshBarItem.target = self
        rootView.refreshBarItem.action = #selector(actionRefresh)

        rootView.settingsBarButton.target = self
        rootView.settingsBarButton.action = #selector(actionSettings)

        rootView.urlBar.addTarget(self, action: #selector(actionSearch), for: .touchUpInside)
    }

    private func didChangeTitle(_ title: String) {
        guard let url = rootView.webView.url else {
            return
        }

        let page = DAppBrowserPage(url: url, title: title)
        presenter.process(page: page)
    }

    private func didChangeUrl(_ newUrl: URL) {
        rootView.urlLabel.text = newUrl.host

        if newUrl.isTLSScheme {
            rootView.securityImageView.image = R.image.iconBrowserSecurity()
        } else {
            rootView.securityImageView.image = nil
        }

        rootView.urlBar.setNeedsLayout()

        let title = rootView.webView.title ?? ""

        let page = DAppBrowserPage(url: newUrl, title: title)
        presenter.process(page: page)
    }

    private func setupUrl(_ url: URL) {
        rootView.urlLabel.text = url.host

        if url.isTLSScheme {
            rootView.securityImageView.image = R.image.iconBrowserSecurity()
        } else {
            rootView.securityImageView.image = nil
        }

        rootView.urlBar.setNeedsLayout()

        let request = URLRequest(url: url)
        rootView.webView.load(request)

        rootView.goBackBarItem.isEnabled = rootView.webView.canGoBack
        rootView.goForwardBarItem.isEnabled = rootView.webView.canGoForward
    }

    private func setupScripts() {
        let contentController = rootView.webView.configuration.userContentController
        contentController.removeAllUserScripts()

        setupTransports(transports, contentController: contentController)
        setupAdditionalUserScripts()
    }

    private func setupTransports(_ transports: [DAppTransportModel], contentController: WKUserContentController) {
        scriptMessageHandlers = transports.reduce(
            into: scriptMessageHandlers
        ) { handlers, transport in
            let handler = handlers[transport.name] ?? DAppBrowserScriptHandler(
                contentController: contentController,
                delegate: self
            )

            handler.bind(viewModel: transport)

            handlers[transport.name] = handler
        }
    }

    private func setupAdditionalUserScripts() {
        if isDesktop {
            let script = WKUserScript(
                source: rootView.webView.viewportScript(targetWidthInPixels: WKWebView.desktopWidth),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )

            rootView.webView.configuration.userContentController.addUserScript(script)
        }
    }

    private func setupWebPreferences() {
        let preferences = WKWebpagePreferences()
        preferences.preferredContentMode = isDesktop ? .desktop : .mobile
        rootView.webView.configuration.defaultWebpagePreferences = preferences

        if isDesktop {
            rootView.webView.customUserAgent = WKWebView.deskstopUserAgent
        } else {
            rootView.webView.customUserAgent = nil
        }
    }

    private func showBars() {
        guard isBarHidden else {
            return
        }

        isBarHidden = false

        navigationController?.setNavigationBarHidden(false, animated: true)

        slidingAnimator.animate(block: {
            self.rootView.setIsToolbarHidden(false)
        }, completionBlock: nil)
    }

    private func hideBars() {
        guard !isBarHidden else {
            return
        }

        isBarHidden = true

        navigationController?.setNavigationBarHidden(true, animated: true)

        slidingAnimator.animate(block: {
            self.rootView.setIsToolbarHidden(true)
        }, completionBlock: nil)
    }

    private func didChangeGoBack(_ newValue: Bool) {
        rootView.goBackBarItem.isEnabled = newValue
    }

    private func didChangeGoForward(_: Bool) {
        rootView.goForwardBarItem.isEnabled = rootView.webView.canGoForward
    }

    @objc private func actionGoBack() {
        rootView.webView.goBack()
    }

    @objc private func actionGoForward() {
        rootView.webView.goForward()
    }

    @objc private func actionRefresh() {
        rootView.webView.reload()
    }

    @objc private func actionSettings() {
        presenter.showSettings(using: isDesktop)
    }

    @objc private func actionSearch() {
        presenter.activateSearch(with: rootView.webView.url?.absoluteString)
    }

    @objc private func actionClose() {
        presenter.close()
    }
}

extension DAppBrowserViewController: DAppBrowserScriptHandlerDelegate {
    func browserScriptHandler(_: DAppBrowserScriptHandler, didReceive message: WKScriptMessage) {
        let host = rootView.webView.url?.host ?? ""

        presenter.process(message: message.body, host: host, transport: message.name)
    }
}

extension DAppBrowserViewController: DAppBrowserViewProtocol {
    func didReceive(viewModel: DAppBrowserModel) {
        isDesktop = viewModel.isDesktop
        transports = viewModel.transports

        setupScripts()
        setupWebPreferences()
        setupUrl(viewModel.url)
    }

    func didReceive(response: DAppScriptResponse, forTransport _: String) {
        rootView.webView.evaluateJavaScript(response.content)
    }

    func didReceiveReplacement(
        transports: [DAppTransportModel],
        postExecution script: DAppScriptResponse
    ) {
        self.transports = transports
        setupScripts()

        rootView.webView.evaluateJavaScript(script.content)
    }

    func didSet(isDesktop: Bool) {
        guard self.isDesktop != isDesktop else {
            return
        }

        self.isDesktop = isDesktop

        setupScripts()
        setupWebPreferences()
        rootView.webView.reload()
    }

    func didSet(canShowSettings: Bool) {
        rootView.settingsBarButton.isEnabled = canShowSettings
    }

    func didDecideClose() {
        if #available(iOS 16.0, *) {
            deviceOrientationManager.disableLandscape()
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

extension DAppBrowserViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard isLandscape else {
            return
        }

        scrollYOffset = scrollView.contentOffset.y
    }

    func scrollViewDidScrollToTop(_: UIScrollView) {
        showBars()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging, isLandscape else {
            return
        }

        let scrollDiff = scrollView.contentOffset.y - scrollYOffset
        let isScrollingUp = scrollDiff > 0 && scrollView.contentOffset.y > 0 && abs(scrollDiff) >= barsHideOffset
        let isScrollingDown = scrollDiff < 0 && abs(scrollDiff) >= barsHideOffset

        if isScrollingUp {
            hideBars()

            scrollYOffset = scrollView.contentOffset.y
        } else if isScrollingDown {
            showBars()

            scrollYOffset = scrollView.contentOffset.y
        }
    }
}

extension DAppBrowserViewController: WKUIDelegate, WKNavigationDelegate {
    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if
            let url = navigationAction.request.url,
            localRouter.canOpenLocalUrl(url) {
            localRouter.openLocalUrl(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }

        return nil
    }

    func webView(
        _: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)

        let languages = selectedLocale.rLanguages
        let confirmTitle = R.string.localizable.commonConfirmTitle(
            preferredLanguages: languages
        )

        alertController.addAction(UIAlertAction(title: confirmTitle, style: .default, handler: { _ in
            completionHandler()
        }))

        let cancelTitle = R.string.localizable.commonCancel(
            preferredLanguages: languages
        )

        alertController.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

        present(alertController, animated: true, completion: nil)
    }
}
