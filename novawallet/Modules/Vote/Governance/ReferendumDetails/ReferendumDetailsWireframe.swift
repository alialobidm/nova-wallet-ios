import Foundation

final class ReferendumDetailsWireframe: ReferendumDetailsWireframeProtocol {
    let state: GovernanceSharedState

    init(state: GovernanceSharedState) {
        self.state = state
    }

    func showFullDetails(
        from view: ReferendumDetailsViewProtocol?,
        referendum: ReferendumLocal,
        actionDetails: ReferendumActionLocal,
        metadata: ReferendumMetadataLocal?,
        identities: [AccountAddress: AccountIdentity]
    ) {
        guard
            let fullDetailsView = ReferendumFullDetailsViewFactory.createView(
                state: state,
                referendum: referendum,
                actionDetails: actionDetails,
                metadata: metadata,
                identities: identities
            ) else {
            return
        }

        let navigationController = NovaNavigationController(rootViewController: fullDetailsView.controller)

        view?.controller.present(navigationController, animated: true)
    }

    func showVote(
        from view: ReferendumDetailsViewProtocol?,
        referendum: ReferendumLocal,
        initData: ReferendumVotingInitData
    ) {
        guard
            let voteSetupView = ReferendumVoteSetupViewFactory.createView(
                for: state,
                referendum: referendum.index,
                initData: initData
            ) else {
            return
        }

        let navigationController = ImportantFlowViewFactory.createNavigation(from: voteSetupView.controller)

        view?.controller.present(navigationController, animated: true)
    }

    func showVoters(
        from view: ReferendumDetailsViewProtocol?,
        referendum: ReferendumLocal,
        type: ReferendumVotersType
    ) {
        guard
            let votersView = ReferendumVotersViewFactory.createView(
                state: state,
                referendum: referendum,
                type: type
            ) else {
            return
        }

        let navigationController = NovaNavigationController(rootViewController: votersView.controller)

        view?.controller.present(navigationController, animated: true)
    }

    func showFullDescription(
        from view: ReferendumDetailsViewProtocol?,
        title: String,
        description: String
    ) {
        let detailsView = MarkdownDescriptionViewFactory.createReferendumFullDetailsView(
            for: title,
            description: description
        )

        let navigationController = NovaNavigationController(
            rootViewController: detailsView.controller
        )

        view?.controller.present(navigationController, animated: true)
    }

    func showDApp(from view: ReferendumDetailsViewProtocol?, url: URL) {
        guard
            let browser = DAppBrowserViewFactory.createView(
                for: .query(string: url.absoluteString)
            ) else {
            return
        }

        view?.controller.navigationController?.pushViewController(browser.controller, animated: true)
    }

    func showWalletDetails(from view: ControllerBackedProtocol?, wallet: MetaAccountModel) {
        guard let accountManagementView = AccountManagementViewFactory.createView(for: wallet.identifier) else {
            return
        }

        view?.controller.navigationController?.pushViewController(accountManagementView.controller, animated: true)
    }
}
