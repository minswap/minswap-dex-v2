import { MaestroProvider, MeshTxBuilder, MeshWallet, applyParamsToScript, deserializeAddress, resolveScriptHash, serializeNativeScript, serializePlutusScript, serializeRewardAddress, } from "@meshsdk/core";
import { builtinByteString, conStr, mConStr0, outputReference, scriptAddress, stringToHex } from "@meshsdk/common";
import dotenv from "dotenv";
dotenv.config();
import blueprint from "../plutus.json" with { type: "json" };
import testBlueprint from "./always_success_mint/plutus.json" with { type: "json" };
import { OfflineEvaluator, resolveNativeScriptHash } from "@meshsdk/core-csl";
import { SHA3 } from "sha3";
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
// import wallet1's wallet passphrase and initialize the wallet
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
// const wallet1Collateral: UTxO = (await blockchainProvider.fetchUTxOs("0f61fee1b8e12b8faf807794464bef3195a32b7949270c7f530fff5144e36aa1", 5))[0];
const wallet1Collateral = (await wallet1.getCollateral())[0];
if (!wallet1Collateral) {
    throw new Error('No collateral utxo found');
}
const { pubKeyHash: wallet1VK, stakeCredentialHash: wallet1SK } = deserializeAddress(wallet1Address);
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
const wallet2Utxos = await wallet2.getUtxos();
const wallet2Collateral = (await wallet2.getCollateral())[0];
if (!wallet2Collateral) {
    throw new Error('No collateral utxo found');
}
// Setup multisig
const nativeScript = {
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
const evaluator = new OfflineEvaluator(blockchainProvider, 'preprod');
// Create transaction builder
const txBuilder = new MeshTxBuilder({
    fetcher: blockchainProvider,
    submitter: blockchainProvider,
    evaluator: evaluator, // Can also be "evaluator: blockchainProvider,"
    // evaluator: blockchainProvider,
    // verbose: true,
});
txBuilder.setNetwork('preprod');
// constants
const factoryAssetName = "4d5346";
const poolAuthAssetName = "4d5350";
const globalSettingAssetName = "4d534753";
// Utils
const calculateInitialLiquidity = (out_a, out_b) => {
    let p = out_a * out_b;
    let sqrt = Math.floor(Math.sqrt(p)); // mimicking Aiken, because it floors any decimal
    if ((sqrt * sqrt) < p) {
        // console.log("sqrt + 1:", sqrt + 1);
        return (sqrt + 1);
    }
    // console.log("sqrt:", sqrt);
    return sqrt;
};
// Always true validator
const alwaysSuccessValidator = blueprint.validators.filter(v => (v.title.includes("always_success.always_success.spend")));
const alwaysSuccessValidatorScript = applyParamsToScript(alwaysSuccessValidator[0].compiledCode, [], "JSON");
const alwaysSuccessValidatorHash = resolveScriptHash(alwaysSuccessValidatorScript, "V3");
// Authen Minting Policy
const authenValidator = blueprint.validators.filter(v => (v.title.includes("authen_minting_policy.authen_minting_policy.mint")));
const dexInitParamTxHash = "bc69a906e208b8d0f4cb520979b098542283561c3cdac69cd4b7ee66c0dded78"; // change this and below on each dex init
const dexInitParamTxIndex = 2;
const authenValidatorScript = applyParamsToScript(authenValidator[0].compiledCode, [outputReference(dexInitParamTxHash, dexInitParamTxIndex)], "JSON");
const authenPolicyId = resolveScriptHash(authenValidatorScript, "V3");
const authenAddress = serializePlutusScript({ code: authenValidatorScript, version: "V3" }, undefined, 0).address;
// Pool Validator
const poolValidator = blueprint.validators.filter(v => (v.title.includes("pool_validator.pool_validator.withdraw") // withdraw 0
));
const poolValidatorScript = applyParamsToScript(poolValidator[0].compiledCode, [builtinByteString(authenPolicyId)], "JSON");
const poolStakeCredentialHash = resolveScriptHash(poolValidatorScript, "V3");
const poolValidatorAddress = serializePlutusScript({ code: alwaysSuccessValidatorScript, version: "V3" }, poolStakeCredentialHash, 0, true).address;
const poolValidatorRewardAddress = serializeRewardAddress(poolStakeCredentialHash, true, 0);
const poolAddressData = scriptAddress(alwaysSuccessValidatorHash, poolStakeCredentialHash, true);
const poolValidatorScriptHash = poolStakeCredentialHash;
console.log("poolValidatorScriptHash:", poolValidatorScriptHash);
// Pool Batching Validator
const poolBatchingValidator = blueprint.validators.filter(v => (v.title.includes("pool_validator.pool_batching_validator.withdraw")));
const poolBatchingValidatorScript = applyParamsToScript(poolBatchingValidator[0].compiledCode, [builtinByteString(authenPolicyId), poolAddressData], "JSON");
const poolBatchingValidatorHash = resolveScriptHash(poolBatchingValidatorScript, "V3");
const poolBatchingValidatorRewardAddress = serializeRewardAddress(poolBatchingValidatorHash, true, 0);
console.log("poolBatchingValidatorHash:", poolBatchingValidatorHash);
// Factory Validator
const factoryValidator = blueprint.validators.filter(v => (v.title.includes("factory_validator.factory_validator.spend")));
const factoryValidatorScript = applyParamsToScript(factoryValidator[0].compiledCode, [builtinByteString(authenPolicyId), poolAddressData, conStr(1, [builtinByteString(poolBatchingValidatorHash)])], "JSON");
const factoryAddress = serializePlutusScript({ code: factoryValidatorScript, version: "V3" }, undefined, 0).address;
// Order Cancellation Validator
const orderCanclValidator = blueprint.validators.filter(v => (v.title.includes("order_validator.validate_expired_order_cancel.withdraw")));
const orderCanclValidatorScript = applyParamsToScript(orderCanclValidator[0].compiledCode, [], "JSON");
const orderCanclValidatorHash = resolveScriptHash(orderCanclValidatorScript, "V3");
const orderCanclValidatorRewardAddress = serializeRewardAddress(orderCanclValidatorHash, true, 0);
// Order Validator
const orderValidator = blueprint.validators.filter(v => (v.title.includes("order_validator.order_validator.withdraw")));
const orderValidatorScript = applyParamsToScript(orderValidator[0].compiledCode, [conStr(1, [builtinByteString(poolBatchingValidatorHash)]), conStr(1, [builtinByteString(orderCanclValidatorHash)])], "JSON");
const orderValidatorScriptHash = resolveScriptHash(orderValidatorScript, "V3");
const orderValidatorAddress = serializePlutusScript({ code: alwaysSuccessValidatorScript, version: "V3" }, orderValidatorScriptHash, 0, true).address;
const orderValidatorRewardAddress = serializeRewardAddress(orderValidatorScriptHash, true, 0);
console.log("orderValidatorScriptHash:", orderValidatorScriptHash);
// console.log('orderValidator Reward Address:', orderValidatorRewardAddress);
// tests
// console.log("orderValidatorScriptHash:", orderValidatorScriptHash);
// const { pubKeyHash: orderVK, stakeCredentialHash: orderSK, scriptHash: orderScH, stakeScriptCredentialHash: orderStakeScH  } = deserializeAddress(orderValidatorAddress);
// console.log("orderVK:", orderVK);
// console.log("orderSK:", orderSK);
// console.log("orderScH:", orderScH);
// console.log("orderStakeScH:", orderStakeScH);
console.log("authen validator utxos number:", (await blockchainProvider.fetchAddressUTxOs(authenAddress)).length, '\n');
console.log("factory validator utxos number:", (await blockchainProvider.fetchAddressUTxOs(factoryAddress)).length, '\n');
// test mint
// Always success mint validator
const alwaysSuccessMintValidator = testBlueprint.validators.filter(v => (v.title.includes("placeholder.placeholder.mint")));
const alwaysSuccessValidatorMintScript = applyParamsToScript(alwaysSuccessMintValidator[0].compiledCode, [], "JSON");
const alwaysSuccessMintValidatorHash = resolveScriptHash(alwaysSuccessValidatorMintScript, "V3");
// pool utils
const tokenA = stringToHex("iMyTokenTwo");
const assetA = mConStr0([
    alwaysSuccessMintValidatorHash,
    tokenA,
]);
const tokenB = stringToHex("myTokenOne");
const assetB = mConStr0([
    alwaysSuccessMintValidatorHash,
    tokenB,
]);
// compute lp asset name
const sha3 = (hex) => {
    const hash = new SHA3(256);
    hash.update(hex, "hex");
    return hash.digest("hex");
};
const assetASha256 = sha3(alwaysSuccessMintValidatorHash + tokenA);
const assetBSha256 = sha3(alwaysSuccessMintValidatorHash + tokenB);
const lpAssetName = sha3(assetASha256 + assetBSha256);
// asset supplies
const iMyTokenTwoSupply = 1500;
const myTokenOneSupply = 1500;
const totalLiquidity = calculateInitialLiquidity(myTokenOneSupply, iMyTokenTwoSupply);
const maxInt64 = 9223372036854775807n;
const remainingLiquidity = maxInt64 - (BigInt(totalLiquidity) - 10n);
// order utils
const swapAmount = 20;
const orderLovelaceAmount = 10000000;
export { blueprint, blockchainProvider, txBuilder, 
// wallet1
wallet1, wallet1Address, wallet1VK, wallet1SK, wallet1Utxos, wallet1Collateral, 
// wallet 2
wallet2, wallet2Collateral, wallet2Utxos, wallet2Address, 
// multisig
multisigHash, multiSigAddress, 
// authen
authenValidatorScript, authenPolicyId, authenAddress, dexInitParamTxHash, dexInitParamTxIndex, 
// factory
factoryValidatorScript, factoryAddress, 
// order
orderValidatorScript, orderValidatorAddress, orderValidatorRewardAddress, orderValidatorScriptHash, 
// order cancellation validator
orderCanclValidatorScript, orderCanclValidatorRewardAddress, 
// pool
poolValidatorAddress, poolValidatorRewardAddress, poolValidatorScript, poolValidatorScriptHash, 
// pool batching
poolBatchingValidatorHash, poolBatchingValidatorRewardAddress, poolBatchingValidatorScript, 
// always success
alwaysSuccessValidatorScript, 
// always success mint
alwaysSuccessValidatorMintScript, alwaysSuccessMintValidatorHash, 
// constants
factoryAssetName, poolAuthAssetName, globalSettingAssetName, 
// Utils
calculateInitialLiquidity, 
// pool utils
tokenA, tokenB, assetA, assetB, lpAssetName, iMyTokenTwoSupply, myTokenOneSupply, totalLiquidity, maxInt64, remainingLiquidity, 
// order utils
swapAmount, orderLovelaceAmount, };
