import Foundation
import SubstrateSdk

protocol WalletRemoteSubscriptionServiceProtocol {
    // swiftlint:disable:next function_parameter_count
    func attachToAccountInfo(
        of accountId: AccountId,
        chainId: ChainModel.Id,
        chainFormat: ChainFormat,
        queue: DispatchQueue?,
        closure: RemoteSubscriptionClosure?,
        subscriptionHandlingFactory: RemoteSubscriptionHandlingFactoryProtocol?
    ) -> UUID?

    func detachFromAccountInfo(
        for subscriptionId: UUID,
        accountId: AccountId,
        chainId: ChainModel.Id,
        queue: DispatchQueue?,
        closure: RemoteSubscriptionClosure?
    )

    // swiftlint:disable:next function_parameter_count
    func attachToAsset(
        of accountId: AccountId,
        assetId: UInt32,
        chainId: ChainModel.Id,
        queue: DispatchQueue?,
        closure: RemoteSubscriptionClosure?,
        subscriptionHandlingFactory: RemoteSubscriptionHandlingFactoryProtocol?
    ) -> UUID?

    // swiftlint:disable:next function_parameter_count
    func detachFromAsset(
        for subscriptionId: UUID,
        accountId: AccountId,
        assetId: UInt32,
        chainId: ChainModel.Id,
        queue: DispatchQueue?,
        closure: RemoteSubscriptionClosure?
    )
}

class WalletRemoteSubscriptionService: RemoteSubscriptionService, WalletRemoteSubscriptionServiceProtocol {
    // swiftlint:disable:next function_parameter_count
    func attachToAccountInfo(
        of accountId: AccountId,
        chainId: ChainModel.Id,
        chainFormat: ChainFormat,
        queue: DispatchQueue?,
        closure: RemoteSubscriptionClosure?,
        subscriptionHandlingFactory: RemoteSubscriptionHandlingFactoryProtocol?
    ) -> UUID? {
        do {
            let storagePath = StorageCodingPath.account
            let localKey = try LocalStorageKeyFactory().createFromStoragePath(
                storagePath,
                accountId: accountId,
                chainId: chainId
            )

            switch chainFormat {
            case .substrate:
                let request = MapSubscriptionRequest(
                    storagePath: storagePath,
                    localKey: localKey
                ) { accountId }

                return attachToSubscription(
                    with: [request],
                    chainId: chainId,
                    cacheKey: localKey,
                    queue: queue,
                    closure: closure,
                    subscriptionHandlingFactory: subscriptionHandlingFactory
                )
            case .ethereum:
                let request = MapSubscriptionRequest(
                    storagePath: storagePath,
                    localKey: localKey
                ) { accountId.map { StringScaleMapper(value: $0) } }

                return attachToSubscription(
                    with: [request],
                    chainId: chainId,
                    cacheKey: localKey,
                    queue: queue,
                    closure: closure,
                    subscriptionHandlingFactory: subscriptionHandlingFactory
                )
            }
        } catch {
            callbackClosureIfProvided(closure, queue: queue, result: .failure(error))
            return nil
        }
    }

    func detachFromAccountInfo(
        for subscriptionId: UUID,
        accountId: AccountId,
        chainId: ChainModel.Id,
        queue: DispatchQueue?,
        closure: RemoteSubscriptionClosure?
    ) {
        do {
            let storagePath = StorageCodingPath.account
            let localKey = try LocalStorageKeyFactory().createFromStoragePath(
                storagePath,
                accountId: accountId,
                chainId: chainId
            )

            detachFromSubscription(localKey, subscriptionId: subscriptionId, queue: queue, closure: closure)
        } catch {
            callbackClosureIfProvided(closure, queue: queue, result: .failure(error))
        }
    }

    // swiftlint:disable:next function_parameter_count
    func attachToAsset(
        of accountId: AccountId,
        assetId: UInt32,
        chainId: ChainModel.Id,
        queue: DispatchQueue?,
        closure: RemoteSubscriptionClosure?,
        subscriptionHandlingFactory: RemoteSubscriptionHandlingFactoryProtocol?
    ) -> UUID? {
        do {
            let storagePath = StorageCodingPath.assetsAccount
            let localKey = try LocalStorageKeyFactory().createFromStoragePath(
                storagePath,
                encodableElements: [assetId, accountId],
                chainId: chainId
            )

            let request = DoubleMapSubscriptionRequest(
                storagePath: storagePath,
                localKey: localKey,
                keyParamClosure: { (assetId, accountId) }
            )

            return attachToSubscription(
                with: [request],
                chainId: chainId,
                cacheKey: localKey,
                queue: queue,
                closure: closure,
                subscriptionHandlingFactory: subscriptionHandlingFactory
            )

        } catch {
            callbackClosureIfProvided(closure, queue: queue, result: .failure(error))

            return nil
        }
    }

    // swiftlint:disable:next function_parameter_count
    func detachFromAsset(
        for subscriptionId: UUID,
        accountId: AccountId,
        assetId: UInt32,
        chainId: ChainModel.Id,
        queue: DispatchQueue?,
        closure: RemoteSubscriptionClosure?
    ) {
        do {
            let storagePath = StorageCodingPath.assetsAccount
            let localKey = try LocalStorageKeyFactory().createFromStoragePath(
                storagePath,
                encodableElements: [assetId, accountId],
                chainId: chainId
            )

            detachFromSubscription(localKey, subscriptionId: subscriptionId, queue: queue, closure: closure)

        } catch {
            callbackClosureIfProvided(closure, queue: queue, result: .failure(error))
        }
    }
}
