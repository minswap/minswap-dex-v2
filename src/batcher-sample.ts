import {
  Assets,
  Constr,
  Data,
  Lucid,
  Script,
  toHex,
  UTxO,
} from "lucid-cardano";

import { sha3 } from "./hash";
import { EmulatorProvider } from "./provider";
import { getContractScripts } from "./script";
import { ADA, Asset } from "./types/asset";
import {
  GlobalSetting,
  PoolAuthorizationMethodType,
} from "./types/global-setting";
import { NetworkId } from "./types/network";
import {
  OrderAmountType,
  OrderAuthorizationMethodType,
  OrderDatum,
  OrderDirection,
  OrderExtraDatumType,
  OrderKillable,
} from "./types/order";
import { PoolBaseFee, PoolDatum } from "./types/pool";
import { TxIn } from "./types/tx";

const DEFAULT_BATCHER_FEE = 2_000000n;
const DEFAULT_DEPOSIT_ADA = 2_000000n;
const DEFAULT_INIT_POOL_ADA = 4_500000n;

const DEFAULT_FEE_DENOMINATOR = 10000n;
const DEFAULT_NETWORK_ID = NetworkId.TESTNET;

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

type ContractReferences = {
  poolRef: UTxO;
  orderRef: UTxO;
  lpRef: UTxO;
  factoryRef: UTxO;
  expiredOrderCancelRef: UTxO;
  poolBatchingRef: UTxO;
};

function getDummyContractReferences(lucid: Lucid): ContractReferences {
  const referencesAddr =
    "addr_test1vzztre5epvtj5p72sh28nvrs3e6s4xxn95f66cvg0sqsk7qd3mah0";
  const testReferenceTxHash =
    "eb5d5d3cf842b171b09a1878fc8c16cf7a5ad6a0d18e3122feb31078e224680a";
  const {
    poolScript,
    orderScript,
    authenScript,
    factoryScript,
    expiredOrderCancelScript,
    poolBatchingScript,
  } = getContractScripts(lucid, DEFAULT_NETWORK_ID);

  return {
    poolRef: {
      txHash: testReferenceTxHash,
      outputIndex: 1,
      address: referencesAddr,
      scriptRef: poolScript,
      assets: {},
    },
    orderRef: {
      txHash: testReferenceTxHash,
      outputIndex: 2,
      address: referencesAddr,
      scriptRef: orderScript,
      assets: {},
    },
    lpRef: {
      txHash: testReferenceTxHash,
      outputIndex: 3,
      address: referencesAddr,
      scriptRef: authenScript,
      assets: {},
    },
    factoryRef: {
      txHash: testReferenceTxHash,
      outputIndex: 4,
      address: referencesAddr,
      scriptRef: factoryScript,
      assets: {},
    },
    expiredOrderCancelRef: {
      txHash: testReferenceTxHash,
      outputIndex: 5,
      address: referencesAddr,
      scriptRef: expiredOrderCancelScript,
      assets: {},
    },
    poolBatchingRef: {
      txHash: testReferenceTxHash,
      outputIndex: 6,
      address: referencesAddr,
      scriptRef: poolBatchingScript,
      assets: {},
    },
  };
}

function getGlobalSetting(lucid: Lucid): {
  globalSetting: GlobalSetting;
  globalSettingUtxo: UTxO;
} {
  const script = getContractScripts(lucid, DEFAULT_NETWORK_ID);
  const pubkeyBatcher = getPubKeyBatcher();
  const scriptBatcher = getScriptBatcher(lucid);
  const globalSetting: GlobalSetting = {
    batchers: [
      {
        type: PoolAuthorizationMethodType.SIGNATURE,
        hash: lucid.utils.paymentCredentialOf(pubkeyBatcher.batcherAddr).hash,
      },
      {
        type: PoolAuthorizationMethodType.SPEND_SCRIPT,
        hash: lucid.utils.paymentCredentialOf(scriptBatcher.batcherAddr).hash,
      },
    ],
    admin: {
      type: PoolAuthorizationMethodType.SIGNATURE,
      hash: lucid.utils.paymentCredentialOf(
        "addr_test1vqe2eyupqj8e0jr8uumakm2zuhh2ucrcevy7hw8vztjaragvljjnc"
      ).hash,
    },
    feeSharingTaker: {
      type: PoolAuthorizationMethodType.SIGNATURE,
      hash: lucid.utils.paymentCredentialOf(
        "addr_test1vqe2eyupqj8e0jr8uumakm2zuhh2ucrcevy7hw8vztjaragvljjnc"
      ).hash,
    },
    poolDynamicFeeUpdater: {
      type: PoolAuthorizationMethodType.SIGNATURE,
      hash: lucid.utils.paymentCredentialOf(
        "addr_test1vqe2eyupqj8e0jr8uumakm2zuhh2ucrcevy7hw8vztjaragvljjnc"
      ).hash,
    },
    poolFeeUpdater: {
      type: PoolAuthorizationMethodType.SIGNATURE,
      hash: lucid.utils.paymentCredentialOf(
        "addr_test1vqe2eyupqj8e0jr8uumakm2zuhh2ucrcevy7hw8vztjaragvljjnc"
      ).hash,
    },
    poolStakeKeyUpdater: {
      type: PoolAuthorizationMethodType.SIGNATURE,
      hash: lucid.utils.paymentCredentialOf(
        "addr_test1vqe2eyupqj8e0jr8uumakm2zuhh2ucrcevy7hw8vztjaragvljjnc"
      ).hash,
    },
  };
  return {
    globalSetting: globalSetting,
    globalSettingUtxo: {
      txHash:
        "eb5d5d3cf842b171b09a1878fc8c16cf7a5ad6a0d18e3122feb31078e224680a",
      outputIndex: 20,
      assets: {
        [Asset.toString(ADA)]: 1_000_000_000n,
        [Asset.toString(script.globalSettingAsset)]: 1n,
      },
      address: script.authenAddress,
      datum: Data.to(GlobalSetting.toPlutus(globalSetting)),
    },
  };
}

function getPubKeyBatcher(): {
  batcherAddr: string;
  licenseUtxo: UTxO;
  skey: string;
} {
  const batcherAddr =
    "addr_test1vq6wk0m30zgvzdpcut0th2flaj0xv2quwjajjthr8r6t9dcpt0dt5";
  return {
    batcherAddr: batcherAddr,
    licenseUtxo: {
      txHash:
        "37f875a17eee36e6ea4026de97c8b063ae649dd39fd07bce419e6b6e3c993477",
      outputIndex: 0,
      assets: {
        [Asset.toString(ADA)]: 1_000_000_000n,
      },
      address: batcherAddr,
    },
    skey: "ed25519_sk1lpsssf9u5qpwraf230jua6d7703ze2ekwl734xqykqu3seszl7aslqde8x",
  };
}

function getScriptBatcher(lucid: Lucid): {
  batcherAddr: string;
  batcherRef: UTxO;
  licenseUtxo: UTxO;
  collateral: UTxO;
  collateralSkey: string;
} {
  const batcherScript: Script = {
    type: "PlutusV2",
    script:
      "583c0100003232323232222533300432323253330073370e900118041baa00114a22c60120026012002600c6ea8004526136565734aae7555cf2ba157441",
  };
  const batcherAddr = lucid.utils.validatorToAddress(batcherScript);
  const batcherRef: UTxO = {
    txHash: "eb5d5d3cf842b171b09a1878fc8c16cf7a5ad6a0d18e3122feb31078e224680a",
    outputIndex: 10,
    address: "addr_test1vzztre5epvtj5p72sh28nvrs3e6s4xxn95f66cvg0sqsk7qd3mah0",
    scriptRef: batcherScript,
    assets: {},
  };
  return {
    batcherAddr: batcherAddr,
    batcherRef: batcherRef,
    licenseUtxo: {
      txHash:
        "37f875a17eee36e6ea4026de97c8b063ae649dd39fd07bce419e6b6e3c993477",
      outputIndex: 0,
      assets: {
        [Asset.toString(ADA)]: 1_000_000_000n,
      },
      address: batcherAddr,
      datum: Data.to(new Constr(0, [])),
    },
    collateral: {
      txHash:
        "eb5d5d3cf842b171b09a1878fc8c16cf7a5ad6a0d18e3122feb31078e224680a",
      outputIndex: 99,
      assets: {
        [Asset.toString(ADA)]: 5_000000n,
      },
      address:
        "addr_test1qqanmx3m8uchn2649eccsu2y3ztgkkr5rqtuznahyc2v5cwqe09wdp3al4rg9psrd43vptvavmaavsv5feldkgmyzjjq87yath",
    },
    collateralSkey:
      "ed25519_sk1cx0k7z6axzggg08d2e870cgpklawa9ppw39s7dny84allq8fltyqmfsvpw",
  };
}

async function buildTxByPubKeyBatcher({
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
  const scripts = getContractScripts(lucid, DEFAULT_NETWORK_ID);
  const referenceScripts = getDummyContractReferences(lucid);
  const globalSetting = getGlobalSetting(lucid);
  const { batcherAddr, licenseUtxo, skey } = getPubKeyBatcher();

  lucid.selectWalletFrom({
    address: batcherAddr,
    utxos: [licenseUtxo],
  });

  const inputIndexes = calculateOrderIndexes(
    orders.map(({ orderIn }) => ({
      txId: orderIn.txHash,
      index: orderIn.outputIndex,
    }))
  );

  const poolBatchingRedeemer = new Constr(0, [
    0n,
    orders.map((_) => DEFAULT_BATCHER_FEE),
    toHex(inputIndexes),
    new Constr(1, []),
    [new Constr(1, [])],
  ]);

  const validFrom = new Date();
  const validTo = new Date(validFrom.getTime() + 10 * 60 * 1000);
  const tx = lucid
    .newTx()
    .readFrom([
      globalSetting.globalSettingUtxo,
      referenceScripts.poolRef,
      referenceScripts.orderRef,
      referenceScripts.poolBatchingRef,
    ])
    .collectFrom([pool.poolIn], Data.to(new Constr(0, [])))
    .collectFrom(
      orders.map((o) => o.orderIn),
      Data.to(new Constr(0, []))
    )
    .withdraw(scripts.poolBatchingAddress, 0n, Data.to(poolBatchingRedeemer))
    .validFrom(validFrom.getTime())
    .validTo(validTo.getTime())
    .addSigner(batcherAddr);

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
      address: batcherAddr,
    },
  });

  const txSigned = await txComplete.signWithPrivateKey(skey).complete();
  const txId = await txSigned.submit();
  console.log(`Submit success by pub key batcher: ${txId}`);
}

async function buildTxByScriptBatcher({
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
  const scripts = getContractScripts(lucid, DEFAULT_NETWORK_ID);
  const referenceScripts = getDummyContractReferences(lucid);
  const globalSetting = getGlobalSetting(lucid);
  const { batcherAddr, licenseUtxo, batcherRef, collateral, collateralSkey } =
    getScriptBatcher(lucid);

  lucid.selectWalletFrom({
    address: collateral.address,
    utxos: [collateral],
  });

  const inputIndexes = calculateOrderIndexes(
    orders.map(({ orderIn }) => ({
      txId: orderIn.txHash,
      index: orderIn.outputIndex,
    }))
  );

  const poolBatchingRedeemer = new Constr(0, [
    1n,
    orders.map((_) => DEFAULT_BATCHER_FEE),
    toHex(inputIndexes),
    new Constr(1, []),
    [new Constr(1, [])],
  ]);

  const validFrom = new Date();
  const validTo = new Date(validFrom.getTime() + 10 * 60 * 1000);
  const tx = lucid
    .newTx()
    .readFrom([
      globalSetting.globalSettingUtxo,
      batcherRef,
      referenceScripts.poolRef,
      referenceScripts.orderRef,
      referenceScripts.poolBatchingRef,
    ])
    .collectFrom([pool.poolIn], Data.to(new Constr(0, [])))
    .collectFrom(
      orders.map((o) => o.orderIn),
      Data.to(new Constr(0, []))
    )
    .collectFrom([licenseUtxo], Data.to(new Constr(0, [])))
    .withdraw(scripts.poolBatchingAddress, 0n, Data.to(poolBatchingRedeemer))
    .validFrom(validFrom.getTime())
    .validTo(validTo.getTime());

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
      address: batcherAddr,
      outputData: {
        inline: Data.to(new Constr(0, [])),
      },
    },
    coinSelection: false,
  });

  const txSigned = await txComplete
    .signWithPrivateKey(collateralSkey)
    .complete();
  const txId = await txSigned.submit();
  console.log(`Submit success by script batcher: ${txId}`);
}

async function main(): Promise<void> {
  const lucid = await Lucid.new(new EmulatorProvider(), "Preprod");
  const scripts = getContractScripts(lucid, DEFAULT_NETWORK_ID);
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
      type: OrderAuthorizationMethodType.SIGNATURE,
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
  for (let i = 0; i < 38; i++) {
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

  await buildTxByPubKeyBatcher({
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
  await buildTxByScriptBatcher({
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
