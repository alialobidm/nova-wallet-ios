import UIKit

extension TitleHorizontalMultiValueView {
    struct Model {
        let title: String
        let subtitle: String
        let value: String
    }

    func bind(viewModel: LoadableViewModelState<Model>) {
        switch viewModel {
        case .loading:
            // TODO:
            break
        case let .cached(value), let .loaded(value):
            titleView.text = value.title
            detailsTitleLabel.text = value.subtitle
            detailsValueLabel.text = value.value
        }
    }

    func bind(balance: Model) {
        titleView.text = balance.title
        detailsTitleLabel.text = balance.subtitle
        detailsValueLabel.text = balance.value
    }
}
