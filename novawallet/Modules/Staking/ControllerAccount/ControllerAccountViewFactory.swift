import Foundation
import SoraFoundation
import SoraKeystore
import SubstrateSdk
import RobinHood

struct ControllerAccountViewFactory {
    static func createView(for state: RelaychainStakingSharedStateProtocol) -> ControllerAccountViewProtocol? {
        let chainAsset = state.stakingOption.chainAsset

        guard
            let metaAccount = SelectedWalletSettings.shared.value,
            let selectedAddress = metaAccount.fetch(for: chainAsset.chain.accountRequest())?.toAddress(),
            let interactor = createInteractor(state: state) else {
            return nil
        }

        let wireframe = ControllerAccountWireframe(state: state)

        let viewModelFactory = ControllerAccountViewModelFactory(selectedAddress: selectedAddress)

        let dataValidatingFactory = StakingDataValidatingFactory(presentable: wireframe)
        let presenter = ControllerAccountPresenter(
            wireframe: wireframe,
            interactor: interactor,
            viewModelFactory: viewModelFactory,
            applicationConfig: ApplicationConfig.shared,
            assetInfo: chainAsset.assetDisplayInfo,
            dataValidatingFactory: dataValidatingFactory,
            chain: chainAsset.chain,
            logger: Logger.shared
        )

        let view = ControllerAccountViewController(
            presenter: presenter,
            localizationManager: LocalizationManager.shared
        )
        presenter.view = view
        dataValidatingFactory.view = view
        interactor.presenter = presenter

        return view
    }

    private static func createInteractor(
        state: RelaychainStakingSharedStateProtocol
    ) -> ControllerAccountInteractor? {
        let chainAsset = state.stakingOption.chainAsset

        guard
            let metaAccount = SelectedWalletSettings.shared.value,
            let selectedAccount = metaAccount.fetch(for: chainAsset.chain.accountRequest()) else {
            return nil
        }

        let facade = UserDataStorageFacade.shared
        let operationManager = OperationManagerFacade.sharedManager

        let accountRepositoryFactory = AccountRepositoryFactory(storageFacade: facade)

        let chainRegistry = ChainRegistryFacade.sharedRegistry

        guard
            let connection = chainRegistry.getConnection(for: chainAsset.chain.chainId),
            let runtimeService = chainRegistry.getRuntimeProvider(for: chainAsset.chain.chainId) else {
            return nil
        }

        let extrinsicServiceFactory = ExtrinsicServiceFactory(
            runtimeRegistry: runtimeService,
            engine: connection,
            operationManager: operationManager,
            userStorageFacade: UserDataStorageFacade.shared
        )

        let storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: operationManager
        )

        return ControllerAccountInteractor(
            selectedAccount: selectedAccount,
            chainAsset: chainAsset,
            stakingLocalSubscriptionFactory: state.localSubscriptionFactory,
            walletLocalSubscriptionFactory: WalletLocalSubscriptionFactory.shared,
            priceLocalSubscriptionFactory: PriceProviderFactory.shared,
            runtimeService: runtimeService,
            connection: connection,
            accountRepositoryFactory: accountRepositoryFactory,
            feeProxy: ExtrinsicFeeProxy(),
            extrinsicServiceFactory: extrinsicServiceFactory,
            storageRequestFactory: storageRequestFactory,
            operationManager: operationManager
        )
    }
}
