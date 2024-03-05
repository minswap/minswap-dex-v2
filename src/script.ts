import fs from "fs";
import {
  applyParamsToScript,
  Constr,
  Credential,
  fromHex,
  fromText,
  Lucid,
  MintingPolicy,
  Script,
  SpendingValidator,
  UTxO,
  WithdrawalValidator,
} from "lucid-cardano";

import { Asset } from "./types/asset";
import { TxIn } from "./types/tx";

type PlutusValidatorCompiled = {
  title: string;
  compiledCode: string;
};
type PlutusCompiled = {
  validators: PlutusValidatorCompiled[];
};

function getInitialParameters(): {
  seedTxIn: TxIn;
  batcherLicensePid: string;
  adminLicensePid: string;
  factoryNFTName: string;
  poolNFTName: string;
  adminNFTName: string;
} {
  return {
    seedTxIn: {
      txId: "2cc240daa819b2ec18a9fc9a8c86c6f2145328a64debd14ead32c589a6bfb22d",
      index: 1,
    },
    batcherLicensePid:
      "229013ad3a22d2d051a28e7f9214a32444ecf19998f7bdf0c2849862",
    adminLicensePid: "229013ad3a22d2d051a28e7f9214a32444ecf19998f7bdf0c2849862",
    factoryNFTName: "MS",
    poolNFTName: "MSP",
    adminNFTName: "MSA",
  };
}

function readValidator(): {
  order: SpendingValidator;
  expiredOrderCancellation: WithdrawalValidator;
  pool: SpendingValidator;
  poolBatching: WithdrawalValidator;
  authen: MintingPolicy;
  factory: SpendingValidator;
} {
  const file = fs.readFileSync("plutus.json", "utf-8");
  const plutusCompiled: PlutusCompiled = JSON.parse(file);
  const orderValidatorComplied = plutusCompiled.validators.find(
    (v) => v.title === "order_validator.validate_order"
  );
  const expiredOrderCancelValidatorComplied = plutusCompiled.validators.find(
    (v) => v.title === "order_validator.validate_expired_order_cancel"
  );
  const poolValidatorComplied = plutusCompiled.validators.find(
    (v) => v.title === "pool_validator.validate_pool"
  );
  const authenMintingComplied = plutusCompiled.validators.find(
    (v) => v.title === "authen_minting_policy.validate_authen"
  );
  const factoryScriptComplied = plutusCompiled.validators.find(
    (v) => v.title === "factory_validator.validate_factory"
  );
  const poolBatchingValidatorComplied = plutusCompiled.validators.find(
    (v) => v.title === "pool_validator.validate_pool_batching"
  );
  if (
    !orderValidatorComplied ||
    !expiredOrderCancelValidatorComplied ||
    !poolValidatorComplied ||
    !poolBatchingValidatorComplied ||
    !authenMintingComplied ||
    !factoryScriptComplied
  ) {
    throw Error("Validator not found");
  }

  return {
    order: {
      type: "PlutusV2",
      script: orderValidatorComplied.compiledCode,
    },
    expiredOrderCancellation: {
      type: "PlutusV2",
      script: expiredOrderCancelValidatorComplied.compiledCode,
    },
    pool: {
      type: "PlutusV2",
      script: poolValidatorComplied.compiledCode,
    },
    poolBatching: {
      type: "PlutusV2",
      script: poolBatchingValidatorComplied.compiledCode,
    },
    authen: {
      type: "PlutusV2",
      script: authenMintingComplied.compiledCode,
    },
    factory: {
      type: "PlutusV2",
      script: factoryScriptComplied.compiledCode,
    },
  };
}

export function getContractScripts(lucid: Lucid): {
  authenPolicyId: string;
  poolAddress: string;
  orderAddress: string;
  factoryAddress: string;
  expiredOrderCancellationAddress: string;
  poolBatchingAddress: string;
  poolBatchingCredential: Credential;
  poolAuthAsset: Asset;
  factoryAuthAsset: Asset;
  batcherLicensePid: string;
  references: {
    poolRef: UTxO;
    orderRef: UTxO;
    lpRef: UTxO;
    factoryRef: UTxO;
    expiredOrderCancelRef: UTxO;
    poolBatchingRef: UTxO;
  };
} {
  const validators = readValidator();
  const initialParameters = getInitialParameters();
  const authenMintingScript: Script = {
    type: "PlutusV2",
    script: applyParamsToScript(validators.authen.script, [
      TxIn.toPlutus(initialParameters.seedTxIn),
    ]),
  };
  const authenPolicyId = lucid.utils.mintingPolicyToId(authenMintingScript);
  const poolScript: Script = {
    type: "PlutusV2",
    script: applyParamsToScript(validators.pool.script, [authenPolicyId]),
  };
  const poolHash = lucid.utils.validatorToScriptHash(poolScript);
  const poolBatchingScript: Script = {
    type: "PlutusV2",
    script: applyParamsToScript(validators.poolBatching.script, [
      authenPolicyId,
      new Constr(1, [poolHash]),
    ]),
  };
  const poolBatchingHash =
    lucid.utils.validatorToScriptHash(poolBatchingScript);
  const poolBatchingStakeCredential = new Constr(0, [
    new Constr(1, [poolBatchingHash]),
  ]);

  const expiredOrderCancellationScript: Script = {
    type: "PlutusV2",
    script: applyParamsToScript(validators.expiredOrderCancellation.script, []),
  };
  const expiredOrderCancellationHash = lucid.utils.validatorToScriptHash(
    expiredOrderCancellationScript
  );
  const expiredOrderCancellationStakeCredential = new Constr(0, [
    new Constr(1, [expiredOrderCancellationHash]),
  ]);

  const orderScript: Script = {
    type: "PlutusV2",
    script: applyParamsToScript(validators.order.script, [
      poolBatchingStakeCredential,
      expiredOrderCancellationStakeCredential,
    ]),
  };

  const factoryScript: Script = {
    type: "PlutusV2",
    script: applyParamsToScript(validators.factory.script, [
      authenPolicyId,
      poolHash,
      poolBatchingStakeCredential,
    ]),
  };

  const poolAddress = lucid.utils.validatorToAddress(poolScript);
  const orderAddress = lucid.utils.validatorToAddress(orderScript);
  const factoryAddress = lucid.utils.validatorToAddress(factoryScript);
  const expiredOrderCancellationAddress = lucid.utils.validatorToRewardAddress(
    expiredOrderCancellationScript
  );
  const poolBatchingAddress =
    lucid.utils.validatorToRewardAddress(poolBatchingScript);

  const referencesAddr =
    "addr_test1vzztre5epvtj5p72sh28nvrs3e6s4xxn95f66cvg0sqsk7qd3mah0";
  const testReferenceTxHash =
    "eb5d5d3cf842b171b09a1878fc8c16cf7a5ad6a0d18e3122feb31078e224680a";

  const authenSize = fromHex(authenMintingScript.script).length;
  const orderSize = fromHex(orderScript.script).length;
  const poolSize = fromHex(poolScript.script).length;
  const factorySize = fromHex(factoryScript.script).length;
  const expiredOrderSize = fromHex(
    expiredOrderCancellationScript.script
  ).length;
  const poolBatchingSize = fromHex(poolBatchingScript.script).length;

  console.log(`
    - Authen size: ${authenSize} bytes
    - Order size: ${orderSize} bytes
    - Pool size: ${poolSize} bytes
    - Factory size: ${factorySize} bytes
    - Expired Order Cancel size: ${expiredOrderSize} bytes
    - Pool batching size: ${poolBatchingSize} bytes
  `);
  return {
    authenPolicyId,
    orderAddress,
    poolAddress,
    factoryAddress,
    expiredOrderCancellationAddress,
    poolBatchingAddress,
    poolBatchingCredential: {
      type: "Script",
      hash: poolBatchingHash,
    },
    poolAuthAsset: {
      policyId: authenPolicyId,
      tokenName: fromText(initialParameters.poolNFTName),
    },
    factoryAuthAsset: {
      policyId: authenPolicyId,
      tokenName: fromText(initialParameters.factoryNFTName),
    },
    batcherLicensePid: initialParameters.batcherLicensePid,
    references: {
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
        scriptRef: authenMintingScript,
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
        scriptRef: expiredOrderCancellationScript,
        assets: {},
      },
      poolBatchingRef: {
        txHash: testReferenceTxHash,
        outputIndex: 6,
        address: referencesAddr,
        scriptRef: poolBatchingScript,
        assets: {},
      },
    },
  };
}
