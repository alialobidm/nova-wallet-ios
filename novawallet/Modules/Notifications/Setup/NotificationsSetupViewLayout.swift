import UIKit
import SoraUI

final class NotificationsSetupViewLayout: UIView {
    let titleImage: UIImageView = .create {
        $0.image = R.image.iconNotiifcationRing()
    }

    let titleLabel: UILabel = .create {
        $0.apply(style: .boldTitle2Primary)
        $0.textAlignment = .center
    }

    let subtitleLabel: UILabel = .create {
        $0.apply(style: .footnoteSecondary)
        $0.numberOfLines = 0
        $0.textAlignment = .center
    }

    let notifications = NotificationsView()

    let enableButton: TriangularedButton = .create {
        $0.applyDefaultStyle()
    }

    let notNowButton: TriangularedButton = .create {
        $0.applySecondaryDefaultStyle()
    }

    let termsLabel: UILabel = .create {
        $0.isUserInteractionEnabled = true
        $0.numberOfLines = 0
        $0.textAlignment = .center
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        addSubview(titleImage)
        titleImage.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(safeAreaLayoutGuide).offset(16)
            make.height.width.equalTo(88)
        }
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleImage.snp.bottom).offset(16)
            make.leading.trailing.equalTo(safeAreaLayoutGuide).inset(16)
        }
        addSubview(subtitleLabel)
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.equalTo(safeAreaLayoutGuide).inset(16)
        }
        addSubview(notifications)
        notifications.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(40)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        addSubview(termsLabel)
        termsLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalTo(safeAreaLayoutGuide).offset(-8)
        }

        addSubview(notNowButton)
        notNowButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(termsLabel.snp.top).offset(-16)
            make.height.equalTo(UIConstants.actionHeight)
        }

        addSubview(enableButton)
        enableButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(notNowButton.snp.top).offset(-16)
            make.height.equalTo(UIConstants.actionHeight)
        }
    }
}
