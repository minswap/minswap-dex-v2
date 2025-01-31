import {
    BlockfrostProvider,
    MaestroProvider,
    MeshTxBuilder,
    MeshWallet,
    applyParamsToScript,
    deserializeAddress,
    resolveScriptHash,
    serializeNativeScript,
    serializePlutusScript,
} from "@meshsdk/core";
import { builtinByteString, conStr, NativeScript, outputReference, scriptAddress, UTxO } from "@meshsdk/common";
import dotenv from "dotenv";
dotenv.config();
import blueprint from "../plutus.json" with { type: "json" };
import { OfflineEvaluator, resolveNativeScriptHash } from "@meshsdk/core-csl";

// Setup blockhain provider as Maestro
const maestroKey = process.env.MAESTRO_KEY;
if (!maestroKey) {
    throw new Error("MAESTRO_KEY does not exist");
}
const blockchainProvider = new MaestroProvider({
    network: 'Preprod',
    apiKey: maestroKey,
});

// Setup blockhain provider as Blockfrost
// const blockfrostId = process.env.BLOCKFROST_ID;
// if (!blockfrostId) {
//     throw new Error("BLOCKFROST_ID does not exist");
// }
// const blockchainProvider = new BlockfrostProvider(blockfrostId);

// import admin's wallet passphrase and initialize the wallet
const wallet1Passphrase = process.env.WALLET_PASSPHRASE_ONE;
if (!wallet1Passphrase) {
    throw new Error("WALLET_PASSPHRASE_ONE does not exist");
}
const wallet1 = new MeshWallet({
    networkId: 0,
    fetcher: blockchainProvider,
    submitter: blockchainProvider,
    key: {
        type: "mnemonic",
        words: wallet1Passphrase.split(' ')
    },
});

const wallet1Address = await wallet1.getChangeAddress();

const wallet1Utxos = await wallet1.getUtxos();
const wallet1Collateral: UTxO = (await wallet1.getCollateral())[0]
if (!wallet1Collateral) {
    throw new Error('No collateral utxo found');
}

const { pubKeyHash: wallet1VK } = deserializeAddress(wallet1Address);

// Setup wallet2
const wallet2Passphrase = process.env.WALLET_PASSPHRASE_TWO;
if (!wallet2Passphrase) {
    throw new Error("WALLET_PASSPHRASE_TWO does not exist");
}
const wallet2 = new MeshWallet({
    networkId: 0,
    fetcher: blockchainProvider,
    submitter: blockchainProvider,
    key: {
        type: "mnemonic",
        words: wallet2Passphrase.split(' ')
    },
});
const wallet2Address = await wallet1.getChangeAddress();
const { pubKeyHash: wallet2VK } = deserializeAddress(wallet2Address);

// Setup multisig
const nativeScript: NativeScript = {
    type: "all",
    scripts: [
        {
            type: "sig",
            keyHash: wallet1VK,
        },
        {
            type: "sig",
            keyHash: wallet2VK,
        },
    ],
};
const { address: multiSigAddress, scriptCbor: multiSigCbor } = serializeNativeScript(nativeScript);
const multisigHash = resolveNativeScriptHash(nativeScript);

// Evaluator for Aiken verbose mode
const evaluator = new OfflineEvaluator(blockchainProvider, "preprod");
// Create transaction builder
const txBuilder = new MeshTxBuilder({
    fetcher: blockchainProvider,
    submitter: blockchainProvider,
    evaluator: evaluator, // Can also be "evaluator: blockchainProvider,"
    verbose: false,
});
txBuilder.setNetwork('preprod');

// Always true validator
const alwaysSuccessValidator = blueprint.validators.filter(v => (
    v.title.includes("always_success.always_success.spend")
));
const alwaysSuccessValidatorScript = applyParamsToScript(
    alwaysSuccessValidator[0].compiledCode,
    [],
    "JSON",
);
const alwaysSuccessValidatorHash = resolveScriptHash(alwaysSuccessValidatorScript, "V3");

// Authen Minting Policy
const authenValidator = blueprint.validators.filter(v => (
    v.title.includes("authen_minting_policy.authen_minting_policy.mint")
));
const authenValidatorScript = applyParamsToScript(
    authenValidator[0].compiledCode,
    [outputReference("3c149a5500447e8f8c7a508ef47f1743da0ff2e4ef4c6d02b1a44a9888c89569", 0)], // change this to real values <====
    "JSON",
);
const authenPolicyId = resolveScriptHash(authenValidatorScript, "V3");
const authenAddress = serializePlutusScript(
    { code: authenValidatorScript, version: "V3" },
    undefined,
    0,
).address;

// Pool Validator
const poolValidator = blueprint.validators.filter(v => (
    v.title.includes("pool_validator.pool_validator.withdraw") // withdraw 0
));
const poolValidatorScript = applyParamsToScript(
    poolValidator[0].compiledCode,
    [builtinByteString(authenPolicyId)],
    "JSON",
);
const poolStakeCredentialHash = resolveScriptHash(poolValidatorScript, "V3");
const poolAddressData = scriptAddress(
    alwaysSuccessValidatorHash, // modify here <==== DONE
    poolStakeCredentialHash,
);

// Pool Batching Validator
const poolBatchingValidator = blueprint.validators.filter(v => (
    v.title.includes("pool_validator.pool_batching_validator.withdraw")
));
const poolBatchingValidatorScript = applyParamsToScript(
    poolBatchingValidator[0].compiledCode,
    [builtinByteString(authenPolicyId), conStr(1, [builtinByteString(alwaysSuccessValidatorHash)])], // modify here <==== DONE
    "JSON",
);
const poolBatchingValidatorHash = resolveScriptHash(poolBatchingValidatorScript, "V3");

// Factory Validator
const factoryValidator = blueprint.validators.filter(v => (
    v.title.includes("factory_validator.factory_validator.spend")
));
const factoryValidatorScript = applyParamsToScript(
    factoryValidator[0].compiledCode,
    [builtinByteString(authenPolicyId), poolAddressData, conStr(1, [builtinByteString(poolBatchingValidatorHash)])],
    "JSON",
);
const factoryAddress = serializePlutusScript(
    { code: factoryValidatorScript, version: "V3" },
    undefined,
    0,
).address;

// Order Cancellation Validator
const orderCanclValidator = blueprint.validators.filter(v => (
    v.title.includes("order_validator.validate_expired_order_cancel.withdraw")
));
const orderCanclValidatorScript = applyParamsToScript(
    orderCanclValidator[0].compiledCode,
    [],
    "JSON",
);
const orderCanclValidatorHash = resolveScriptHash(orderCanclValidatorScript, "V3");

// Order Validator
const orderValidator = blueprint.validators.filter(v => (
    v.title.includes("order_validator.order_validator.withdraw")
));
const orderValidatorScript = applyParamsToScript(
    orderValidator[0].compiledCode,
    [conStr(1, [builtinByteString(poolBatchingValidatorHash)]), conStr(1, [builtinByteString(orderCanclValidatorHash)])],
    "JSON",
);
console.log('orderValidatorScript:', orderValidatorScript);

export {
    blueprint,
    maestroKey,
    wallet1Passphrase,
    blockchainProvider,
    txBuilder,
    wallet1,
    wallet1Address,
    wallet1VK,
    wallet1Utxos,
    wallet1Collateral,
    wallet2,
    multisigHash,
    multiSigAddress,
    // authen
    authenValidatorScript,
    authenPolicyId,
    authenAddress,
    // factory
    factoryAddress,
}
