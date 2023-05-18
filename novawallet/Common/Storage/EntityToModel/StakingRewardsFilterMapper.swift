import Foundation
import RobinHood
import CoreData
import BigInt

final class StakingRewardsFilterMapper {
    var entityIdentifierFieldName: String { #keyPath(CDStakingRewardsFilter.identifier) }

    typealias DataProviderModel = StakingRewardsFilter
    typealias CoreDataEntity = CDStakingRewardsFilter
}

extension StakingRewardsFilterMapper: CoreDataMapperProtocol {
    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.chainAccountId = model.chainAccountId.toHex()
        entity.chainId = model.chainAssetId.chainId
        entity.assetId = Int32(bitPattern: model.chainAssetId.assetId)
        entity.stakingType = model.stakingType.rawValue
        entity.period = try JSONEncoder().encode(model.period)
    }

    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        let chainAccountId = try Data(hexString: entity.chainAccountId!)
        let chainId = entity.chainId
        let chainAssetId = ChainAssetId(
            chainId: entity.chainId!,
            assetId: UInt32(bitPattern: entity.assetId)
        )
        return .init(
            chainAccountId: chainAccountId,
            chainAssetId: chainAssetId,
            stakingType: StakingType(rawType: entity.stakingType),
            period: try JSONDecoder().decode(StakingRewardFiltersPeriod.self, from: entity.period!)
        )
    }
}
