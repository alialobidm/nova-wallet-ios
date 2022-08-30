import Foundation
import SoraFoundation
import CommonWallet
import BigInt

protocol StakingMainViewProtocol: ControllerBackedProtocol, Localizable {
    func didReceive(viewModel: StakingMainViewModel)
    func didRecieveNetworkStakingInfo(viewModel: LocalizableResource<NetworkStakingInfoViewModel>?)
    func didReceiveStakingState(viewModel: StakingViewState)
    func expandNetworkInfoView(_ isExpanded: Bool)
    func didReceiveStatics(viewModel: StakingMainStaticViewModelProtocol)
}

protocol StakingMainPresenterProtocol: AnyObject {
    func setup()
    func performAssetSelection()
    func performMainAction()
    func performAccountAction()
    func performRewardInfoAction()
    func performChangeValidatorsAction()
    func performSetupValidatorsForBondedAction()
    func performStakeMoreAction()
    func performRedeemAction()
    func performRebondAction()
    func performAnalyticsAction()
    func networkInfoViewDidChangeExpansion(isExpanded: Bool)
    func performManageAction(_ action: StakingManageOption)
}

protocol StakingMainInteractorInputProtocol: AnyObject {
    func setup()
    func saveNetworkInfoViewExpansion(isExpanded: Bool)
    func save(chainAsset: ChainAsset)
}

protocol StakingMainInteractorOutputProtocol: AnyObject {
    func didReceiveAccountInfo(_ accountInfo: AccountInfo?)
    func didReceiveSelectedAccount(_ metaAccount: MetaAccountModel)
    func didReceiveStakingSettings(_ stakingSettings: StakingAssetSettings)
    func didReceiveExpansion(_ isExpanded: Bool)
    func didReceiveError(_ error: Error)
}

protocol StakingMainWireframeProtocol: AlertPresentable, ErrorPresentable, StakingErrorPresentable,
    WalletSwitchPresentable {
    func showChainAssetSelection(
        from view: StakingMainViewProtocol?,
        selectedChainAssetId: ChainAssetId?,
        delegate: AssetSelectionDelegate
    )

    func showCreateAccount(
        from view: ControllerBackedProtocol?,
        wallet: MetaAccountModel,
        chain: ChainModel
    )

    func showImportAccount(
        from view: ControllerBackedProtocol?,
        wallet: MetaAccountModel,
        chain: ChainModel
    )
}

protocol StakingMainViewFactoryProtocol: AnyObject {
    static func createView() -> StakingMainViewProtocol?
}

protocol StakingMainChildPresenterProtocol: AnyObject {
    func setup()
    func performMainAction()
    func performRewardInfoAction()
    func performChangeValidatorsAction()
    func performSetupValidatorsForBondedAction()
    func performStakeMoreAction()
    func performRedeemAction()
    func performRebondAction()
    func performAnalyticsAction()
    func performManageAction(_ action: StakingManageOption)
}
