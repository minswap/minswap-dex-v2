import { mConStr0, mConStr1, stringToHex } from "@meshsdk/core";
import { authenPolicyId, authenValidatorScript, blockchainProvider, factoryAddress, factoryAssetName, poolAuthAssetName, poolBatchingValidatorHash, poolValidatorAddress, txBuilder, wallet1, wallet1Address, wallet1Collateral, wallet1Utxos } from "./setup.js";
import { alwaysSuccessMintValidatorHash } from "./mint_test_tokens.js";
import { sha256 } from "lucid-cardano";
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
console.log("Asset A unit:", alwaysSuccessMintValidatorHash + tokenA);
console.log("Asset B unit:", alwaysSuccessMintValidatorHash + tokenB);
// compute lp asset name
// const assetASha256 = crypto.createHash('sha3-256').update(alwaysSuccessMintValidatorHash + tokenA).digest('hex');
// const assetBSha256 = crypto.createHash('sha3-256').update(alwaysSuccessMintValidatorHash + tokenB).digest('hex');
// const lpAssetName = crypto.createHash('sha3-256').update(assetASha256 + assetBSha256).digest('hex');
// console.log("lpAssetName offchain:", lpAssetName, '\n');
// lpAssetName offchain: 8153379443cf9f6a703bfadf9957899ab84f15c929c88ff8adae624f3307a141
const toHexString = (byteArray) => {
    return Array.from(byteArray, byte => {
        return ('0' + (byte & 0xFF).toString(16)).slice(-2);
    }).join('');
};
const hexToBytes = (hex) => {
    let bytes = new Uint8Array(hex.length / 2);
    for (let c = 0; c < hex.length; c += 2) {
        bytes[c / 2] = parseInt(hex.substr(c, 2), 16);
    }
    return bytes;
};
const assetASha256 = toHexString(sha256(new Uint8Array([...hexToBytes(alwaysSuccessMintValidatorHash + tokenB)])));
const assetBSha256 = toHexString(sha256(new Uint8Array([...hexToBytes(alwaysSuccessMintValidatorHash + tokenA)])));
const lpAssetName = toHexString(sha256(new Uint8Array([...hexToBytes(assetASha256 + assetBSha256)])));
console.log("lpAssetName offchain:", lpAssetName, '\n');
// lpAssetName offchain: 78a140a30ee1d60c49b3a46e64374f0e89102d13225eaa2d9a1746ad3c5cbb7e
const factoryNftUnit = authenPolicyId + factoryAssetName;
const factoryDatum1 = mConStr0([
    "00",
    lpAssetName,
]);
const factoryDatum2 = mConStr0([
    lpAssetName,
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00",
]);
const calculate_initial_liquidity = (out_a, out_b) => {
    let p = out_a * out_b;
    let sqrt = Math.floor(Math.sqrt(p)); // mimicking Aiken, because it floors any decimal
    if (sqrt * sqrt < p) {
        return (sqrt + 1);
    }
    return sqrt;
};
const iMyTokenTwoSupply = 1500;
const myTokenOneSupply = 1500;
const totalLiquidity = calculate_initial_liquidity(myTokenOneSupply, iMyTokenTwoSupply);
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
// const maxInt64 = 9223372036854775807;
const maxInt64 = 92233720368547;
const remainingLiquidity = maxInt64 - totalLiquidity - 10;
console.log("remainingLiquidity:", remainingLiquidity, '\n');
const unsignedTx = await txBuilder
    // consume last factory UTxO
    .spendingPlutusScriptV3()
    .txIn(factoryInput.input.txHash, factoryInput.input.outputIndex, factoryInput.output.amount, factoryInput.output.address)
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
    { unit: alwaysSuccessMintValidatorHash + stringToHex("myTokenOne"), quantity: String(myTokenOneSupply) },
    { unit: alwaysSuccessMintValidatorHash + stringToHex("iMyTokenTwo"), quantity: String(iMyTokenTwoSupply) },
    { unit: authenPolicyId + poolAuthAssetName, quantity: "1" },
    { unit: authenPolicyId + lpAssetName, quantity: String(remainingLiquidity) },
])
    .txOutInlineDatumValue(poolDatum)
    .txInCollateral(wallet1Collateral.input.txHash, wallet1Collateral.input.outputIndex, wallet1Collateral.output.amount, wallet1Collateral.output.address)
    .changeAddress(wallet1Address)
    .selectUtxosFrom(wallet1Utxos)
    .complete();
const signedTx = await wallet1.signTx(unsignedTx);
const txHash = await wallet1.submitTx(signedTx);
console.log("Create order tx hash:", txHash);
