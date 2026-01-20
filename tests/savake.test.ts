
import { describe, expect, it } from "vitest";
import {
  Cl,
  ClarityType,
  type ClarityValue,
  type ListCV,
  type ResponseOkCV,
  type SomeCV,
  type TupleCV,
  type UIntCV,
} from "@stacks/transactions";

const contractName = "savake";
const accounts = simnet.getAccounts();
const deployer = simnet.deployer;

const getAccount = (name: string) => {
  const address = accounts.get(name);
  if (!address) {
    throw new Error(`Missing account: ${name}`);
  }
  return address;
};

const wallet1 = getAccount("wallet_1");
const wallet2 = getAccount("wallet_2");
const wallet3 = getAccount("wallet_3");
const wallet4 = getAccount("wallet_4");

const unwrapOk = <T extends ClarityValue>(result: ClarityValue): T => {
  expect(result).toHaveClarityType(ClarityType.ResponseOk);
  return (result as ResponseOkCV).value as T;
};

const unwrapSome = <T extends ClarityValue>(value: ClarityValue): T => {
  expect(value).toHaveClarityType(ClarityType.OptionalSome);
  return (value as SomeCV).value as T;
};

const toBigInt = (value: bigint | number | string): bigint =>
  typeof value === "bigint" ? value : BigInt(value);

const readUintOk = (result: ClarityValue): bigint => {
  const value = unwrapOk<UIntCV>(result);
  expect(value).toHaveClarityType(ClarityType.UInt);
  return toBigInt(value.value);
};

const getUserBalance = (user: string): bigint => {
  const { result } = simnet.callReadOnlyFn(
    contractName,
    "get-user-balance",
    [Cl.principal(user)],
    user,
  );
  return readUintOk(result);
};

const getTokenBalance = (user: string): bigint => {
  const { result } = simnet.callReadOnlyFn(
    contractName,
    "get-balance",
    [Cl.principal(user)],
    user,
  );
  return readUintOk(result);
};

const getUserLock = (user: string): bigint => {
  const { result } = simnet.callReadOnlyFn(
    contractName,
    "get-user-lock",
    [Cl.principal(user)],
    user,
  );
  return readUintOk(result);
};

const getUserPositions = (user: string): bigint[] => {
  const { result } = simnet.callReadOnlyFn(
    contractName,
    "get-user-positions",
    [Cl.principal(user)],
    user,
  );
  const list = unwrapOk<ListCV>(result);
  return list.value.map((item) => toBigInt((item as UIntCV).value));
};

const getContractInfo = (sender = wallet1) => {
  const { result } = simnet.callReadOnlyFn(contractName, "get-contract-info", [], sender);
  return unwrapOk<TupleCV>(result).value;
};

const getContractNumbers = () => {
  const info = getContractInfo();
  return {
    totalStaked: toBigInt((info["total-staked"] as UIntCV).value),
    stakingFee: toBigInt((info["staking-fee"] as UIntCV).value),
    contractStxBalance: toBigInt((info["contract-stx-balance"] as UIntCV).value),
    nextPositionId: toBigInt((info["next-position-id"] as UIntCV).value),
  };
};

const ensureUnpaused = () => {
  simnet.callPublicFn(contractName, "unpause-contract", [], deployer);
};

const calcFee = (amount: bigint, feeRate: bigint) =>
  amount >= 10000n ? (amount * 50n) / 10000n : (amount * feeRate) / 10000n;

const calcTier = (balance: bigint) => {
  if (balance >= 100000n) return 4n;
  if (balance >= 25000n) return 3n;
  if (balance >= 5000n) return 2n;
  if (balance >= 1000n) return 1n;
  return 0n;
};

const tierMultiplier = (tier: bigint) => {
  if (tier === 4n) return 200n;
  if (tier === 3n) return 150n;
  if (tier === 2n) return 125n;
  if (tier === 1n) return 100n;
  return 50n;
};

describe("savake core flows", () => {
  it("stakes STX and mints savake tokens", () => {
    ensureUnpaused();
    const amount = 1000n;
    const infoBefore = getContractNumbers();
    const balanceBefore = getUserBalance(wallet1);
    const fee = calcFee(amount, infoBefore.stakingFee);
    const netAmount = amount - fee;

    const { result } = simnet.callPublicFn(
      contractName,
      "stake",
      [Cl.uint(amount)],
      wallet1,
    );

    expect(result).toBeOk(Cl.uint(netAmount));
    expect(getUserBalance(wallet1)).toBe(balanceBefore + netAmount);

    const infoAfter = getContractNumbers();
    expect(infoAfter.totalStaked).toBe(infoBefore.totalStaked + netAmount);
    expect(infoAfter.contractStxBalance).toBe(infoBefore.contractStxBalance + netAmount);
  });

  it("locks stake-and-bake positions and blocks early unstake", () => {
    ensureUnpaused();
    const amount = 2000n;
    const lockPeriod = 10n;
    const infoBefore = getContractNumbers();
    const fee = calcFee(amount, infoBefore.stakingFee);
    const netAmount = amount - fee;

    const { result } = simnet.callPublicFn(
      contractName,
      "stake-and-bake",
      [Cl.uint(amount), Cl.uint(lockPeriod)],
      wallet2,
    );

    expect(result).toBeOk(Cl.uint(netAmount));
    expect(getUserLock(wallet2)).toBeGreaterThan(0n);

    const { result: unstakeResult } = simnet.callPublicFn(
      contractName,
      "unstake",
      [Cl.uint(netAmount)],
      wallet2,
    );
    expect(unstakeResult).toBeErr(Cl.uint(105));
  });

  it("unstakes and returns balances to the prior state", () => {
    ensureUnpaused();
    const amount = 1200n;
    const infoBefore = getContractNumbers();
    const balanceBefore = getUserBalance(wallet3);
    const fee = calcFee(amount, infoBefore.stakingFee);
    const netAmount = amount - fee;

    const { result: stakeResult } = simnet.callPublicFn(
      contractName,
      "stake",
      [Cl.uint(amount)],
      wallet3,
    );
    expect(stakeResult).toBeOk(Cl.uint(netAmount));

    const { result: unstakeResult } = simnet.callPublicFn(
      contractName,
      "unstake",
      [Cl.uint(netAmount)],
      wallet3,
    );
    expect(unstakeResult).toBeOk(Cl.uint(netAmount));

    const infoAfter = getContractNumbers();
    expect(getUserBalance(wallet3)).toBe(balanceBefore);
    expect(infoAfter.totalStaked).toBe(infoBefore.totalStaked);
    expect(infoAfter.contractStxBalance).toBe(infoBefore.contractStxBalance);
  });

  it("creates staking positions with stored metadata", () => {
    ensureUnpaused();
    const amount = 1500n;
    const lockPeriod = 20n;
    const infoBefore = getContractNumbers();
    const positionsBefore = getUserPositions(wallet1);

    const { result } = simnet.callPublicFn(
      contractName,
      "create-staking-position",
      [Cl.uint(amount), Cl.uint(lockPeriod)],
      wallet1,
    );

    expect(result).toBeOk(Cl.uint(infoBefore.nextPositionId));
    const detailsResult = simnet.callReadOnlyFn(
      contractName,
      "get-position-details",
      [Cl.uint(infoBefore.nextPositionId)],
      wallet1,
    );
    const detailsTuple = unwrapSome<TupleCV>(unwrapOk(detailsResult.result));
    const details = detailsTuple.value;

    const expectedTier = calcTier(amount);
    expect(details.owner).toBePrincipal(wallet1);
    expect(details.amount).toBeUint(amount);
    expect(details["lock-period"]).toBeUint(lockPeriod);
    expect(details.tier).toBeUint(expectedTier);
    expect(details.multiplier).toBeUint(tierMultiplier(expectedTier));
    expect(details["created-at"]).toHaveClarityType(ClarityType.UInt);

    const positionsAfter = getUserPositions(wallet1);
    expect(positionsAfter.length).toBe(positionsBefore.length + 1);
    expect(positionsAfter[positionsAfter.length - 1]).toBe(infoBefore.nextPositionId);
  });

  it("transfers staking position ownership", () => {
    ensureUnpaused();
    const amount = 1100n;
    const lockPeriod = 5n;
    const infoBefore = getContractNumbers();

    const { result: createResult } = simnet.callPublicFn(
      contractName,
      "create-staking-position",
      [Cl.uint(amount), Cl.uint(lockPeriod)],
      wallet2,
    );
    expect(createResult).toBeOk(Cl.uint(infoBefore.nextPositionId));

    const { result: transferResult } = simnet.callPublicFn(
      contractName,
      "transfer-position",
      [Cl.uint(infoBefore.nextPositionId), Cl.principal(wallet3)],
      wallet2,
    );
    expect(transferResult).toBeOk(Cl.bool(true));

    const { result: detailsResult } = simnet.callReadOnlyFn(
      contractName,
      "get-position-details",
      [Cl.uint(infoBefore.nextPositionId)],
      wallet2,
    );
    const detailsTuple = unwrapSome<TupleCV>(unwrapOk(detailsResult));
    expect(detailsTuple.value.owner).toBePrincipal(wallet3);
  });

  it("rewards referrers when staking", () => {
    ensureUnpaused();
    const amount = 1000n;
    const infoBefore = getContractNumbers();
    const fee = calcFee(amount, infoBefore.stakingFee);
    const netAmount = amount - fee;
    const referrerBalanceBefore = getTokenBalance(wallet3);

    const { result: referrerResult } = simnet.callPublicFn(
      contractName,
      "set-referrer",
      [Cl.principal(wallet3)],
      wallet4,
    );
    expect(referrerResult).toBeOk(Cl.bool(true));

    const { result: stakeResult } = simnet.callPublicFn(
      contractName,
      "stake",
      [Cl.uint(amount)],
      wallet4,
    );
    expect(stakeResult).toBeOk(Cl.uint(netAmount));

    const referrerBalanceAfter = getTokenBalance(wallet3);
    expect(referrerBalanceAfter).toBe(referrerBalanceBefore + 10n);

    const { result: referrerLookup } = simnet.callReadOnlyFn(
      contractName,
      "get-user-referrer",
      [Cl.principal(wallet4)],
      wallet4,
    );
    const referrerValue = unwrapOk<ClarityValue>(referrerLookup);
    expect(referrerValue).toHaveClarityType(ClarityType.OptionalSome);
  });

  it("enforces admin-only pause controls", () => {
    const { result: nonOwnerPause } = simnet.callPublicFn(
      contractName,
      "pause-contract",
      [],
      wallet1,
    );
    expect(nonOwnerPause).toBeErr(Cl.uint(100));

    const { result: ownerPause } = simnet.callPublicFn(
      contractName,
      "pause-contract",
      [],
      deployer,
    );
    expect(ownerPause).toBeOk(Cl.bool(true));

    const pausedInfo = getContractInfo();
    expect(pausedInfo["contract-paused"]).toBeBool(true);

    const { result: ownerUnpause } = simnet.callPublicFn(
      contractName,
      "unpause-contract",
      [],
      deployer,
    );
    expect(ownerUnpause).toBeOk(Cl.bool(true));

    const unpausedInfo = getContractInfo();
    expect(unpausedInfo["contract-paused"]).toBeBool(false);
  });
});
