import {
  Assets,
  Constr,
  Data,
  fromText,
  Lucid,
  toHex,
  UTxO,
} from "lucid-cardano";

import { sha3 } from "./hash";
import { EmulatorProvider } from "./provider";
import { getContractScripts } from "./script";
import { ADA, Asset } from "./types/asset";
import {
  AuthorizationMethodType,
  OrderAmountType,
  OrderDatum,
  OrderDirection,
  OrderExtraDatumType,
  OrderKillable,
} from "./types/order";
import { PoolBaseFee, PoolDatum } from "./types/pool";
import { TxIn } from "./types/tx";

const DEFAULT_BATCHER_FEE = 2_000000n;
const DEFAULT_DEPOSIT_ADA = 2_000000n;
const DEFAULT_INIT_POOL_ADA = 3_000000n;

const DEFAULT_FEE_DENOMINATOR = 10000n;

function computeLPAssetName(assetA: Asset, assetB: Asset): string {
  const k1 = sha3(assetA.policyId + assetA.tokenName);
  const k2 = sha3(assetB.policyId + assetB.tokenName);
  return sha3(k1 + k2);
}

function calculateAmountOut({
  reserveIn,
  reserveOut,
  amountIn,
  tradingFee,
}: {
  reserveIn: bigint;
  reserveOut: bigint;
  amountIn: bigint;
  tradingFee: bigint;
}): bigint {
  const diff = DEFAULT_FEE_DENOMINATOR - tradingFee;
  const inWithFee = diff * amountIn;
  const numerator = inWithFee * reserveOut;
  const denominator = DEFAULT_FEE_DENOMINATOR * reserveIn + inWithFee;
  return numerator / denominator;
}

function calculateEarnedFeeIn({
  amountIn,
  tradingFee,
  feeSharing,
}: {
  amountIn: bigint;
  tradingFee: bigint;
  feeSharing?: bigint;
}): {
  lpFee: bigint;
  feeShare: bigint;
} {
  const lpFee = (amountIn * tradingFee) / DEFAULT_FEE_DENOMINATOR;
  let feeShare = 0n;
  if (feeSharing) {
    feeShare =
      (amountIn * tradingFee * feeSharing) /
      (DEFAULT_FEE_DENOMINATOR * DEFAULT_FEE_DENOMINATOR);
  }

  return {
    lpFee: lpFee,
    feeShare: feeShare,
  };
}

function calculateSwapExactIn({
  datumReserves,
  valueReserves,
  tradingFee,
  amountIn,
  direction,
  feeSharing,
}: {
  datumReserves: [bigint, bigint];
  valueReserves: [bigint, bigint];
  tradingFee: PoolBaseFee;
  amountIn: bigint;
  direction: OrderDirection;
  feeSharing?: bigint;
}): {
  newDatumReserves: [bigint, bigint];
  newValueReserves: [bigint, bigint];
  amountOut: bigint;
} {
  const [datumReserveA, datumReserveB] = [...datumReserves];
  const [valueReserveA, valueReserveB] = [...valueReserves];
  const [reserveIn, reserveOut, tradingFeeIn] =
    direction === OrderDirection.A_TO_B
      ? [datumReserveA, datumReserveB, tradingFee.feeANumerator]
      : [datumReserveB, datumReserveA, tradingFee.feeBNumerator];
  const amountOut = calculateAmountOut({
    amountIn: amountIn,
    reserveIn: reserveIn,
    reserveOut: reserveOut,
    tradingFee: tradingFeeIn,
  });
  const { feeShare: feeShareIn } = calculateEarnedFeeIn({
    amountIn: amountIn,
    tradingFee: tradingFeeIn,
    feeSharing: feeSharing,
  });
  let newDatumReserveA: bigint;
  let newDatumReserveB: bigint;
  let newValueReserveA: bigint;
  let newValueReserveB: bigint;
  switch (direction) {
    case OrderDirection.A_TO_B: {
      newDatumReserveA = datumReserveA + amountIn - feeShareIn;
      newDatumReserveB = datumReserveB - amountOut;
      newValueReserveA = valueReserveA + amountIn;
      newValueReserveB = valueReserveB - amountOut;
      break;
    }
    case OrderDirection.B_TO_A: {
      newDatumReserveA = datumReserveA - amountOut;
      newDatumReserveB = datumReserveB + amountIn - feeShareIn;
      newValueReserveA = valueReserveA - amountOut;
      newValueReserveB = valueReserveB + amountIn;
      break;
    }
  }
  return {
    newDatumReserves: [newDatumReserveA, newDatumReserveB],
    newValueReserves: [newValueReserveA, newValueReserveB],
    amountOut: amountOut,
  };
}

function calculateOrderIndexes(txIns: TxIn[]): Uint8Array {
  // first, we need to sort order by TxID and TxIndex
  const tempTxIns = [...txIns];
  tempTxIns.sort((a, b) => TxIn.compare(a, b));
  // then, we loop the original orders backwards and add the indexes to resulting array
  const ret: number[] = [];
  for (let i = txIns.length - 1; i >= 0; i--) {
    for (let j = 0; j < tempTxIns.length; j++) {
      if (TxIn.compare(txIns[i], tempTxIns[j]) === 0) {
        ret.push(j);
        break;
      }
    }
  }
  return new Uint8Array(ret.reverse());
}

async function buildBatchTx({
  lucid,
  pool,
  orders,
}: {
  lucid: Lucid;
  pool: {
    poolIn: UTxO;
    poolOut: {
      value: Assets;
      datum: string;
    };
  };
  orders: {
    orderIn: UTxO;
    orderOut: {
      address: string;
      value: Assets;
    };
  }[];
}): Promise<void> {
  const scripts = getContractScripts(lucid);
  const batcherArr =
    "addr_test1vq6wk0m30zgvzdpcut0th2flaj0xv2quwjajjthr8r6t9dcpt0dt5";
  const licenseDate = new Date("2024-02-25T10:00:00.000Z");
  const licenseDeadline = BigInt(
    licenseDate.getTime() + 60 * 24 * 60 * 60 * 1000
  );
  const batcherLicenseAsset: Asset = {
    policyId: scripts.batcherLicensePid,
    tokenName: fromText(licenseDeadline.toString()),
  };
  const licenseUtxo: UTxO = {
    txHash: "37f875a17eee36e6ea4026de97c8b063ae649dd39fd07bce419e6b6e3c993477",
    outputIndex: 0,
    assets: {
      [Asset.toString(ADA)]: 1_000_000_000n,
      [Asset.toString(batcherLicenseAsset)]: 1n,
    },
    address: batcherArr,
  };

  lucid.selectWalletFrom({
    address: batcherArr,
    utxos: [licenseUtxo],
  });

  const inputs: UTxO[] = [
    licenseUtxo,
    pool.poolIn,
    ...orders.map((o) => o.orderIn),
  ].sort((a, b) =>
    TxIn.compare(
      {
        txId: a.txHash,
        index: a.outputIndex,
      },
      {
        txId: b.txHash,
        index: b.outputIndex,
      }
    )
  );

  let licenseIndex = -1;
  for (let i = 0; i < inputs.length; i++) {
    const isLicenseInput =
      inputs[i].txHash === licenseUtxo.txHash &&
      inputs[i].outputIndex === licenseUtxo.outputIndex;
    if (isLicenseInput && licenseIndex === -1) {
      licenseIndex = i;
      continue;
    }
  }

  const inputIndexes = calculateOrderIndexes(
    orders.map(({ orderIn }) => ({
      txId: orderIn.txHash,
      index: orderIn.outputIndex,
    }))
  );

  const poolBatchingRedeemer = new Constr(0, [
    BigInt(licenseIndex),
    orders.map((_) => DEFAULT_BATCHER_FEE),
    toHex(inputIndexes),
    new Constr(1, []),
    [new Constr(1, [])],
  ]);

  const validFrom = new Date();
  const validTo = new Date(validFrom.getTime() + 1000 * 1000);
  const tx = lucid
    .newTx()
    .readFrom([
      scripts.references.poolRef,
      scripts.references.orderRef,
      scripts.references.poolBatchingRef,
    ])
    .collectFrom([pool.poolIn], Data.to(new Constr(0, [])))
    .collectFrom(
      orders.map((o) => o.orderIn),
      Data.to(new Constr(0, []))
    )
    .collectFrom([licenseUtxo])
    .withdraw(scripts.poolBatchingAddress, 0n, Data.to(poolBatchingRedeemer))
    .validFrom(validFrom.getTime())
    .validTo(validTo.getTime())
    .addSigner(batcherArr);

  for (const { orderOut } of orders) {
    tx.payToAddress(orderOut.address, orderOut.value);
  }
  tx.payToContract(
    pool.poolIn.address,
    {
      inline: pool.poolOut.datum,
    },
    pool.poolOut.value
  );

  const txComplete = await tx.complete({
    change: {
      address: batcherArr,
    },
  });

  const txSigned = await txComplete
    .signWithPrivateKey(
      "ed25519_sk1lpsssf9u5qpwraf230jua6d7703ze2ekwl734xqykqu3seszl7aslqde8x"
    )
    .complete();
  const txId = await txSigned.submit();
  console.log(`Submit success: ${txId}`);
}

async function main(): Promise<void> {
  const lucid = await Lucid.new(new EmulatorProvider(), "Preprod");
  const scripts = getContractScripts(lucid);
  const assetA: Asset = ADA;
  const assetB: Asset = {
    policyId: "e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
    tokenName: "4d494e",
  };
  const amountA = 27_877_961_987941n;
  const amountB = 414_804_973_691450n;
  const lpAssetName = computeLPAssetName(assetA, assetB);
  const lpAsset: Asset = {
    policyId: scripts.authenPolicyId,
    tokenName: lpAssetName,
  };
  const totalLiquidity = 106241703280080n;
  const maxLiquidity = 9223372036854775807n;

  const poolDatum: PoolDatum = {
    poolBatchingStakeCredential: scripts.poolBatchingCredential,
    assetA: assetA,
    assetB: assetB,
    totalLiquidity: totalLiquidity,
    reserveA: 27_877_961_987941n,
    reserveB: 414_804_973_691450n,
    feeSharingNumerator: undefined,
    baseFee: {
      feeANumerator: 30n,
      feeBNumerator: 100n,
    },
    allowDynamicFee: false,
  };

  const poolValue: Assets = {
    [Asset.toString(assetA)]: amountA + DEFAULT_INIT_POOL_ADA,
    [Asset.toString(assetB)]: amountB,
    [Asset.toString(lpAsset)]: maxLiquidity - totalLiquidity,
    [Asset.toString(scripts.poolAuthAsset)]: 1n,
  };

  const poolInUtxo: UTxO = {
    txHash: "dcb8585da6a8b47d014e2fc8718d3b6a44bd5f899d02654f611dfc525e74b154",
    outputIndex: 0,
    assets: poolValue,
    address: scripts.poolAddress,
    datum: Data.to(PoolDatum.toPlutus(poolDatum)),
  };

  const testUserAddr =
    "addr_test1vrxhzzazrwa988jumcrtt7kt6gf7rwd4jxzr0kfvxjaqvwqavxh3s";
  const cancellerPubKeyHash =
    "cd710ba21bba539e5cde06b5facbd213e1b9b5918437d92c34ba0638";
  const totalOrderAmount = 2_000_000000n;
  const swapAmount = 1_000_000000n;
  const swapDirection = OrderDirection.A_TO_B;
  const orderDatum: OrderDatum = {
    canceller: {
      type: AuthorizationMethodType.SIGNATURE,
      hash: cancellerPubKeyHash,
    },
    refundReceiver: testUserAddr,
    refundReceiverDatum: {
      type: OrderExtraDatumType.NO_DATUM,
    },
    successReceiver: testUserAddr,
    successReceiverDatum: {
      type: OrderExtraDatumType.NO_DATUM,
    },
    lpAsset: lpAsset,
    maxBatcherFee: DEFAULT_BATCHER_FEE,
    expiredOptions: undefined,
    step: {
      direction: swapDirection,
      swapAmountOption: {
        type: OrderAmountType.SPECIFIC_AMOUNT,
        swapAmount: swapAmount,
      },
      minimumReceived: 1n,
      killable: OrderKillable.PENDING_ON_FAILED,
    },
  };
  const orderValue: Assets = {
    [Asset.toString(ADA)]:
      DEFAULT_BATCHER_FEE + DEFAULT_DEPOSIT_ADA + totalOrderAmount,
  };

  const orders: {
    orderIn: UTxO;
    orderOut: {
      address: string;
      value: Assets;
    };
  }[] = [];

  let tempDatumReserves: [bigint, bigint] = [amountA, amountB];
  let tempValueReserves: [bigint, bigint] = [amountA, amountB];
  for (let i = 0; i < 35; i++) {
    const orderIn: UTxO = {
      txHash:
        "5573777bedba6bb5f56541681256158dcf8ebfbc9e7251277d25b118517dce10",
      outputIndex: i,
      assets: orderValue,
      address: scripts.orderAddress,
      datum: Data.to(OrderDatum.toPlutus(orderDatum)),
    };
    const { amountOut, newDatumReserves, newValueReserves } =
      calculateSwapExactIn({
        datumReserves: tempDatumReserves,
        valueReserves: tempValueReserves,
        tradingFee: poolDatum.baseFee,
        amountIn: swapAmount,
        direction: swapDirection,
        feeSharing: poolDatum.feeSharingNumerator,
      });
    tempDatumReserves = newDatumReserves;
    tempValueReserves = newValueReserves;

    const orderOutValue: Assets = {
      ...orderValue,
    };
    orderOutValue[Asset.toString(ADA)] -= DEFAULT_BATCHER_FEE + swapAmount;
    orderOutValue[Asset.toString(assetB)] =
      (orderOutValue[Asset.toString(assetB)] ?? 0n) + amountOut;
    orders.push({
      orderIn: orderIn,
      orderOut: {
        address: orderDatum.successReceiver,
        value: orderOutValue,
      },
    });
  }

  const newPoolDatum: PoolDatum = {
    ...poolDatum,
    reserveA: tempDatumReserves[0],
    reserveB: tempValueReserves[1],
  };

  const newPoolValue: Assets = {
    ...poolValue,
  };
  newPoolValue[Asset.toString(ADA)] =
    tempDatumReserves[0] + DEFAULT_INIT_POOL_ADA;
  newPoolValue[Asset.toString(assetB)] = tempValueReserves[1];

  await buildBatchTx({
    lucid: lucid,
    pool: {
      poolIn: poolInUtxo,
      poolOut: {
        value: newPoolValue,
        datum: Data.to(PoolDatum.toPlutus(newPoolDatum)),
      },
    },
    orders: orders,
  });
}

void main();
