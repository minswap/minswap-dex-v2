import fs from "fs";
import {
  applyParamsToScript,
  Constr,
  Credential,
  fromText,
  Lucid,
  MintingPolicy,
  Script,
  SpendingValidator,
  WithdrawalValidator,
} from "lucid-cardano";

import { AddressPlutusData } from "./types/address";
import { Asset } from "./types/asset";
import { NetworkId } from "./types/network";
import { TxIn } from "./types/tx";

type PlutusValidatorCompiled = {
  title: string;
  compiledCode: string;
};
type PlutusCompiled = {
  validators: PlutusValidatorCompiled[];
};

type ContractParameters = {
  seedTxIn: TxIn;
  factoryNFTName: string;
  poolNFTName: string;
  globalSettingNFTName: string;
  poolDefaultStakeKey: Credential;
};

export function getContractParameters(
  networkId: NetworkId
): ContractParameters {
  const cases: Record<string, string> = {
    [NetworkId.TESTNET]: "deployed/preprod/params.json",
    [NetworkId.MAINNET]: "deployed/mainnet/params.json",
  };
  const path = cases[networkId];
  const params = JSON.parse(fs.readFileSync(path, "utf-8"));
  const seedTxInParts = params.seedTxIn.split("#");
  return {
    seedTxIn: {
      txId: seedTxInParts[0],
      index: Number(seedTxInParts[1]),
    },
    factoryNFTName: params.factoryNFTName,
    poolNFTName: params.poolNFTName,
    globalSettingNFTName: params.globalSettingNFTName,
    poolDefaultStakeKey: params.poolStakeCredential,
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

type ContractScript = {
  // Authentication asset
  factoryAsset: Asset;
  poolAuthenAsset: Asset;
  globalSettingAsset: Asset;

  // LP PolicyID
  lpPolicyId: string;

  // Smart contract address
  globalSettingEnterpriseAddress: string;
  orderEnterpriseAddress: string;
  poolEnterpriseAddress: string;
  poolCreationAddress: string;
  factoryEnterpriseAddress: string;
  expiredOrderCancelAddress: string;
  poolBatchingAddress: string;
  poolBatchingCredential: Credential;

  // Smart contract script
  authenScript: Script;
  poolScript: Script;
  orderScript: Script;
  factoryScript: Script;
  expiredOrderCancelScript: Script;
  poolBatchingScript: Script;
};

export function getContractScripts(
  lucid: Lucid,
  networkId: NetworkId
): ContractScript {
  const validators = readValidator();
  const {
    seedTxIn,
    factoryNFTName,
    poolNFTName,
    globalSettingNFTName,
    poolDefaultStakeKey,
  } = getContractParameters(networkId);
  const authenMintingScript: Script = {
    type: "PlutusV2",
    script: applyParamsToScript(validators.authen.script, [
      TxIn.toPlutus(seedTxIn),
    ]),
  };
  const authenPolicyId = lucid.utils.mintingPolicyToId(authenMintingScript);
  const poolScript: Script = {
    type: "PlutusV2",
    script: applyParamsToScript(validators.pool.script, [authenPolicyId]),
  };
  const poolHash = lucid.utils.validatorToScriptHash(poolScript);
  const poolCreationAddress = lucid.utils.validatorToAddress(
    poolScript,
    poolDefaultStakeKey
  );
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
      AddressPlutusData.toPlutus(poolCreationAddress),
      poolBatchingStakeCredential,
    ]),
  };

  const globalSettingAddress =
    lucid.utils.validatorToAddress(authenMintingScript);
  const poolEnterpriseAddress = lucid.utils.validatorToAddress(poolScript);
  const orderEnterpriseAddress = lucid.utils.validatorToAddress(orderScript);
  const factoryEnterpriseAddress =
    lucid.utils.validatorToAddress(factoryScript);
  const expiredOrderCancellationAddress = lucid.utils.validatorToRewardAddress(
    expiredOrderCancellationScript
  );
  const poolBatchingAddress =
    lucid.utils.validatorToRewardAddress(poolBatchingScript);

  return {
    factoryAsset: {
      policyId: authenPolicyId,
      tokenName: fromText(factoryNFTName),
    },
    poolAuthenAsset: {
      policyId: authenPolicyId,
      tokenName: fromText(poolNFTName),
    },
    globalSettingAsset: {
      policyId: authenPolicyId,
      tokenName: fromText(globalSettingNFTName),
    },
    lpPolicyId: authenPolicyId,
    globalSettingEnterpriseAddress: globalSettingAddress,
    orderEnterpriseAddress: orderEnterpriseAddress,
    poolEnterpriseAddress: poolEnterpriseAddress,
    poolCreationAddress: poolCreationAddress,
    factoryEnterpriseAddress: factoryEnterpriseAddress,
    expiredOrderCancelAddress: expiredOrderCancellationAddress,
    poolBatchingAddress: poolBatchingAddress,
    poolBatchingCredential: {
      type: "Script",
      hash: poolBatchingHash,
    },
    authenScript: authenMintingScript,
    poolScript: poolScript,
    orderScript: orderScript,
    factoryScript: factoryScript,
    expiredOrderCancelScript: expiredOrderCancellationScript,
    poolBatchingScript: poolBatchingScript,
  };
}
