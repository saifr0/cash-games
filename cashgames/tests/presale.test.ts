import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { Address, BigInt } from "@graphprotocol/graph-ts"
import { FundsWalletUpdated } from "../generated/schema"
import { FundsWalletUpdated as FundsWalletUpdatedEvent } from "../generated/Presale/Presale"
import { handleFundsWalletUpdated } from "../src/presale"
import { createFundsWalletUpdatedEvent } from "./presale-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let oldWallet = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let newWallet = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let newFundsWalletUpdatedEvent = createFundsWalletUpdatedEvent(
      oldWallet,
      newWallet
    )
    handleFundsWalletUpdated(newFundsWalletUpdatedEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("FundsWalletUpdated created and stored", () => {
    assert.entityCount("FundsWalletUpdated", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "FundsWalletUpdated",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "oldWallet",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals(
      "FundsWalletUpdated",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "newWallet",
      "0x0000000000000000000000000000000000000001"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
