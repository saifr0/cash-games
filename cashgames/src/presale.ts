import {
  FundsWalletUpdated as FundsWalletUpdatedEvent,
  OwnershipTransferStarted as OwnershipTransferStartedEvent,
  OwnershipTransferred as OwnershipTransferredEvent,
  Paused as PausedEvent,
  PresaleWalletUpdated as PresaleWalletUpdatedEvent,
  PriceFeedStalenessUpdated as PriceFeedStalenessUpdatedEvent,
  StablecoinFeedStalenessUpdated as StablecoinFeedStalenessUpdatedEvent,
  TokenPriceUpdated as TokenPriceUpdatedEvent,
  TokensPurchased as TokensPurchasedEvent,
  Unpaused as UnpausedEvent
} from "../generated/Presale/Presale"
import {
  FundsWalletUpdated,
  OwnershipTransferStarted,
  OwnershipTransferred,
  Paused,
  PresaleWalletUpdated,
  PriceFeedStalenessUpdated,
  StablecoinFeedStalenessUpdated,
  TokenPriceUpdated,
  TokensPurchased,
  Unpaused
} from "../generated/schema"

export function handleFundsWalletUpdated(event: FundsWalletUpdatedEvent): void {
  let entity = new FundsWalletUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.oldWallet = event.params.oldWallet
  entity.newWallet = event.params.newWallet

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleOwnershipTransferStarted(
  event: OwnershipTransferStartedEvent
): void {
  let entity = new OwnershipTransferStarted(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.previousOwner = event.params.previousOwner
  entity.newOwner = event.params.newOwner

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleOwnershipTransferred(
  event: OwnershipTransferredEvent
): void {
  let entity = new OwnershipTransferred(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.previousOwner = event.params.previousOwner
  entity.newOwner = event.params.newOwner

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handlePaused(event: PausedEvent): void {
  let entity = new Paused(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.account = event.params.account

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handlePresaleWalletUpdated(
  event: PresaleWalletUpdatedEvent
): void {
  let entity = new PresaleWalletUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.oldWallet = event.params.oldWallet
  entity.newWallet = event.params.newWallet

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handlePriceFeedStalenessUpdated(
  event: PriceFeedStalenessUpdatedEvent
): void {
  let entity = new PriceFeedStalenessUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.oldStaleness = event.params.oldStaleness
  entity.newStaleness = event.params.newStaleness

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleStablecoinFeedStalenessUpdated(
  event: StablecoinFeedStalenessUpdatedEvent
): void {
  let entity = new StablecoinFeedStalenessUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.oldStaleness = event.params.oldStaleness
  entity.newStaleness = event.params.newStaleness

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleTokenPriceUpdated(event: TokenPriceUpdatedEvent): void {
  let entity = new TokenPriceUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.oldPrice = event.params.oldPrice
  entity.newPrice = event.params.newPrice

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleTokensPurchased(event: TokensPurchasedEvent): void {
  let entity = new TokensPurchased(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.buyer = event.params.buyer
  entity.paymentAsset = event.params.paymentAsset
  entity.amountPaid = event.params.amountPaid
  entity.usdValue = event.params.usdValue
  entity.tokensBought = event.params.tokensBought

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleUnpaused(event: UnpausedEvent): void {
  let entity = new Unpaused(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.account = event.params.account

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}
