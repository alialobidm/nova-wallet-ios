import Foundation
import SubstrateSdk
import RobinHood

protocol StakingSharedStateFactoryProtocol {
    func createRelaychain(
        for stakingOption: Multistaking.ChainAssetOption
    ) throws -> RelaychainStakingSharedStateProtocol

    func createNominationPools(
        for chainAsset: ChainAsset,
        consensus: ConsensusType
    ) throws -> NPoolsStakingSharedStateProtocol

    func createParachain(
        for stakingOption: Multistaking.ChainAssetOption
    ) throws -> ParachainStakingSharedStateProtocol

    func createStartRelaychainStaking(
        for chainAsset: ChainAsset,
        consensus: ConsensusType,
        selectedStakingType: StakingType?
    ) throws -> RelaychainStartStakingStateProtocol
}

enum StakingSharedStateFactoryError: Error {
    case unsupported
}

final class StakingSharedStateFactory {
    struct RelaychainGlobalCommonServices {
        let globalRemoteSubscriptionService: StakingRemoteSubscriptionServiceProtocol
        let eraValidatorService: EraValidatorServiceProtocol
        let rewardCalculatorService: RewardCalculatorServiceProtocol
        let timeModel: StakingTimeModel
        let localSubscriptionFactory: StakingLocalSubscriptionFactoryProtocol
    }

    struct RelaychainCommonServices {
        let globalRemoteSubscriptionService: StakingRemoteSubscriptionServiceProtocol
        let accountRemoteSubscriptionService: StakingAccountUpdatingServiceProtocol
        let eraValidatorService: EraValidatorServiceProtocol
        let rewardCalculatorService: RewardCalculatorServiceProtocol
        let timeModel: StakingTimeModel
        let localSubscriptionFactory: StakingLocalSubscriptionFactoryProtocol
        let proxySubscriptionFactory: ProxyListLocalSubscriptionFactoryProtocol
        let proxyRemoteSubscriptionService: ProxyAccountUpdatingServiceProtocol?
    }

    struct NominationPoolsServices {
        let remoteSubscriptionService: NominationPoolsRemoteSubscriptionServiceProtocol?
        let accountSubscriptionServiceFactory: NominationPoolsAccountUpdatingFactoryProtocol?
        let localSubscriptionFactory: NPoolsLocalSubscriptionFactoryProtocol
        let activePoolsService: EraNominationPoolsServiceProtocol?
    }

    let storageFacade: StorageFacadeProtocol
    let chainRegistry: ChainRegistryProtocol
    let eventCenter: EventCenterProtocol
    let proxySyncService: ProxySyncServiceProtocol?
    let syncOperationQueue: OperationQueue
    let repositoryOperationQueue: OperationQueue
    let logger: LoggerProtocol

    init(
        storageFacade: StorageFacadeProtocol,
        chainRegistry: ChainRegistryProtocol,
        proxySyncService: ProxySyncServiceProtocol?,
        eventCenter: EventCenterProtocol,
        syncOperationQueue: OperationQueue,
        repositoryOperationQueue: OperationQueue,
        logger: LoggerProtocol
    ) {
        self.storageFacade = storageFacade
        self.proxySyncService = proxySyncService
        self.chainRegistry = chainRegistry
        self.eventCenter = eventCenter
        self.syncOperationQueue = syncOperationQueue
        self.repositoryOperationQueue = repositoryOperationQueue
        self.logger = logger
    }

    private func createRelaychainGlobalCommonServices(
        for consensus: ConsensusType,
        chainAsset: ChainAsset
    ) throws -> RelaychainGlobalCommonServices {
        let substrateRepositoryFactory = SubstrateRepositoryFactory(storageFacade: storageFacade)

        let substrateRepository = substrateRepositoryFactory.createChainStorageItemRepository()
        let globalRemoteSubscriptionService = StakingRemoteSubscriptionService(
            chainRegistry: chainRegistry,
            repository: substrateRepository,
            syncOperationManager: OperationManager(operationQueue: syncOperationQueue),
            repositoryOperationManager: OperationManager(operationQueue: repositoryOperationQueue),
            logger: logger
        )

        let stakingServiceFactory = StakingServiceFactory(
            chainRegisty: chainRegistry,
            storageFacade: storageFacade,
            eventCenter: eventCenter,
            operationQueue: syncOperationQueue,
            logger: logger
        )

        let chainId = chainAsset.chain.chainId

        let localSubscriptionFactory = StakingLocalSubscriptionFactory(
            chainRegistry: chainRegistry,
            storageFacade: storageFacade,
            operationManager: OperationManager(operationQueue: repositoryOperationQueue),
            logger: logger
        )

        let eraValidatorService = try stakingServiceFactory.createEraValidatorService(
            for: chainId,
            localSubscriptionFactory: localSubscriptionFactory
        )

        let timeModel = try stakingServiceFactory.createTimeModel(for: chainId, consensus: consensus)

        let durationFactory = RelaychainConsensusStateDependingFactory().createStakingDurationOperationFactory(
            for: chainAsset.chain,
            timeModel: timeModel
        )

        let rewardCalculatorService = try stakingServiceFactory.createRewardCalculatorService(
            for: chainAsset,
            stakingType: consensus.stakingType,
            stakingLocalSubscriptionFactory: localSubscriptionFactory,
            stakingDurationFactory: durationFactory,
            validatorService: eraValidatorService
        )

        return .init(
            globalRemoteSubscriptionService: globalRemoteSubscriptionService,
            eraValidatorService: eraValidatorService,
            rewardCalculatorService: rewardCalculatorService,
            timeModel: timeModel,
            localSubscriptionFactory: localSubscriptionFactory
        )
    }

    private func createRelaychainCommonServices(
        for consensus: ConsensusType,
        chainAsset: ChainAsset
    ) throws -> RelaychainCommonServices {
        let globalServices = try createRelaychainGlobalCommonServices(for: consensus, chainAsset: chainAsset)

        let substrateRepositoryFactory = SubstrateRepositoryFactory(storageFacade: storageFacade)

        let substrateDataProviderFactory = SubstrateDataProviderFactory(
            facade: storageFacade,
            operationManager: OperationManager(operationQueue: repositoryOperationQueue)
        )

        let childSubscriptionFactory = ChildSubscriptionFactory(
            storageFacade: storageFacade,
            operationManager: OperationManager(operationQueue: repositoryOperationQueue),
            eventCenter: eventCenter,
            logger: logger
        )

        let accountRemoteSubscriptionService = StakingAccountUpdatingService(
            chainRegistry: chainRegistry,
            substrateRepositoryFactory: substrateRepositoryFactory,
            substrateDataProviderFactory: substrateDataProviderFactory,
            childSubscriptionFactory: childSubscriptionFactory,
            operationQueue: syncOperationQueue
        )

        let proxyRemoteSubscriptionService = proxySyncService.map {
            ProxyAccountUpdatingService(
                chainRegistry: chainRegistry,
                proxySyncService: $0,
                storageFacade: storageFacade,
                operationQueue: syncOperationQueue,
                logger: logger
            )
        }

        return .init(
            globalRemoteSubscriptionService: globalServices.globalRemoteSubscriptionService,
            accountRemoteSubscriptionService: accountRemoteSubscriptionService,
            eraValidatorService: globalServices.eraValidatorService,
            rewardCalculatorService: globalServices.rewardCalculatorService,
            timeModel: globalServices.timeModel,
            localSubscriptionFactory: globalServices.localSubscriptionFactory,
            proxySubscriptionFactory: ProxyListLocalSubscriptionFactory.shared,
            proxyRemoteSubscriptionService: proxyRemoteSubscriptionService
        )
    }

    // swiftlint:disable:next function_body_length
    func createNominationPoolsServices(
        for chainAsset: ChainAsset,
        eraValidatorService: EraValidatorServiceProtocol
    ) throws -> NominationPoolsServices {
        let localSubscriptionFactory = NPoolsLocalSubscriptionFactory(
            chainRegistry: chainRegistry,
            storageFacade: storageFacade,
            operationManager: OperationManager(operationQueue: repositoryOperationQueue),
            logger: logger
        )

        guard chainAsset.asset.supportsNominationPoolsStaking else {
            return NominationPoolsServices(
                remoteSubscriptionService: nil,
                accountSubscriptionServiceFactory: nil,
                localSubscriptionFactory: localSubscriptionFactory,
                activePoolsService: nil
            )
        }

        let substrateRepositoryFactory = SubstrateRepositoryFactory(storageFacade: storageFacade)

        let substrateRepository = substrateRepositoryFactory.createChainStorageItemRepository()

        let remoteSubsriptionService = NominationPoolsRemoteSubscriptionService(
            chainRegistry: chainRegistry,
            repository: substrateRepository,
            syncOperationManager: OperationManager(operationQueue: syncOperationQueue),
            repositoryOperationManager: OperationManager(operationQueue: repositoryOperationQueue),
            logger: logger
        )

        let poolSubscriptionService = NominationPoolsPoolSubscriptionService(
            chainRegistry: chainRegistry,
            repository: substrateRepository,
            syncOperationManager: OperationManager(operationQueue: syncOperationQueue),
            repositoryOperationManager: OperationManager(operationQueue: repositoryOperationQueue),
            logger: logger
        )

        let accountServiceFactory = NominationPoolsAccountUpdatingFactory(
            chainRegistry: chainRegistry,
            repositoryFactory: substrateRepositoryFactory,
            remoteSubscriptionService: poolSubscriptionService,
            npoolsLocalSubscriptionFactory: localSubscriptionFactory,
            operationQueue: repositoryOperationQueue,
            logger: logger
        )

        guard let runtimeService = chainRegistry.getRuntimeProvider(for: chainAsset.chain.chainId) else {
            throw ChainRegistryError.runtimeMetadaUnavailable
        }

        let remoteOperationFactory = NominationPoolsOperationFactory(operationQueue: syncOperationQueue)

        let activePoolsService = EraNominationPoolsService(
            chainAsset: chainAsset,
            runtimeCodingService: runtimeService,
            operationFactory: remoteOperationFactory,
            npoolsLocalSubscriptionFactory: localSubscriptionFactory,
            eraValidatorService: eraValidatorService,
            operationQueue: syncOperationQueue
        )

        return .init(
            remoteSubscriptionService: remoteSubsriptionService,
            accountSubscriptionServiceFactory: accountServiceFactory,
            localSubscriptionFactory: localSubscriptionFactory,
            activePoolsService: activePoolsService
        )
    }
}

extension StakingSharedStateFactory: StakingSharedStateFactoryProtocol {
    func createRelaychain(
        for stakingOption: Multistaking.ChainAssetOption
    ) throws -> RelaychainStakingSharedStateProtocol {
        guard let consensus = ConsensusType(stakingType: stakingOption.type) else {
            throw StakingSharedStateFactoryError.unsupported
        }

        let services = try createRelaychainCommonServices(for: consensus, chainAsset: stakingOption.chainAsset)

        return RelaychainStakingSharedState(
            consensus: consensus,
            stakingOption: stakingOption,
            globalRemoteSubscriptionService: services.globalRemoteSubscriptionService,
            accountRemoteSubscriptionService: services.accountRemoteSubscriptionService,
            proxyRemoteSubscriptionService: services.proxyRemoteSubscriptionService,
            localSubscriptionFactory: services.localSubscriptionFactory,
            proxyLocalSubscriptionFactory: services.proxySubscriptionFactory,
            eraValidatorService: services.eraValidatorService,
            rewardCalculatorService: services.rewardCalculatorService,
            timeModel: services.timeModel,
            logger: logger
        )
    }

    func createNominationPools(
        for chainAsset: ChainAsset,
        consensus: ConsensusType
    ) throws -> NPoolsStakingSharedStateProtocol {
        let relaychainServices = try createRelaychainGlobalCommonServices(for: consensus, chainAsset: chainAsset)
        let nominationPoolServices = try createNominationPoolsServices(
            for: chainAsset,
            eraValidatorService: relaychainServices.eraValidatorService
        )

        guard
            let npRemoteSubscriptionService = nominationPoolServices.remoteSubscriptionService,
            let npAccountSubscriptionServiceFactory = nominationPoolServices.accountSubscriptionServiceFactory,
            let activePoolsService = nominationPoolServices.activePoolsService else {
            throw ChainAccountFetchingError.accountNotExists
        }

        return NPoolsStakingSharedState(
            chainAsset: chainAsset,
            relaychainGlobalSubscriptionService: relaychainServices.globalRemoteSubscriptionService,
            timeModel: relaychainServices.timeModel,
            relaychainLocalSubscriptionFactory: relaychainServices.localSubscriptionFactory,
            eraValidatorService: relaychainServices.eraValidatorService,
            rewardCalculatorService: relaychainServices.rewardCalculatorService,
            npRemoteSubscriptionService: npRemoteSubscriptionService,
            npAccountSubscriptionServiceFactory: npAccountSubscriptionServiceFactory,
            activePoolsService: activePoolsService,
            npLocalSubscriptionFactory: nominationPoolServices.localSubscriptionFactory,
            logger: logger
        )
    }

    // swiftlint:disable:next function_body_length
    func createParachain(
        for stakingOption: Multistaking.ChainAssetOption
    ) throws -> ParachainStakingSharedStateProtocol {
        let repositoryFactory = SubstrateRepositoryFactory()
        let repository = repositoryFactory.createChainStorageItemRepository()

        let stakingAccountService = ParachainStaking.AccountSubscriptionService(
            chainRegistry: chainRegistry,
            repository: repository,
            syncOperationManager: OperationManager(operationQueue: syncOperationQueue),
            repositoryOperationManager: OperationManager(operationQueue: repositoryOperationQueue),
            logger: logger
        )

        let stakingAssetService = ParachainStaking.StakingRemoteSubscriptionService(
            chainRegistry: chainRegistry,
            repository: repository,
            syncOperationManager: OperationManager(operationQueue: syncOperationQueue),
            repositoryOperationManager: OperationManager(operationQueue: repositoryOperationQueue),
            logger: logger
        )

        let localSubscriptionFactory = ParachainStakingLocalSubscriptionFactory(
            chainRegistry: chainRegistry,
            storageFacade: storageFacade,
            operationManager: OperationManager(operationQueue: repositoryOperationQueue),
            logger: logger
        )

        let serviceFactory = ParachainStakingServiceFactory(
            stakingProviderFactory: localSubscriptionFactory,
            chainRegisty: chainRegistry,
            storageFacade: storageFacade,
            eventCenter: eventCenter,
            operationQueue: syncOperationQueue,
            logger: logger
        )

        let chainId = stakingOption.chainAsset.chain.chainId

        let collatorService = try serviceFactory.createSelectedCollatorsService(for: chainId)
        let blockTimeService = try serviceFactory.createBlockTimeService(for: chainId)
        let rewardService = try serviceFactory.createRewardCalculatorService(
            for: chainId,
            stakingType: stakingOption.type,
            assetPrecision: stakingOption.chainAsset.asset.decimalPrecision,
            collatorService: collatorService
        )

        let generalLocalSubscriptionFactory = GeneralStorageSubscriptionFactory(
            chainRegistry: chainRegistry,
            storageFacade: storageFacade,
            operationManager: OperationManager(operationQueue: repositoryOperationQueue),
            logger: logger
        )

        return ParachainStakingSharedState(
            stakingOption: stakingOption,
            chainRegistry: chainRegistry,
            globalRemoteSubscriptionService: stakingAssetService,
            accountRemoteSubscriptionService: stakingAccountService,
            collatorService: collatorService,
            rewardCalculationService: rewardService,
            blockTimeService: blockTimeService,
            stakingLocalSubscriptionFactory: localSubscriptionFactory,
            generalLocalSubscriptionFactory: generalLocalSubscriptionFactory,
            logger: logger
        )
    }

    func createStartRelaychainStaking(
        for chainAsset: ChainAsset,
        consensus: ConsensusType,
        selectedStakingType: StakingType?
    ) throws -> RelaychainStartStakingStateProtocol {
        let relaychainServices = try createRelaychainCommonServices(for: consensus, chainAsset: chainAsset)

        let nominationPoolsService: NominationPoolsServices = try createNominationPoolsServices(
            for: chainAsset,
            eraValidatorService: relaychainServices.eraValidatorService
        )

        return RelaychainStartStakingState(
            stakingType: selectedStakingType,
            consensus: consensus,
            chainAsset: chainAsset,
            relaychainGlobalSubscriptionService: relaychainServices.globalRemoteSubscriptionService,
            relaychainAccountSubscriptionService: relaychainServices.accountRemoteSubscriptionService,
            timeModel: relaychainServices.timeModel,
            relaychainLocalSubscriptionFactory: relaychainServices.localSubscriptionFactory,
            eraValidatorService: relaychainServices.eraValidatorService,
            relaychainRewardCalculatorService: relaychainServices.rewardCalculatorService,
            npRemoteSubscriptionService: nominationPoolsService.remoteSubscriptionService,
            npAccountSubscriptionServiceFactory: nominationPoolsService.accountSubscriptionServiceFactory,
            npLocalSubscriptionFactory: nominationPoolsService.localSubscriptionFactory,
            activePoolsService: nominationPoolsService.activePoolsService,
            logger: logger
        )
    }
}
