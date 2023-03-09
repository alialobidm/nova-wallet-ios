import UIKit
import RobinHood
import BigInt

final class StakingRebagConfirmInteractor: AnyProviderAutoCleaning, AnyCancellableCleaning, AccountFetching {
    weak var presenter: StakingRebagConfirmInteractorOutputProtocol!

    let chainAsset: ChainAsset
    var chainId: ChainModel.Id { chainAsset.chain.chainId }

    let selectedAccount: MetaChainAccountResponse
    let walletLocalSubscriptionFactory: WalletLocalSubscriptionFactoryProtocol
    let priceLocalSubscriptionFactory: PriceProviderFactoryProtocol
    let feeProxy: ExtrinsicFeeProxyProtocol
    let stakingLocalSubscriptionFactory: StakingLocalSubscriptionFactoryProtocol
    let networkInfoFactory: NetworkStakingInfoOperationFactoryProtocol
    let eraValidatorService: EraValidatorServiceProtocol?
    let chainRegistry: ChainRegistryProtocol
    let extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol
    let signingWrapperFactory: SigningWrapperFactoryProtocol
    let accountRepositoryFactory: AccountRepositoryFactoryProtocol

    private let operationManager: OperationManagerProtocol

    private var networkInfoCancellable: CancellableCall?

    private var priceProvider: AnySingleValueProvider<PriceData>?
    private var balanceProvider: StreamableProvider<AssetBalance>?
    private var stashControllerProvider: StreamableProvider<StashItem>?
    private var ledgerProvider: AnyDataProvider<DecodedLedgerInfo>?
    private var bagListNodeProvider: AnyDataProvider<DecodedBagListNode>?
    private var totalIssuanceProvider: AnyDataProvider<DecodedBigUInt>?

    private var extrinsicService: ExtrinsicServiceProtocol?
    private var signingWrapper: SigningWrapperProtocol?

    init(
        chainAsset: ChainAsset,
        selectedAccount: MetaChainAccountResponse,
        chainRegistry: ChainRegistryProtocol,
        feeProxy: ExtrinsicFeeProxyProtocol,
        walletLocalSubscriptionFactory: WalletLocalSubscriptionFactoryProtocol,
        priceLocalSubscriptionFactory: PriceProviderFactoryProtocol,
        stakingLocalSubscriptionFactory: StakingLocalSubscriptionFactoryProtocol,
        networkInfoFactory: NetworkStakingInfoOperationFactoryProtocol,
        eraValidatorService: EraValidatorServiceProtocol?,
        extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol,
        signingWrapperFactory: SigningWrapperFactoryProtocol,
        accountRepositoryFactory: AccountRepositoryFactoryProtocol,
        operationManager: OperationManagerProtocol,
        currencyManager: CurrencyManagerProtocol
    ) {
        self.chainAsset = chainAsset
        self.selectedAccount = selectedAccount
        self.feeProxy = feeProxy
        self.walletLocalSubscriptionFactory = walletLocalSubscriptionFactory
        self.priceLocalSubscriptionFactory = priceLocalSubscriptionFactory
        self.networkInfoFactory = networkInfoFactory
        self.eraValidatorService = eraValidatorService
        self.operationManager = operationManager
        self.stakingLocalSubscriptionFactory = stakingLocalSubscriptionFactory
        self.chainRegistry = chainRegistry
        self.extrinsicServiceFactory = extrinsicServiceFactory
        self.signingWrapperFactory = signingWrapperFactory
        self.accountRepositoryFactory = accountRepositoryFactory
        self.currencyManager = currencyManager
    }

    private func subscribePrice() {
        if let priceId = chainAsset.asset.priceId {
            priceProvider = subscribeToPrice(for: priceId, currency: selectedCurrency)
        } else {
            presenter?.didReceive(price: nil)
        }
    }

    private func subscribeAccountBalance() {
        balanceProvider = subscribeToAssetBalanceProvider(
            for: selectedAccount.chainAccount.accountId,
            chainId: chainAsset.chain.chainId,
            assetId: chainAsset.asset.assetId
        )
    }

    private func handleStashMetaAccount(response: MetaChainAccountResponse?, stashItem: StashItem?) {
        guard let response = response else {
            return
        }
        let chain = chainAsset.chain

        extrinsicService = extrinsicServiceFactory.createService(
            account: response.chainAccount,
            chain: chain
        )

        signingWrapper = signingWrapperFactory.createSigningWrapper(
            for: response.metaId,
            accountResponse: response.chainAccount
        )

        estimateFee(stashItem: stashItem)
    }

    private func stashAccountId(stashItem: StashItem?) -> AccountId? {
        guard let stashItem = stashItem else {
            return nil
        }
        return try? stashItem.stash.toAccountId()
    }

    private func subscribeStashControllerSubscription() {
        guard let address = selectedAccount.chainAccount.toAddress() else {
            subscribeBagListNode(stashItem: nil)
            return
        }

        stashControllerProvider = subscribeStashItemProvider(for: address)
    }

    private func subscribeBagListNode(stashItem: StashItem?) {
        clear(dataProvider: &bagListNodeProvider)

        guard let stashAccountId = stashAccountId(stashItem: stashItem) else {
            return
        }

        bagListNodeProvider = subscribeBagListNode(for: stashAccountId, chainId: chainId)
    }

    private func subscribeLedgerInfo(stashItem: StashItem?) {
        clear(dataProvider: &ledgerProvider)

        guard let stashItem = stashItem,
              let controllerId = try? stashItem.controller.toAccountId() else {
            return
        }

        ledgerProvider = subscribeLedgerInfo(for: controllerId, chainId: chainId)
    }

    private func provideMetaAccount(stashItem: StashItem?) {
        guard let stashAccountId = stashAccountId(stashItem: stashItem) else {
            return
        }

        fetchFirstMetaAccountResponse(
            for: stashAccountId,
            accountRequest: chainAsset.chain.accountRequest(),
            repositoryFactory: accountRepositoryFactory,
            operationManager: operationManager
        ) { [weak self] result in
            switch result {
            case let .success(response):
                self?.handleStashMetaAccount(response: response, stashItem: stashItem)
            case let .failure(error):
                self?.presenter.didReceive(error: .fetchStashItemFailed(error))
            }
        }
    }

    func subscribeTotalIssuanceSubscription() {
        clear(dataProvider: &totalIssuanceProvider)

        totalIssuanceProvider = subscribeTotalIssuance(for: chainId)
    }

    func provideNetworkStakingInfo() {
        do {
            clear(cancellable: &networkInfoCancellable)
            guard
                let runtimeService = chainRegistry.getRuntimeProvider(for: chainId),
                let eraValidatorService = eraValidatorService else {
                presenter?.didReceive(error: .networkInfo(ChainRegistryError.runtimeMetadaUnavailable))
                return
            }

            let wrapper = networkInfoFactory.networkStakingOperation(
                for: eraValidatorService,
                runtimeService: runtimeService
            )

            wrapper.targetOperation.completionBlock = { [weak self] in
                DispatchQueue.main.async {
                    guard self?.networkInfoCancellable === wrapper else {
                        return
                    }

                    self?.networkInfoCancellable = nil

                    do {
                        let info = try wrapper.targetOperation.extractNoCancellableResultData()
                        self?.networkInfo = info
                        //  self?.presenter?.didReceive(networkStakingInfo: info)
                    } catch {
                        self?.presenter?.didReceive(error: .networkInfo(error))
                    }
                }
            }

            networkInfoCancellable = wrapper

            operationManager.enqueue(operations: wrapper.allOperations, in: .transient)
        } catch {
            presenter?.didReceive(error: .networkInfo(error))
        }
    }

    var networkInfo: NetworkStakingInfo? {
        didSet {
            provideCurrentBagList()
            provideNextBagList()
        }
    }

    var currentBagListNode: BagList.Node? {
        didSet {
            provideCurrentBagList()
        }
    }

    var ledgerInfo: StakingLedger? {
        didSet {
            provideNextBagList()
        }
    }

    var totalIssuance: BigUInt? {
        didSet {
            provideNextBagList()
        }
    }

    private func provideCurrentBagList() {
        guard let votersInfo = networkInfo?.votersInfo, let currentBagListNode = currentBagListNode else {
            return
        }

        let bagUpper = currentBagListNode.bagUpper
        guard let currentBagListIndex = votersInfo.bagsThresholds.firstIndex(where: { $0 == bagUpper }) else {
            return
        }

        let bagLower = votersInfo.bagsThresholds[safe: currentBagListIndex - 1] ?? 0

        presenter.didReceive(currentBag: (bagLower, bagUpper))
    }

    private func provideNextBagList() {
        guard let ledgerInfo = ledgerInfo,
              let totalIssuance = totalIssuance,
              let votersInfo = networkInfo?.votersInfo else {
            return
        }

        let score = BagList.scoreOf(stake: ledgerInfo.active, totalIssuance: totalIssuance)
        let lowerTreshold: BigUInt
        let upperTreshold: BigUInt

        if let targetTresholdIndex = votersInfo.bagsThresholds.firstIndex(where: { $0 > score }) {
            lowerTreshold = votersInfo.bagsThresholds[safe: targetTresholdIndex - 1] ?? 0
            upperTreshold = votersInfo.bagsThresholds[targetTresholdIndex]
        } else {
            lowerTreshold = votersInfo.bagsThresholds.last ?? 0
            upperTreshold = BigUInt(UInt64.max)
        }

        presenter.didReceive(nextBag: (lowerTreshold, upperTreshold))
    }

    private func estimateFee(stashItem: StashItem?) {
        guard let extrinsicService = extrinsicService,
              let stashItem = stashItem,
              let accountId = try? stashItem.identifier.toAccountId() else {
            presenter.didReceive(error: .fetchFeeFailed(CommonError.undefined))
            return
        }

        let rebagCall = BagList.RebagCall(dislocated: .accoundId(accountId))
        let reuseIdentifier = rebagCall.runtimeCall.callName + rebagCall.extrinsicIdentifier
        feeProxy.estimateFee(using: extrinsicService, reuseIdentifier: reuseIdentifier) { builder in
            try builder.adding(call: rebagCall.runtimeCall)
        }
    }

    func submit(stashItem: StashItem?) {
        guard let extrinsicService = extrinsicService,
              let stashItem = stashItem,
              let accountId = try? stashItem.identifier.toAccountId() else {
            presenter.didReceive(error: .submitFailed(CommonError.undefined))
            return
        }

        let rebagCall = BagList.RebagCall(dislocated: .accoundId(accountId))

        extrinsicService.submit(
            { builder in
                try builder.adding(call: rebagCall.runtimeCall)
            },
            signer: signingWrapper,
            runningIn: .main,
            completion: { [weak self] _ in
                self?.presenter.didSubmitRebag()
            }
        )
    }
}

extension StakingRebagConfirmInteractor: StakingRebagConfirmInteractorInputProtocol {
    func setup() {
        feeProxy.delegate = self
        provideNetworkStakingInfo()
        subscribeAccountBalance()
        subscribePrice()
        subscribeStashControllerSubscription()
        subscribeTotalIssuanceSubscription()
    }
}

extension StakingRebagConfirmInteractor: PriceLocalStorageSubscriber, PriceLocalSubscriptionHandler {
    func handlePrice(
        result: Result<PriceData?, Error>,
        priceId _: AssetModel.PriceId
    ) {
        switch result {
        case let .success(priceData):
            presenter?.didReceive(price: priceData)
        case let .failure(error):
            presenter?.didReceive(error: .fetchPriceFailed(error))
        }
    }
}

extension StakingRebagConfirmInteractor: WalletLocalStorageSubscriber, WalletLocalSubscriptionHandler {
    func handleAssetBalance(
        result: Result<AssetBalance?, Error>,
        accountId _: AccountId,
        chainId _: ChainModel.Id,
        assetId _: AssetModel.Id
    ) {
        switch result {
        case let .success(balance):
            presenter?.didReceive(assetBalance: balance)
        case let .failure(error):
            presenter?.didReceive(error: .fetchBalanceFailed(error))
        }
    }
}

extension StakingRebagConfirmInteractor: StakingLocalStorageSubscriber, StakingLocalSubscriptionHandler {
    func handleStashItem(result: Result<StashItem?, Error>, for _: AccountAddress) {
        switch result {
        case let .success(stashItem):
            subscribeBagListNode(stashItem: stashItem)
            subscribeLedgerInfo(stashItem: stashItem)
            provideMetaAccount(stashItem: stashItem)
        case let .failure(error):
            presenter?.didReceive(error: .fetchStashItemFailed(error))
        }
    }

    func handleLedgerInfo(
        result: Result<StakingLedger?, Error>,
        accountId _: AccountId,
        chainId _: ChainModel.Id
    ) {
        switch result {
        case let .success(ledgerInfo):
            self.ledgerInfo = ledgerInfo
        case let .failure(error):
            presenter?.didReceive(error: .fetchLedgerInfoFailed(error))
        }
    }

    func handleBagListNode(
        result: Result<BagList.Node?, Error>,
        accountId _: AccountId,
        chainId _: ChainModel.Id
    ) {
        switch result {
        case let .success(node):
            currentBagListNode = node
        case let .failure(error):
            presenter.didReceive(error: .fetchBagListNodeFailed(error))
        }
    }

    func handleTotalIssuance(result: Result<BigUInt?, Error>, chainId _: ChainModel.Id) {
        switch result {
        case let .success(totalIssuance):
            self.totalIssuance = totalIssuance
        case let .failure(error):
            presenter?.didReceive(error: .fetchBagListScoreFactorFailed(error))
        }
    }
}

extension StakingRebagConfirmInteractor: ExtrinsicFeeProxyDelegate {
    func didReceiveFee(result: Result<RuntimeDispatchInfo, Error>, for _: TransactionFeeId) {
        switch result {
        case let .success(dispatchInfo):
            let fee = BigUInt(dispatchInfo.fee)
            presenter?.didReceive(fee: fee)
        case let .failure(error):
            presenter?.didReceive(error: .fetchFeeFailed(error))
        }
    }
}

extension StakingRebagConfirmInteractor: SelectedCurrencyDepending {
    func applyCurrency() {
        guard presenter != nil,
              let priceId = chainAsset.asset.priceId else {
            return
        }

        priceProvider = subscribeToPrice(for: priceId, currency: selectedCurrency)
    }
}

enum StakingRebagConfirmError: Error {
    case fetchPriceFailed(Error)
    case fetchBalanceFailed(Error)
    case fetchFeeFailed(Error)
    case fetchStashItemFailed(Error)
    case fetchBagListScoreFactorFailed(Error)
    case fetchBagListNodeFailed(Error)
    case fetchLedgerInfoFailed(Error)
    case networkInfo(Error)
    case submitFailed(Error)
}
