import { mConStr0, mConStr1, stringToHex } from "@meshsdk/core";
import { authenPolicyId, authenValidatorScript, blockchainProvider, factoryAddress, factoryAssetName, factoryValidatorScript, poolAuthAssetName, poolBatchingValidatorHash, poolValidatorAddress, txBuilder, wallet1, wallet1Address, wallet1Collateral, wallet1Utxos } from "./setup.js"
import { alwaysSuccessMintValidatorHash } from "./mint_test_tokens.js";
import { SHA3 } from "sha3";

// Authen
const authenScriptTxHash = "cd7e32ac4dbb39a18b0dedc6b0503efc7d7245bf0318d5c223b6a80de9ae12bd";
const authenScriptTxIndex = 0;
// Factory
const factoryScriptTxHash = "dceab6c01f14c4fb95cae621ed4b1d633044a209db48c56f613b1b578dab9a81";
const factoryScriptTxIndex = 0;

const factoryUtxos = await blockchainProvider.fetchAddressUTxOs(factoryAddress);
const factoryInput = factoryUtxos[factoryUtxos.length - 1];
if (!factoryInput) {
    throw new Error('Factory input not found');
}

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
const factoryRedeemer = mConStr0([
    assetA,
    assetB,
]);

console.log("Asset A unit:", alwaysSuccessMintValidatorHash, tokenA);
console.log("Asset B unit:", alwaysSuccessMintValidatorHash, tokenB);

// compute lp asset name
const sha3 = (hex: string): string => {
  const hash = new SHA3(256);
  hash.update(hex, "hex");
  return hash.digest("hex");
}
const assetASha256 = sha3(alwaysSuccessMintValidatorHash + tokenA);
const assetBSha256 = sha3(alwaysSuccessMintValidatorHash + tokenB);
const lpAssetName = sha3(assetASha256 + assetBSha256);
console.log("lpAssetName offchain:", lpAssetName, '\n');

const factoryNftUnit = authenPolicyId + factoryAssetName;
const factoryDatum1 = mConStr0([
    "00",
    lpAssetName,
]);
const factoryDatum2 = mConStr0([
    lpAssetName,
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00",
]);

const calculateInitialLiquidity = (out_a: number, out_b: number) => {
    let p = out_a * out_b
    let sqrt = Math.floor(Math.sqrt(p)); // mimicking Aiken, because it floors any decimal
    if ((sqrt * sqrt) < p) {
        console.log("sqrt + 1:", sqrt + 1);
        return (sqrt + 1);
    }
    console.log("sqrt:", sqrt);
    return sqrt;
}
const iMyTokenTwoSupply = 1500;
const myTokenOneSupply = 1500;
const totalLiquidity = calculateInitialLiquidity(myTokenOneSupply, iMyTokenTwoSupply)
// pool datum
const poolDatum = mConStr0([
    mConStr1([poolBatchingValidatorHash]),
    assetA,
    assetB,
    totalLiquidity,
    iMyTokenTwoSupply,
    myTokenOneSupply,
    6,
    6,
    mConStr1([]),
    mConStr0([]),
]);

const maxInt64 = 9223372036854775807n;
const remainingLiquidity = maxInt64 - (BigInt(totalLiquidity) - 10n);
console.log("totalLiquidity:", totalLiquidity, '\n');
console.log("remainingLiquidity:", remainingLiquidity, '\n');
console.log("remainingLiquidity String:", String(remainingLiquidity), '\n');

const unsignedTx = await txBuilder
    // consume last factory UTxO
    .spendingPlutusScriptV3()
    .txIn(
        factoryInput.input.txHash,
        factoryInput.input.outputIndex,
        factoryInput.output.amount,
        factoryInput.output.address,
    )
    // .txInScript(factoryValidatorScript)
    .spendingTxInReference(factoryScriptTxHash, factoryScriptTxIndex)
    .spendingReferenceTxInInlineDatumPresent()
    .spendingReferenceTxInRedeemerValue(factoryRedeemer)
    // mint pool factory NFT
    .mintPlutusScriptV3()
    .mint("1", authenPolicyId, factoryAssetName)
    .mintingScript(authenValidatorScript)
    // .mintTxInReference(authenScriptTxHash, authenScriptTxIndex)
    .mintRedeemerValue(mConStr1([]))
    // mint pool NFT
    .mintPlutusScriptV3()
    .mint("1", authenPolicyId, poolAuthAssetName)
    .mintingScript(authenValidatorScript)
    // .mintTxInReference(authenScriptTxHash, authenScriptTxIndex)
    .mintRedeemerValue(mConStr1([]))
    // mint lp tokens
    .mintPlutusScriptV3()
    .mint(String(maxInt64), authenPolicyId, lpAssetName)
    .mintingScript(authenValidatorScript)
    // .mintTxInReference(authenScriptTxHash, authenScriptTxIndex)
    .mintRedeemerValue(mConStr1([]))
    // previous element of factory linked list
    .txOut(factoryAddress, [{ unit: factoryNftUnit, quantity: "1" }])
    .txOutInlineDatumValue(factoryDatum1)
    // next element of factory linked list
    .txOut(factoryAddress, [{ unit: factoryNftUnit, quantity: "1" }])
    .txOutInlineDatumValue(factoryDatum2)
    // pool validator output
    .txOut(poolValidatorAddress, [
        { unit: "lovelace", quantity: "4500000" },
        { unit: alwaysSuccessMintValidatorHash + stringToHex("iMyTokenTwo"), quantity: String(iMyTokenTwoSupply) },
        { unit: alwaysSuccessMintValidatorHash + stringToHex("myTokenOne"), quantity: String(myTokenOneSupply) },
        { unit: authenPolicyId + lpAssetName, quantity: String(remainingLiquidity) },
        { unit: authenPolicyId + poolAuthAssetName, quantity: "1" },
    ])
    .txOutInlineDatumValue(poolDatum)
    .txInCollateral(
        wallet1Collateral.input.txHash,
        wallet1Collateral.input.outputIndex,
        wallet1Collateral.output.amount,
        wallet1Collateral.output.address,
    )
    .changeAddress(wallet1Address)
    .selectUtxosFrom(wallet1Utxos)
    .complete()

const signedTx = await wallet1.signTx(unsignedTx);
const txHash = await wallet1.submitTx(signedTx);

console.log("Create pool tx hash:", txHash);
