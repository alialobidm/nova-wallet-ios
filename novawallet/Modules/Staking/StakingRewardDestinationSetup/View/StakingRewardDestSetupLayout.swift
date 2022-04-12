import UIKit
import SnapKit

final class StakingRewardDestSetupLayout: UIView {
    let contentView: ScrollableContainerView = {
        let view = ScrollableContainerView()
        view.stackView.isLayoutMarginsRelativeArrangement = true
        view.stackView.layoutMargins = UIEdgeInsets(top: 16.0, left: 0.0, bottom: 0.0, right: 0.0)
        return view
    }()

    let restakeOptionView = RewardSelectionView()
    let payoutOptionView = RewardSelectionView()
    let accountView = UIFactory.default.createAccountView(for: .selection, filled: false)

    let networkFeeView = UIFactory.default.createNetworkFeeView()
    let actionButton: TriangularedButton = UIFactory.default.createMainActionButton()
    let learnMoreView = UIFactory.default.createNovaLearnMoreView()

    var locale = Locale.current {
        didSet {
            if locale != oldValue {
                applyLocalization()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = R.color.colorBlack()!

        setupLayout()
        applyLocalization()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyLocalization() {
        networkFeeView.locale = locale

        learnMoreView.titleLabel.text = R.string.localizable
            .stakingRewardsLearnMore_2_2_0(preferredLanguages: locale.rLanguages)

        restakeOptionView.titleLabel.text = R.string.localizable
            .stakingRestakeTitle_v2_2_0(preferredLanguages: locale.rLanguages)

        payoutOptionView.titleLabel.text = R.string.localizable
            .stakingPayoutTitle_v2_2_0(preferredLanguages: locale.rLanguages)

        accountView.title = R.string.localizable
            .stakingRewardPayoutAccount(preferredLanguages: locale.rLanguages)

        actionButton.imageWithTitleView?.title = R.string.localizable
            .commonContinue(preferredLanguages: locale.rLanguages)
    }

    private func setupLayout() {
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.top.equalTo(safeAreaLayoutGuide)
            make.bottom.leading.trailing.equalToSuperview()
        }

        contentView.stackView.addArrangedSubview(restakeOptionView)
        restakeOptionView.snp.makeConstraints { make in
            make.width.equalTo(self).offset(-2.0 * UIConstants.horizontalInset)
            make.height.equalTo(52.0)
        }

        contentView.stackView.setCustomSpacing(16.0, after: restakeOptionView)

        contentView.stackView.addArrangedSubview(payoutOptionView)
        payoutOptionView.snp.makeConstraints { make in
            make.width.equalTo(self).offset(-2.0 * UIConstants.horizontalInset)
            make.height.equalTo(52.0)
        }

        contentView.stackView.setCustomSpacing(16.0, after: payoutOptionView)

        contentView.stackView.addArrangedSubview(accountView)
        accountView.snp.makeConstraints { make in
            make.width.equalTo(self).offset(-2.0 * UIConstants.horizontalInset)
            make.height.equalTo(52.0)
        }

        contentView.stackView.setCustomSpacing(16.0, after: payoutOptionView)
        contentView.stackView.setCustomSpacing(16.0, after: accountView)

        contentView.stackView.addArrangedSubview(learnMoreView)
        learnMoreView.snp.makeConstraints { make in
            make.width.equalTo(self)
        }

        contentView.stackView.addArrangedSubview(networkFeeView)
        networkFeeView.snp.makeConstraints { make in
            make.width.equalTo(self).offset(-2.0 * UIConstants.horizontalInset)
        }

        addSubview(actionButton)
        actionButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInset)
            make.bottom.equalTo(safeAreaLayoutGuide).inset(UIConstants.actionBottomInset)
            make.height.equalTo(UIConstants.actionHeight)
        }
    }
}
