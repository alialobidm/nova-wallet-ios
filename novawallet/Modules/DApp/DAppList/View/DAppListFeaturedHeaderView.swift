import UIKit

final class DAppListFeaturedHeaderView: UICollectionViewCell {
    static let preferredHeight: CGFloat = 64.0

    let titleLabel: UILabel = {
        let view = UILabel()
        view.font = .semiBoldTitle3
        view.textColor = R.color.colorWhite()
        return view
    }()

    var locale = Locale.current {
        didSet {
            if oldValue != locale {
                setupLocalization()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupLayout()
        setupLocalization()
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        layoutAttributes.frame.size = CGSize(width: layoutAttributes.frame.width, height: Self.preferredHeight)
        return layoutAttributes
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLocalization() {
        titleLabel.text = R.string.localizable.dappListFeaturedWebsites(
            preferredLanguages: locale.rLanguages
        )
    }

    private func setupLayout() {
        contentView.addSubview(titleLabel)

        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInset)
            make.centerY.equalToSuperview()
        }
    }
}
