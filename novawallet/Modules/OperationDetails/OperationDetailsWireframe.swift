import Foundation

final class OperationDetailsWireframe: OperationDetailsWireframeProtocol {
    let assetListObservable: AssetListModelObservable
    let swapCompletionClosure: SwapCompletionClosure?

    init(
        assetListObservable: AssetListModelObservable,
        swapCompletionClosure: SwapCompletionClosure?
    ) {
        self.assetListObservable = assetListObservable
        self.swapCompletionClosure = swapCompletionClosure
    }

    func showSend(
        from view: OperationDetailsViewProtocol?,
        displayAddress: DisplayAddress,
        chainAsset: ChainAsset
    ) {
        guard let transferView = TransferSetupViewFactory.createView(
            from: chainAsset,
            recepient: displayAddress
        ) else {
            return
        }

        view?.controller.navigationController?.pushViewController(transferView.controller, animated: true)
    }

    func showSwapSetup(
        from view: OperationDetailsViewProtocol?,
        state: SwapSetupInitState
    ) {
        guard let swapView = SwapSetupViewFactory.createView(
            assetListObservable: assetListObservable,
            initState: state,
            swapCompletionClosure: swapCompletionClosure
        ) else {
            return
        }

        view?.controller.navigationController?.pushViewController(swapView.controller, animated: true)
    }
}
