import { deserializeDatum, mConStr0, mConStr1, stringToHex } from "@meshsdk/core";
import { alwaysSuccessMintValidatorHash, alwaysSuccessValidatorScript, assetA, assetB, authenAddress, authenPolicyId, blockchainProvider, lpAssetName, orderLovelaceAmount, orderValidatorAddress, orderValidatorRewardAddress, orderValidatorScript, poolAuthAssetName, poolBatchingValidatorHash, poolBatchingValidatorRewardAddress, poolBatchingValidatorScript, poolValidatorAddress, poolValidatorRewardAddress, poolValidatorScript, remainingLiquidity, swapAmount, totalLiquidity, txBuilder, wallet1, wallet1Address, wallet1Collateral, wallet1Utxos, wallet1VK, wallet2, wallet2Address, wallet2Collateral, wallet2Utxos } from "./setup.js";

// withdraw zero setup (register pool validator stake cert)
// const unsignedTx = await txBuilder
//     .registerStakeCertificate(poolValidatorRewardAddress)
//     .selectUtxosFrom(wallet1Utxos)
//     .changeAddress(wallet1Address)
//     .complete();
// const signedTx = await wallet1.signTx(unsignedTx);
// const txHash = await wallet1.submitTx(signedTx);
// console.log("register pool stake certificate tx hash:", txHash);

// withdraw zero setup (register pool batching validator stake cert)
// const unsignedTx = await txBuilder
//     .registerStakeCertificate(poolBatchingValidatorRewardAddress)
//     .selectUtxosFrom(wallet1Utxos)
//     .changeAddress(wallet1Address)
//     .complete();
// const signedTx = await wallet1.signTx(unsignedTx);
// const txHash = await wallet1.submitTx(signedTx);
// console.log("register pool batching stake certificate tx hash:", txHash);

const poolUtxo = (await blockchainProvider.fetchAddressUTxOs(poolValidatorAddress))[0];
const orderUtxo = (await blockchainProvider.fetchAddressUTxOs(orderValidatorAddress))[0];
const globalSettingsUtxo = (await blockchainProvider.fetchAddressUTxOs(authenAddress))[0];

const usedBatcherFee = 3000000;
const poolBatchingRedeemer = mConStr0([
    0,
    [usedBatcherFee], // used_batcher_fee, first index: 3 ADA
    "0",
    mConStr1([]),
    [mConStr1([])] // [mConStr0([6])],
]);

// order output value
const orderLovelaceBalance = orderLovelaceAmount - usedBatcherFee;
const assetBAmount = 19; // pre-calculated/assumed off chain (just for testing)

// updated pool datum (calculated updated reserves based on A -> B order direction)
if (!poolUtxo.output.plutusData) {
    throw new Error("No datum in pool utxo");
}
const oldPoolDatum = deserializeDatum(poolUtxo.output.plutusData); // ideal way is to create a type for the datum to deserialize; this is just for testing
const updatedIMyTokenTwoSupply = oldPoolDatum.fields[4].int + swapAmount;
const updatedMyTokenOneSupply = oldPoolDatum.fields[5].int - assetBAmount ;
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

const unsignedTx = await txBuilder
    // spend order utxo
    .spendingPlutusScriptV3()
    .txIn(
        orderUtxo.input.txHash,
        orderUtxo.input.outputIndex,
        orderUtxo.output.amount,
        orderUtxo.output.address,
    )
    .txInScript(alwaysSuccessValidatorScript)
    .spendingReferenceTxInInlineDatumPresent()
    .spendingReferenceTxInRedeemerValue("")
    // withdraw script on order utxo
    .withdrawalPlutusScriptV3()
    .withdrawal(orderValidatorRewardAddress, "0")
    .withdrawalScript(orderValidatorScript)
    .withdrawalRedeemerValue(mConStr0([]))
    // spend pool utxo
    .spendingPlutusScriptV3()
    .txIn(
        poolUtxo.input.txHash,
        poolUtxo.input.outputIndex,
        poolUtxo.output.amount,
        poolUtxo.output.address,
    )
    .txInScript(alwaysSuccessValidatorScript)
    .spendingReferenceTxInInlineDatumPresent()
    .spendingReferenceTxInRedeemerValue("")
    // withdraw script on pool utxo
    .withdrawalPlutusScriptV3()
    .withdrawal(poolValidatorRewardAddress, "0")
    .withdrawalScript(poolValidatorScript)
    .withdrawalRedeemerValue(mConStr0([]))
    // pool batching withdrawal
    .withdrawalPlutusScriptV3()
    .withdrawal(poolBatchingValidatorRewardAddress, "0")
    .withdrawalScript(poolBatchingValidatorScript)
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
    .txInCollateral(
        wallet1Collateral.input.txHash,
        wallet1Collateral.input.outputIndex,
        wallet1Collateral.output.amount,
        wallet1Collateral.output.address,
    )
    // transaction must be executed by authorized batcher, wallet1VK
    .requiredSignerHash(wallet1VK)
    .changeAddress(wallet1Address)
    .selectUtxosFrom(wallet1Utxos)
    .complete();

const signedTx = await wallet1.signTx(unsignedTx);
const txHash = await wallet1.submitTx(signedTx);

console.log("pool batching tx hash:", txHash);
