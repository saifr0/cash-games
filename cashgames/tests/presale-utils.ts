import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt } from "@graphprotocol/graph-ts"
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
} from "../generated/Presale/Presale"

export function createFundsWalletUpdatedEvent(
  oldWallet: Address,
  newWallet: Address
): FundsWalletUpdated {
  let fundsWalletUpdatedEvent = changetype<FundsWalletUpdated>(newMockEvent())

  fundsWalletUpdatedEvent.parameters = new Array()

  fundsWalletUpdatedEvent.parameters.push(
    new ethereum.EventParam("oldWallet", ethereum.Value.fromAddress(oldWallet))
  )
  fundsWalletUpdatedEvent.parameters.push(
    new ethereum.EventParam("newWallet", ethereum.Value.fromAddress(newWallet))
  )

  return fundsWalletUpdatedEvent
}

export function createOwnershipTransferStartedEvent(
  previousOwner: Address,
  newOwner: Address
): OwnershipTransferStarted {
  let ownershipTransferStartedEvent =
    changetype<OwnershipTransferStarted>(newMockEvent())

  ownershipTransferStartedEvent.parameters = new Array()

  ownershipTransferStartedEvent.parameters.push(
    new ethereum.EventParam(
      "previousOwner",
      ethereum.Value.fromAddress(previousOwner)
    )
  )
  ownershipTransferStartedEvent.parameters.push(
    new ethereum.EventParam("newOwner", ethereum.Value.fromAddress(newOwner))
  )

  return ownershipTransferStartedEvent
}

export function createOwnershipTransferredEvent(
  previousOwner: Address,
  newOwner: Address
): OwnershipTransferred {
  let ownershipTransferredEvent =
    changetype<OwnershipTransferred>(newMockEvent())

  ownershipTransferredEvent.parameters = new Array()

  ownershipTransferredEvent.parameters.push(
    new ethereum.EventParam(
      "previousOwner",
      ethereum.Value.fromAddress(previousOwner)
    )
  )
  ownershipTransferredEvent.parameters.push(
    new ethereum.EventParam("newOwner", ethereum.Value.fromAddress(newOwner))
  )

  return ownershipTransferredEvent
}

export function createPausedEvent(account: Address): Paused {
  let pausedEvent = changetype<Paused>(newMockEvent())

  pausedEvent.parameters = new Array()

  pausedEvent.parameters.push(
    new ethereum.EventParam("account", ethereum.Value.fromAddress(account))
  )

  return pausedEvent
}

export function createPresaleWalletUpdatedEvent(
  oldWallet: Address,
  newWallet: Address
): PresaleWalletUpdated {
  let presaleWalletUpdatedEvent =
    changetype<PresaleWalletUpdated>(newMockEvent())

  presaleWalletUpdatedEvent.parameters = new Array()

  presaleWalletUpdatedEvent.parameters.push(
    new ethereum.EventParam("oldWallet", ethereum.Value.fromAddress(oldWallet))
  )
  presaleWalletUpdatedEvent.parameters.push(
    new ethereum.EventParam("newWallet", ethereum.Value.fromAddress(newWallet))
  )

  return presaleWalletUpdatedEvent
}

export function createPriceFeedStalenessUpdatedEvent(
  oldStaleness: BigInt,
  newStaleness: BigInt
): PriceFeedStalenessUpdated {
  let priceFeedStalenessUpdatedEvent =
    changetype<PriceFeedStalenessUpdated>(newMockEvent())

  priceFeedStalenessUpdatedEvent.parameters = new Array()

  priceFeedStalenessUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "oldStaleness",
      ethereum.Value.fromUnsignedBigInt(oldStaleness)
    )
  )
  priceFeedStalenessUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "newStaleness",
      ethereum.Value.fromUnsignedBigInt(newStaleness)
    )
  )

  return priceFeedStalenessUpdatedEvent
}

export function createStablecoinFeedStalenessUpdatedEvent(
  oldStaleness: BigInt,
  newStaleness: BigInt
): StablecoinFeedStalenessUpdated {
  let stablecoinFeedStalenessUpdatedEvent =
    changetype<StablecoinFeedStalenessUpdated>(newMockEvent())

  stablecoinFeedStalenessUpdatedEvent.parameters = new Array()

  stablecoinFeedStalenessUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "oldStaleness",
      ethereum.Value.fromUnsignedBigInt(oldStaleness)
    )
  )
  stablecoinFeedStalenessUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "newStaleness",
      ethereum.Value.fromUnsignedBigInt(newStaleness)
    )
  )

  return stablecoinFeedStalenessUpdatedEvent
}

export function createTokenPriceUpdatedEvent(
  oldPrice: BigInt,
  newPrice: BigInt
): TokenPriceUpdated {
  let tokenPriceUpdatedEvent = changetype<TokenPriceUpdated>(newMockEvent())

  tokenPriceUpdatedEvent.parameters = new Array()

  tokenPriceUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "oldPrice",
      ethereum.Value.fromUnsignedBigInt(oldPrice)
    )
  )
  tokenPriceUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "newPrice",
      ethereum.Value.fromUnsignedBigInt(newPrice)
    )
  )

  return tokenPriceUpdatedEvent
}

export function createTokensPurchasedEvent(
  buyer: Address,
  paymentAsset: Address,
  amountPaid: BigInt,
  usdValue: BigInt,
  tokensBought: BigInt
): TokensPurchased {
  let tokensPurchasedEvent = changetype<TokensPurchased>(newMockEvent())

  tokensPurchasedEvent.parameters = new Array()

  tokensPurchasedEvent.parameters.push(
    new ethereum.EventParam("buyer", ethereum.Value.fromAddress(buyer))
  )
  tokensPurchasedEvent.parameters.push(
    new ethereum.EventParam(
      "paymentAsset",
      ethereum.Value.fromAddress(paymentAsset)
    )
  )
  tokensPurchasedEvent.parameters.push(
    new ethereum.EventParam(
      "amountPaid",
      ethereum.Value.fromUnsignedBigInt(amountPaid)
    )
  )
  tokensPurchasedEvent.parameters.push(
    new ethereum.EventParam(
      "usdValue",
      ethereum.Value.fromUnsignedBigInt(usdValue)
    )
  )
  tokensPurchasedEvent.parameters.push(
    new ethereum.EventParam(
      "tokensBought",
      ethereum.Value.fromUnsignedBigInt(tokensBought)
    )
  )

  return tokensPurchasedEvent
}

export function createUnpausedEvent(account: Address): Unpaused {
  let unpausedEvent = changetype<Unpaused>(newMockEvent())

  unpausedEvent.parameters = new Array()

  unpausedEvent.parameters.push(
    new ethereum.EventParam("account", ethereum.Value.fromAddress(account))
  )

  return unpausedEvent
}
