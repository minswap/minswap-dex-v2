import { deserializeDatum, mConStr0, mConStr1, SLOT_CONFIG_NETWORK, stringToHex, unixTimeToEnclosingSlot } from "@meshsdk/core";
import { alwaysSuccessMintValidatorHash, alwaysSuccessValidatorScript, assetA, assetB, authenAddress, authenPolicyId, blockchainProvider, lpAssetName, orderLovelaceAmount, orderValidatorAddress, orderValidatorRewardAddress, orderValidatorScriptHash, poolAuthAssetName, poolBatchingValidatorHash, poolBatchingValidatorRewardAddress, poolValidatorAddress, poolValidatorRewardAddress, poolValidatorScriptHash, remainingLiquidity, swapAmount, totalLiquidity, txBuilder, wallet1, wallet1Address, wallet1Collateral, wallet1Utxos, wallet1VK } from "./setup.js";
// pool batching ref script
const poolBatchingScriptTxHash = "75e53842f67e41cb7cbc9f6496913c17147017fae341c4ae77afbdf46fc4a110"; // Preview 1.8.14 -> "77bbb195460ab5fcae27f70858ae373c9cda09a26bfadc8c7655268e840d8ed3"; // Preview 1.8.8 -> "64ef728f6eae2f102108268f66b0c13c27a709baa4e7a87b6be0b89ba749971f";
const poolBatchingScriptTxIndex = 0;
// pool ref script
const poolScriptTxHash = "61453a1a6314c58fa622ee2ee1651d18420a4c60a47c17c82eb70e15a7f2ba1c"; // Preview 1.8.14 -> "7a946f89065ea118b133c405771bbb06f9eca14b19796ae2b9b2475066a230ec"; // Preview 1.8.8 -> "8d7f379ef425a9a35fd58c2b92cbb31d1237774387fa71368ca7d19250928a9f";
const poolScriptTxIndex = 0;
// order ref script
const orderScriptTxHash = "d4a881d7562d1e17fa0ae7b02dd9dec40564ca2e7258b286ba8d5511ce97809a"; // Preview 1.8.14 -> "fe772f40e5426b35451a3bf20c7fcc22902062517b7ddeb42ca6cd781c31be58"; // Preview 1.8.8 -> "8bf0851af4d85a8db601d77576bc2dad733d07d8147b31c75b67e743d92573e6";
const orderScriptTxIndex = 0;
console.log("pool validator utxos number:", (await blockchainProvider.fetchAddressUTxOs(poolValidatorAddress)).length, '\n');
console.log("order validator utxos number:", (await blockchainProvider.fetchAddressUTxOs(orderValidatorAddress)).length, '\n');
const poolUtxo = (await blockchainProvider.fetchAddressUTxOs(poolValidatorAddress))[0];
if (!poolUtxo) {
    throw new Error("pool utxo not found!");
}
const orderUtxos = await blockchainProvider.fetchAddressUTxOs(orderValidatorAddress);
const orderUtxo = orderUtxos[orderUtxos.length - 1];
if (!orderUtxo) {
    throw new Error("order utxo not found!");
}
const globalSettingsUtxo = (await blockchainProvider.fetchAddressUTxOs(authenAddress))[0];
if (!globalSettingsUtxo) {
    throw new Error("global settings utxo not found!");
}
const usedBatcherFee = 3000000;
const poolBatchingRedeemer = mConStr0([
    0,
    [usedBatcherFee], // used_batcher_fee, first index: 3 ADA
    "00", // minswap used "00"
    mConStr1([]),
    [mConStr1([])] // [mConStr0([6])],
]);
// order output value
const orderLovelaceBalance = orderLovelaceAmount - usedBatcherFee;
const assetBAmount = 19; // pre-calculated on chain (just for testing)
// updated pool datum (calculated updated reserves based on A -> B order direction)
if (!poolUtxo.output.plutusData) {
    throw new Error("No datum in pool utxo");
}
const oldPoolDatum = deserializeDatum(poolUtxo.output.plutusData); // ideal way is to create a type for the datum to deserialize; this is just for testing
const updatedIMyTokenTwoSupply = oldPoolDatum.fields[4].int + swapAmount;
const updatedMyTokenOneSupply = oldPoolDatum.fields[5].int - assetBAmount;
console.log("updatedIMyTokenTwoSupply:", updatedIMyTokenTwoSupply);
console.log("updatedMyTokenOneSupply:", updatedMyTokenOneSupply);
const poolDatum = mConStr0([
    mConStr1([poolBatchingValidatorHash]),
    assetA,
    assetB,
    totalLiquidity,
    updatedIMyTokenTwoSupply,
    updatedMyTokenOneSupply,
    6,
    6,
    mConStr1([]),
    mConStr0([]),
]);
const invalidBefore = unixTimeToEnclosingSlot((Date.now() - 30000), SLOT_CONFIG_NETWORK.preprod);
const invalidAfter = unixTimeToEnclosingSlot((Date.now() + 8 * 60 * 1000), // 8 mins
SLOT_CONFIG_NETWORK.preprod);
const unsignedTx = await txBuilder
    // spend order utxo
    .spendingPlutusScriptV3()
    .txIn(orderUtxo.input.txHash, orderUtxo.input.outputIndex, orderUtxo.output.amount, orderUtxo.output.address)
    .txInScript(alwaysSuccessValidatorScript)
    .spendingReferenceTxInInlineDatumPresent()
    .spendingReferenceTxInRedeemerValue("")
    // withdraw script on order utxo
    .withdrawalPlutusScriptV3()
    .withdrawal(orderValidatorRewardAddress, "0")
    // .withdrawalScript(orderValidatorScript)
    .withdrawalTxInReference(orderScriptTxHash, orderScriptTxIndex, undefined, orderValidatorScriptHash)
    .withdrawalRedeemerValue(mConStr0([]))
    // spend pool utxo
    .spendingPlutusScriptV3()
    .txIn(poolUtxo.input.txHash, poolUtxo.input.outputIndex, poolUtxo.output.amount, poolUtxo.output.address)
    .txInScript(alwaysSuccessValidatorScript)
    .spendingReferenceTxInInlineDatumPresent()
    .spendingReferenceTxInRedeemerValue("")
    // withdraw script on pool utxo
    .withdrawalPlutusScriptV3()
    .withdrawal(poolValidatorRewardAddress, "0")
    // .withdrawalScript(poolValidatorScript)
    .withdrawalTxInReference(poolScriptTxHash, poolScriptTxIndex, undefined, poolValidatorScriptHash)
    .withdrawalRedeemerValue(mConStr0([]))
    // pool batching withdrawal
    .withdrawalPlutusScriptV3()
    .withdrawal(poolBatchingValidatorRewardAddress, "0")
    // .withdrawalScript(poolBatchingValidatorScript)
    .withdrawalTxInReference(poolBatchingScriptTxHash, poolBatchingScriptTxIndex, undefined, poolBatchingValidatorHash)
    .withdrawalRedeemerValue(poolBatchingRedeemer)
    // order output
    .txOut(wallet1Address, [
    { unit: "lovelace", quantity: String(orderLovelaceBalance) },
    { unit: alwaysSuccessMintValidatorHash + stringToHex("myTokenOne"), quantity: String(assetBAmount) }
])
    // pool validator output
    .txOut(poolValidatorAddress, [
    { unit: "lovelace", quantity: "4500000" },
    { unit: alwaysSuccessMintValidatorHash + stringToHex("iMyTokenTwo"), quantity: String(updatedIMyTokenTwoSupply) },
    { unit: alwaysSuccessMintValidatorHash + stringToHex("myTokenOne"), quantity: String(updatedMyTokenOneSupply) },
    { unit: authenPolicyId + lpAssetName, quantity: String(remainingLiquidity) },
    { unit: authenPolicyId + poolAuthAssetName, quantity: "1" },
])
    .txOutInlineDatumValue(poolDatum)
    // global settings utxo ref
    .readOnlyTxInReference(globalSettingsUtxo.input.txHash, globalSettingsUtxo.input.outputIndex)
    .txInCollateral(wallet1Collateral.input.txHash, wallet1Collateral.input.outputIndex, wallet1Collateral.output.amount, wallet1Collateral.output.address)
    .invalidBefore(invalidBefore)
    .invalidHereafter(invalidAfter)
    // transaction must be executed by authorized batcher, wallet1VK
    .requiredSignerHash(wallet1VK)
    .changeAddress(wallet1Address)
    .selectUtxosFrom(wallet1Utxos)
    .setFee("3491809")
    .complete();
const signedTx = await wallet1.signTx(unsignedTx);
const txHash = await wallet1.submitTx(signedTx);
console.log("pool batching tx hash:", txHash);
