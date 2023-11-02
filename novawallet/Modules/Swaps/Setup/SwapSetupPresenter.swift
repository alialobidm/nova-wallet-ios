import Foundation
import SoraFoundation
import BigInt

final class SwapSetupPresenter: PurchaseFlowManaging {
    weak var view: SwapSetupViewProtocol?
    let wireframe: SwapSetupWireframeProtocol
    let interactor: SwapSetupInteractorInputProtocol
    let dataValidatingFactory: SwapDataValidatorFactoryProtocol
    let logger: LoggerProtocol
    let selectedAccount: MetaAccountModel
    let purchaseProvider: PurchaseProviderProtocol

    private(set) var viewModelFactory: SwapsSetupViewModelFactoryProtocol

    private(set) var balances: [ChainAssetId: AssetBalance] = [:]

    var payAssetBalance: AssetBalance? {
        payChainAsset.flatMap { balances[$0.chainAssetId] }
    }

    var feeAssetBalance: AssetBalance? {
        feeChainAsset.flatMap { balances[$0.chainAssetId] }
    }

    var receiveAssetBalance: AssetBalance? {
        receiveChainAsset.flatMap { balances[$0.chainAssetId] }
    }

    private(set) var prices: [ChainAssetId: PriceData] = [:]

    var payAssetPriceData: PriceData? {
        payChainAsset.flatMap { prices[$0.chainAssetId] }
    }

    var receiveAssetPriceData: PriceData? {
        receiveChainAsset.flatMap { prices[$0.chainAssetId] }
    }

    var feeAssetPriceData: PriceData? {
        feeChainAsset.flatMap { prices[$0.chainAssetId] }
    }

    private(set) var payChainAsset: ChainAsset?
    private(set) var canPayFeeInPayAsset: Bool = false
    private(set) var receiveChainAsset: ChainAsset?
    private(set) var feeChainAsset: ChainAsset?
    private(set) var payAmountInput: AmountInputResult?
    private(set) var receiveAmountInput: Decimal?
    private(set) var fee: AssetConversion.FeeModel?
    private(set) var quote: AssetConversion.Quote?
    private(set) var quoteArgs: AssetConversion.QuoteArgs? {
        didSet {
            provideDetailsViewModel(isAvailable: quoteArgs != nil)
        }
    }

    private var slippage: BigRational?
    private var feeIdentifier: SwapSetupFeeIdentifier?
    private var accountId: AccountId?
    private var depositOperations: [DepositOperationModel] = []
    private var purchaseActions: [PurchaseAction] = []
    private var depositCrossChainAssets: [ChainAsset] = []
    private var xcmTransfers: XcmTransfers?

    init(
        payChainAsset: ChainAsset?,
        interactor: SwapSetupInteractorInputProtocol,
        wireframe: SwapSetupWireframeProtocol,
        viewModelFactory: SwapsSetupViewModelFactoryProtocol,
        dataValidatingFactory: SwapDataValidatorFactoryProtocol,
        localizationManager: LocalizationManagerProtocol,
        selectedAccount: MetaAccountModel,
        purchaseProvider: PurchaseProviderProtocol,
        logger: LoggerProtocol
    ) {
        self.payChainAsset = payChainAsset
        feeChainAsset = payChainAsset?.chain.utilityChainAsset()
        self.interactor = interactor
        self.wireframe = wireframe
        self.viewModelFactory = viewModelFactory
        self.dataValidatingFactory = dataValidatingFactory
        self.logger = logger
        self.selectedAccount = selectedAccount
        self.purchaseProvider = purchaseProvider
        self.localizationManager = localizationManager
    }

    private func provideButtonState() {
        let buttonState = viewModelFactory.buttonState(
            assetIn: payChainAsset?.chainAssetId,
            assetOut: receiveChainAsset?.chainAssetId,
            amountIn: getPayAmount(for: payAmountInput),
            amountOut: receiveAmountInput
        )
        view?.didReceiveButtonState(
            title: buttonState.title.value(for: selectedLocale),
            enabled: buttonState.enabled
        )
    }

    private func providePayTitle() {
        let payTitleViewModel = viewModelFactory.payTitleViewModel(
            assetDisplayInfo: payChainAsset?.assetDisplayInfo,
            maxValue: payAssetBalance?.transferable
        )
        view?.didReceiveTitle(payViewModel: payTitleViewModel)
    }

    private func providePayAssetViewModel() {
        let payAssetViewModel = viewModelFactory.payAssetViewModel(
            chainAsset: payChainAsset
        )
        view?.didReceiveInputChainAsset(payViewModel: payAssetViewModel)
    }

    private func providePayInputPriceViewModel() {
        guard let assetDisplayInfo = payChainAsset?.assetDisplayInfo else {
            view?.didReceiveAmountInputPrice(payViewModel: nil)
            return
        }
        let inputPriceViewModel = viewModelFactory.inputPriceViewModel(
            assetDisplayInfo: assetDisplayInfo,
            amount: getPayAmount(for: payAmountInput),
            priceData: payAssetPriceData
        )
        view?.didReceiveAmountInputPrice(payViewModel: inputPriceViewModel)
    }

    private func provideReceiveTitle() {
        let receiveTitleViewModel = viewModelFactory.receiveTitleViewModel()
        view?.didReceiveTitle(receiveViewModel: receiveTitleViewModel)
    }

    private func provideReceiveAssetViewModel() {
        let receiveAssetViewModel = viewModelFactory.receiveAssetViewModel(
            chainAsset: receiveChainAsset
        )
        view?.didReceiveInputChainAsset(receiveViewModel: receiveAssetViewModel)
    }

    private func provideReceiveInputPriceViewModel() {
        guard let assetDisplayInfo = receiveChainAsset?.assetDisplayInfo else {
            view?.didReceiveAmountInputPrice(receiveViewModel: nil)
            return
        }

        let inputPriceViewModel = viewModelFactory.inputPriceViewModel(
            assetDisplayInfo: assetDisplayInfo,
            amount: receiveAmountInput,
            priceData: receiveAssetPriceData
        )

        let differenceViewModel: DifferenceViewModel?
        if let quote = quote, let payAssetDisplayInfo = payChainAsset?.assetDisplayInfo {
            let params = RateParams(
                assetDisplayInfoIn: payAssetDisplayInfo,
                assetDisplayInfoOut: assetDisplayInfo,
                amountIn: quote.amountIn,
                amountOut: quote.amountOut
            )

            differenceViewModel = viewModelFactory.priceDifferenceViewModel(
                rateParams: params,
                priceIn: payAssetPriceData,
                priceOut: receiveAssetPriceData
            )
        } else {
            differenceViewModel = nil
        }

        view?.didReceiveAmountInputPrice(receiveViewModel: .init(
            price: inputPriceViewModel,
            difference: differenceViewModel
        ))
    }

    private func providePayAmountInputViewModel() {
        guard let payChainAsset = payChainAsset else {
            return
        }
        let amountInputViewModel = viewModelFactory.amountInputViewModel(
            chainAsset: payChainAsset,
            amount: getPayAmount(for: payAmountInput)
        )
        view?.didReceiveAmount(payInputViewModel: amountInputViewModel)
    }

    private func provideReceiveAmountInputViewModel() {
        guard let receiveChainAsset = receiveChainAsset else {
            return
        }
        let amountInputViewModel = viewModelFactory.amountInputViewModel(
            chainAsset: receiveChainAsset,
            amount: receiveAmountInput
        )
        view?.didReceiveAmount(receiveInputViewModel: amountInputViewModel)
    }

    private func provideSettingsState() {
        view?.didReceiveSettingsState(isAvailable: payChainAsset != nil)
    }

    private func getPayAmount(for input: AmountInputResult?) -> Decimal? {
        guard let input = input, let balanceMinusFee = balanceMinusFee() else {
            return nil
        }
        return input.absoluteValue(from: balanceMinusFee)
    }

    private func providePayAssetViews() {
        providePayTitle()
        providePayAssetViewModel()
        providePayInputPriceViewModel()
        providePayAmountInputViewModel()
    }

    private func provideReceiveAssetViews() {
        provideReceiveTitle()
        provideReceiveAssetViewModel()
        provideReceiveInputPriceViewModel()
        provideReceiveAmountInputViewModel()
    }

    private func provideDetailsViewModel(isAvailable: Bool) {
        view?.didReceiveDetailsState(isAvailable: isAvailable)
    }

    private func provideRateViewModel() {
        guard
            let assetDisplayInfoIn = payChainAsset?.assetDisplayInfo,
            let assetDisplayInfoOut = receiveChainAsset?.assetDisplayInfo,
            let quote = quote else {
            view?.didReceiveRate(viewModel: .loading)
            return
        }
        let rateViewModel = viewModelFactory.rateViewModel(from: .init(
            assetDisplayInfoIn: assetDisplayInfoIn,
            assetDisplayInfoOut: assetDisplayInfoOut,
            amountIn: quote.amountIn,
            amountOut: quote.amountOut
        ))

        view?.didReceiveRate(viewModel: .loaded(value: rateViewModel))
    }

    private func provideFeeViewModel() {
        guard quoteArgs != nil, let feeChainAsset = feeChainAsset else {
            return
        }
        guard let fee = fee?.networkFee.targetAmount else {
            view?.didReceiveNetworkFee(viewModel: .loading)
            return
        }
        let isEditable = (payChainAsset?.isUtilityAsset == false) && canPayFeeInPayAsset
        let viewModel = viewModelFactory.feeViewModel(
            amount: fee,
            assetDisplayInfo: feeChainAsset.assetDisplayInfo,
            isEditable: isEditable,
            priceData: feeAssetPriceData
        )

        view?.didReceiveNetworkFee(viewModel: .loaded(value: viewModel))
    }

    private func provideErrors() {
        guard let payAmount = getPayAmount(for: payAmountInput) else {
            view?.didReceive(errors: [])
            return
        }
        var errors: [SwapSetupViewError] = []
        let balanceMinusFee = balanceMinusFee() ?? 0

        if payAmount > balanceMinusFee {
            errors.append(.insufficientToken)
        }

        view?.didReceive(errors: errors)
    }

    func estimateFee() {
        guard let quote = quote,
              let accountId = accountId,
              let quoteArgs = quoteArgs,
              let slippage = slippage else {
            return
        }

        let args = AssetConversion.CallArgs(
            assetIn: quote.assetIn,
            amountIn: quote.amountIn,
            assetOut: quote.assetOut,
            amountOut: quote.amountOut,
            receiver: accountId,
            direction: quoteArgs.direction,
            slippage: slippage
        )

        let newIdentifier = SwapSetupFeeIdentifier(
            transactionId: args.identifier,
            feeChainAssetId: feeChainAsset?.chainAssetId
        )

        guard newIdentifier != feeIdentifier else {
            return
        }

        feeIdentifier = newIdentifier
        interactor.calculateFee(args: args)
    }

    func refreshQuote(direction: AssetConversion.Direction, forceUpdate: Bool = true) {
        guard
            let payChainAsset = payChainAsset,
            let receiveChainAsset = receiveChainAsset else {
            return
        }

        quote = nil

        switch direction {
        case .buy:
            refreshQuoteForBuy(
                payChainAsset: payChainAsset,
                receiveChainAsset: receiveChainAsset,
                forceUpdate: forceUpdate
            )
        case .sell:
            refreshQuoteForSell(
                payChainAsset: payChainAsset,
                receiveChainAsset: receiveChainAsset,
                forceUpdate: forceUpdate
            )
        }

        provideRateViewModel()
        provideFeeViewModel()
    }

    private func refreshQuoteForBuy(payChainAsset: ChainAsset, receiveChainAsset: ChainAsset, forceUpdate: Bool) {
        if
            let receiveInPlank = receiveAmountInput?.toSubstrateAmount(
                precision: receiveChainAsset.assetDisplayInfo.assetPrecision
            ),
            receiveInPlank > 0 {
            let quoteArgs = AssetConversion.QuoteArgs(
                assetIn: payChainAsset.chainAssetId,
                assetOut: receiveChainAsset.chainAssetId,
                amount: receiveInPlank,
                direction: .buy
            )
            self.quoteArgs = quoteArgs
            interactor.calculateQuote(for: quoteArgs)
        } else {
            quoteArgs = nil
            if forceUpdate {
                payAmountInput = nil
                providePayAmountInputViewModel()
            } else {
                refreshQuote(direction: .sell)
            }
        }
    }

    private func refreshQuoteForSell(payChainAsset: ChainAsset, receiveChainAsset: ChainAsset, forceUpdate: Bool) {
        if let payInPlank = getPayAmount(for: payAmountInput)?.toSubstrateAmount(
            precision: Int16(payChainAsset.assetDisplayInfo.assetPrecision)), payInPlank > 0 {
            let quoteArgs = AssetConversion.QuoteArgs(
                assetIn: payChainAsset.chainAssetId,
                assetOut: receiveChainAsset.chainAssetId,
                amount: payInPlank,
                direction: .sell
            )
            self.quoteArgs = quoteArgs
            interactor.calculateQuote(for: quoteArgs)
        } else {
            quoteArgs = nil
            if forceUpdate {
                receiveAmountInput = nil
                provideReceiveAmountInputViewModel()
                provideReceiveInputPriceViewModel()
            } else {
                refreshQuote(direction: .buy)
            }
        }
    }

    private func balanceMinusFee() -> Decimal? {
        guard let payChainAsset = payChainAsset else {
            return nil
        }
        let balanceValue = payAssetBalance?.transferable ?? 0
        let feeValue = payChainAsset.chainAssetId == feeChainAsset?.chainAssetId ? fee?.totalFee.targetAmount : 0

        let precision = Int16(payChainAsset.asset.precision)

        guard
            let balance = Decimal.fromSubstrateAmount(balanceValue, precision: precision),
            let fee = Decimal.fromSubstrateAmount(feeValue ?? 0, precision: precision) else {
            return 0
        }

        return max(0, balance - fee)
    }

    private func handleAssetBalanceError(chainAssetId: ChainAssetId) {
        switch chainAssetId {
        case payChainAsset?.chainAssetId:
            wireframe.presentRequestStatus(on: view, locale: selectedLocale) { [weak self] in
                self?.payChainAsset.map { self?.interactor.update(payChainAsset: $0) }
            }
        case feeChainAsset?.chainAssetId:
            wireframe.presentRequestStatus(on: view, locale: selectedLocale) { [weak self] in
                self?.feeChainAsset.map { self?.interactor.update(feeChainAsset: $0) }
            }
        default:
            break
        }
    }

    private func handlePriceError(priceId: AssetModel.PriceId) {
        wireframe.presentRequestStatus(on: view, locale: selectedLocale) { [weak self] in
            guard let self = self else {
                return
            }
            [self.payChainAsset, self.receiveChainAsset, self.feeChainAsset]
                .compactMap { $0 }
                .filter { $0.asset.priceId == priceId }
                .forEach(self.interactor.remakePriceSubscription)
        }
    }

    private func updateFeeChainAsset(_ chainAsset: ChainAsset?) {
        feeChainAsset = chainAsset
        providePayAssetViews()
        interactor.update(feeChainAsset: chainAsset)

        fee = nil
        provideFeeViewModel()

        estimateFee()
    }
}

extension SwapSetupPresenter: SwapSetupPresenterProtocol {
    func setup() {
        providePayAssetViews()
        provideReceiveAssetViews()
        provideDetailsViewModel(isAvailable: false)
        provideButtonState()
        provideSettingsState()
        // TODO: get from settings
        slippage = .fraction(from: AssetConversionConstants.defaultSlippage)?.fromPercents()
        provideErrors()

        interactor.setup()
        interactor.update(payChainAsset: payChainAsset)
        interactor.update(feeChainAsset: feeChainAsset)
    }

    func selectPayToken() {
        wireframe.showPayTokenSelection(from: view, chainAsset: receiveChainAsset) { [weak self] chainAsset in
            self?.payChainAsset = chainAsset
            let feeChainAsset = chainAsset.chain.utilityAsset().map {
                ChainAsset(chain: chainAsset.chain, asset: $0)
            }

            self?.feeChainAsset = feeChainAsset
            self?.fee = nil
            self?.canPayFeeInPayAsset = false

            self?.providePayAssetViews()
            self?.provideButtonState()
            self?.provideSettingsState()
            self?.provideFeeViewModel()
            self?.provideErrors()

            self?.interactor.update(payChainAsset: chainAsset)
            self?.interactor.update(feeChainAsset: feeChainAsset)

            if let direction = self?.quoteArgs?.direction {
                self?.refreshQuote(direction: direction, forceUpdate: false)
            } else if self?.payAmountInput != nil {
                self?.refreshQuote(direction: .sell, forceUpdate: false)
            } else {
                self?.refreshQuote(direction: .buy, forceUpdate: false)
            }
        }
    }

    func selectReceiveToken() {
        wireframe.showReceiveTokenSelection(from: view, chainAsset: payChainAsset) { [weak self] chainAsset in
            self?.receiveChainAsset = chainAsset
            self?.provideReceiveAssetViews()
            self?.provideButtonState()

            self?.interactor.update(receiveChainAsset: chainAsset)

            if let direction = self?.quoteArgs?.direction {
                self?.refreshQuote(direction: direction, forceUpdate: false)
            } else if self?.receiveAmountInput != nil {
                self?.refreshQuote(direction: .buy, forceUpdate: false)
            } else {
                self?.refreshQuote(direction: .sell, forceUpdate: false)
            }
        }
    }

    func updatePayAmount(_ amount: Decimal?) {
        payAmountInput = amount.map { .absolute($0) }
        refreshQuote(direction: .sell)
        provideButtonState()
        provideErrors()
    }

    func updateReceiveAmount(_ amount: Decimal?) {
        receiveAmountInput = amount
        refreshQuote(direction: .buy)
        provideButtonState()
    }

    func flip(currentFocus: TextFieldFocus?) {
        let payAmount = getPayAmount(for: payAmountInput)
        let receiveAmount = receiveAmountInput.map { AmountInputResult.absolute($0) }

        Swift.swap(&payChainAsset, &receiveChainAsset)
        canPayFeeInPayAsset = false

        interactor.update(payChainAsset: payChainAsset)
        interactor.update(receiveChainAsset: receiveChainAsset)
        let newFocus: TextFieldFocus?

        switch currentFocus {
        case .payAsset:
            newFocus = .receiveAsset
        case .receiveAsset:
            newFocus = .payAsset
        case .none:
            newFocus = nil
        }

        switch quoteArgs?.direction {
        case .sell:
            receiveAmountInput = payAmount
            payAmountInput = nil
            refreshQuote(direction: .buy, forceUpdate: false)
        case .buy:
            payAmountInput = receiveAmount
            receiveAmountInput = nil
            refreshQuote(direction: .sell, forceUpdate: false)
        case .none:
            payAmountInput = nil
            receiveAmountInput = nil
        }

        providePayAssetViews()
        provideReceiveAssetViews()
        provideButtonState()
        provideSettingsState()
        provideFeeViewModel()
        provideErrors()

        view?.didReceive(focus: newFocus)
    }

    func selectMaxPayAmount() {
        payAmountInput = .rate(1)
        providePayAssetViews()
        refreshQuote(direction: .sell)
        provideButtonState()
        provideErrors()
    }

    func showFeeActions() {
        guard let payChainAsset = payChainAsset,
              let utilityAsset = payChainAsset.chain.utilityChainAsset() else {
            return
        }
        let payAssetSelected = feeChainAsset?.chainAssetId == payChainAsset.chainAssetId
        let viewModel = SwapNetworkFeeSheetViewModel(
            title: FeeSelectionViewModel.title,
            message: FeeSelectionViewModel.message,
            sectionTitle: { section in
                .init { _ in
                    FeeSelectionViewModel(rawValue: section) == .utilityAsset ?
                        utilityAsset.asset.symbol : payChainAsset.asset.symbol
                }
            },
            action: { [weak self] in
                let chainAsset = FeeSelectionViewModel(rawValue: $0) == .utilityAsset ? utilityAsset : payChainAsset
                self?.updateFeeChainAsset(chainAsset)
            },
            selectedIndex: payAssetSelected ? FeeSelectionViewModel.payAsset.rawValue :
                FeeSelectionViewModel.utilityAsset.rawValue,
            count: FeeSelectionViewModel.allCases.count,
            hint: FeeSelectionViewModel.hint
        )

        wireframe.showNetworkFeeAssetSelection(
            form: view,
            viewModel: viewModel
        )
    }

    func showFeeInfo() {
        wireframe.showFeeInfo(from: view)
    }

    func showRateInfo() {
        wireframe.showRateInfo(from: view)
    }

    func proceed() {
        guard let payChainAsset = payChainAsset,
              let feeChainAsset = feeChainAsset else {
            return
        }

        let validators = validators(
            spendingAmount: getPayAmount(for: payAmountInput),
            payChainAsset: payChainAsset,
            feeChainAsset: feeChainAsset
        )

        DataValidationRunner(validators: validators).runValidation { [weak self] in
            guard let receiveChainAsset = self?.receiveChainAsset,
                  let slippage = self?.slippage,
                  let quote = self?.quote,
                  let quoteArgs = self?.quoteArgs else {
                return
            }

            let confirmInitState = SwapConfirmInitState(
                chainAssetIn: payChainAsset,
                chainAssetOut: receiveChainAsset,
                feeChainAsset: feeChainAsset,
                slippage: slippage,
                quote: quote,
                quoteArgs: quoteArgs
            )

            self?.wireframe.showConfirmation(
                from: self?.view,
                initState: confirmInitState
            )
        }
    }

    func showSettings() {
        guard let payChainAsset = payChainAsset else {
            return
        }
        wireframe.showSettings(
            from: view,
            percent: slippage,
            chainAsset: payChainAsset
        ) { [weak self, payChainAsset] slippageValue in
            guard payChainAsset.chainAssetId == self?.payChainAsset?.chainAssetId else {
                return
            }
            self?.slippage = slippageValue
            self?.estimateFee()
        }
    }

    func depositInsufficientToken() {
        guard let payChainAsset = payChainAsset, let accountId = accountId else {
            return
        }

        purchaseActions = purchaseProvider.buildPurchaseActions(for: payChainAsset, accountId: accountId)
        let sendAvailable = TokenOperation.checkTransferOperationAvailable()
        let crossChainSendAvailable = depositCrossChainAssets.first != nil && sendAvailable

        let recieveAvailable = TokenOperation.checkReceiveOperationAvailable(
            walletType: selectedAccount.type,
            chainAsset: payChainAsset
        ).available
        let buyAvailable = TokenOperation.checkBuyOperationAvailable(
            purchaseActions: purchaseActions,
            walletType: selectedAccount.type,
            chainAsset: payChainAsset
        ).available
        depositOperations = [
            .init(operation: .send, active: crossChainSendAvailable),
            .init(operation: .receive, active: recieveAvailable),
            .init(operation: .buy, active: buyAvailable)
        ]
        wireframe.showTokenDepositOptions(
            form: view,
            operations: depositOperations,
            token: payChainAsset.asset.symbol,
            delegate: self
        )
    }
}

extension SwapSetupPresenter: SwapSetupInteractorOutputProtocol {
    func didReceive(baseError: SwapBaseError) {
        logger.error("Did receive base error: \(baseError)")

        switch baseError {
        case let .quote(_, args):
            guard args == quoteArgs else {
                return
            }
            wireframe.presentRequestStatus(on: view, locale: selectedLocale) { [weak self] in
                self?.refreshQuote(direction: args.direction)
            }
        case let .fetchFeeFailed(_, id, feeChainAssetId):
            let identifier = SwapSetupFeeIdentifier(transactionId: id, feeChainAssetId: feeChainAssetId)
            guard identifier == feeIdentifier else {
                return
            }
            wireframe.presentRequestStatus(on: view, locale: selectedLocale) { [weak self] in
                self?.estimateFee()
            }
        case let .price(_, priceId):
            handlePriceError(priceId: priceId)
        case let .assetBalance(_, chainAssetId, _):
            handleAssetBalanceError(chainAssetId: chainAssetId)
        }
    }

    func didReceive(setupError: SwapSetupError) {
        logger.error("Did receive setup error: \(setupError)")

        switch setupError {
        case .payAssetSetFailed:
            wireframe.presentRequestStatus(on: view, locale: selectedLocale) { [weak self] in
                if let payChainAsset = self?.payChainAsset {
                    self?.interactor.update(payChainAsset: payChainAsset)
                }
            }
        case .xcm:
            wireframe.presentRequestStatus(on: view, locale: selectedLocale) { [weak self] in
                self?.interactor.setupXcm()
            }
        }
    }

    func didReceive(quote: AssetConversion.Quote, for quoteArgs: AssetConversion.QuoteArgs) {
        guard quoteArgs == self.quoteArgs else {
            return
        }

        self.quote = quote

        switch quoteArgs.direction {
        case .buy:
            let payAmount = payChainAsset.map {
                Decimal.fromSubstrateAmount(
                    quote.amountIn,
                    precision: Int16($0.asset.precision)
                ) ?? 0
            }
            payAmountInput = payAmount.map { .absolute($0) }
            providePayAmountInputViewModel()
        case .sell:
            receiveAmountInput = receiveChainAsset.map {
                Decimal.fromSubstrateAmount(
                    quote.amountOut,
                    precision: $0.asset.displayInfo.assetPrecision
                ) ?? 0
            }
            provideReceiveAmountInputViewModel()
            provideReceiveInputPriceViewModel()
        }

        provideRateViewModel()
        estimateFee()
        provideButtonState()
    }

    func didReceive(
        fee: AssetConversion.FeeModel?,
        transactionId: TransactionFeeId,
        feeChainAssetId: FeeChainAssetId?
    ) {
        let identifier = SwapSetupFeeIdentifier(
            transactionId: transactionId,
            feeChainAssetId: feeChainAssetId
        )

        guard identifier == feeIdentifier else {
            return
        }

        self.fee = fee
        provideFeeViewModel()
        provideButtonState()
        provideErrors()
    }

    func didReceive(price: PriceData?, priceId: AssetModel.PriceId) {
        if let payChainAsset = payChainAsset, priceId == payChainAsset.asset.priceId {
            prices[payChainAsset.chainAssetId] = price
            providePayInputPriceViewModel()
        }

        if let receiveChainAsset = receiveChainAsset, priceId == receiveChainAsset.asset.priceId {
            prices[receiveChainAsset.chainAssetId] = price
            provideReceiveInputPriceViewModel()
        }

        if let feeChainAsset = feeChainAsset, priceId == feeChainAsset.asset.priceId {
            prices[feeChainAsset.chainAssetId] = price
            provideFeeViewModel()
        }
    }

    func didReceive(payAccountId: AccountId?) {
        accountId = payAccountId
        provideErrors()
    }

    func didReceive(balance: AssetBalance?, for chainAsset: ChainAssetId, accountId _: AccountId) {
        balances[chainAsset] = balance

        if chainAsset == payChainAsset?.chainAssetId {
            providePayTitle()
            provideErrors()

            if case .rate = payAmountInput {
                providePayInputPriceViewModel()
                providePayAmountInputViewModel()
                provideButtonState()
            }
        }
    }

    func didReceiveCanPayFeeInPayAsset(_ value: Bool, chainAssetId: ChainAssetId) {
        if payChainAsset?.chainAssetId == chainAssetId {
            canPayFeeInPayAsset = value

            provideFeeViewModel()
        }
    }

    func didReceiveAvailableXcm(origins: [ChainAsset], xcmTransfers: XcmTransfers?) {
        depositCrossChainAssets = origins
        self.xcmTransfers = xcmTransfers
    }
}

extension SwapSetupPresenter: Localizable {
    func applyLocalization() {
        if view?.isSetup == true {
            setup()
            viewModelFactory.locale = selectedLocale
        }
    }
}

extension SwapSetupPresenter: ModalPickerViewControllerDelegate {
    func modalPickerDidSelectModelAtIndex(_ index: Int, context _: AnyObject?) {
        guard let operation = depositOperations[safe: index], operation.active else {
            return
        }

        switch operation.operation {
        case .buy:
            startPuchaseFlow(
                from: view,
                purchaseActions: purchaseActions,
                wireframe: wireframe,
                locale: selectedLocale
            )
        case .receive:
            guard let payChainAsset = payChainAsset,
                  let metaChainAccountResponse = selectedAccount.fetchMetaChainAccount(for: payChainAsset.chain.accountRequest()) else {
                return
            }
            wireframe.showDepositTokensByReceive(
                from: view,
                chainAsset: payChainAsset,
                metaChainAccountResponse: metaChainAccountResponse
            )
        case .send:
            guard let payChainAsset = payChainAsset,
                  let accountId = accountId,
                  let address = try? accountId.toAddress(using: payChainAsset.chain.chainFormat),
                  let origin = depositCrossChainAssets.first,
                  let xcmTransfers = xcmTransfers else {
                return
            }
            wireframe.showDepositTokensBySend(
                from: view,
                origin: origin,
                destination: payChainAsset,
                recepient: .init(address: address, username: ""),
                xcmTransfers: xcmTransfers
            )
        }
    }
}

extension SwapSetupPresenter: PurchaseDelegate {
    func purchaseDidComplete() {
        wireframe.presentPurchaseDidComplete(view: view, locale: selectedLocale)
    }
}
