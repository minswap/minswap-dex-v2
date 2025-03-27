import { mConStr1 } from "@meshsdk/core";
import { blockchainProvider, orderValidatorScript, orderValidatorAddress, txBuilder, wallet1, wallet1Address, wallet1Collateral, wallet1Utxos, wallet1VK, orderValidatorRewardAddress, alwaysSuccessValidatorScript } from "./setup.js";
// console.log("orderValidatorAddress:", orderValidatorAddress);
const orderUtxo = (await blockchainProvider.fetchAddressUTxOs(orderValidatorAddress))[0];
if (!orderUtxo) {
    throw new Error("order utxo not found!");
}
// console.log("orderUtxo:", orderUtxo);
// order ref script
const orderScriptTxHash = "";
const orderScriptTxIndex = 0;
const unsignedTx = await txBuilder
    .spendingPlutusScriptV3()
    .txIn(orderUtxo.input.txHash, orderUtxo.input.outputIndex, orderUtxo.output.amount, orderUtxo.output.address)
    .txInScript(alwaysSuccessValidatorScript)
    // .txInScript(orderValidatorScript)
    .spendingReferenceTxInInlineDatumPresent()
    .spendingReferenceTxInRedeemerValue("")
    // withdraw zero
    .withdrawalPlutusScriptV3()
    .withdrawal(orderValidatorRewardAddress, "0")
    .withdrawalScript(orderValidatorScript)
    // .withdrawalTxInReference(orderScriptTxHash, orderScriptTxIndex, undefined, orderValidatorScriptHash)
    .withdrawalRedeemerValue(mConStr1([]))
    .txOut(wallet1Address, orderUtxo.output.amount)
    .txInCollateral(wallet1Collateral.input.txHash, wallet1Collateral.input.outputIndex, wallet1Collateral.output.amount, wallet1Collateral.output.address)
    .changeAddress(wallet1Address)
    .selectUtxosFrom(wallet1Utxos)
    .requiredSignerHash(wallet1VK)
    .complete();
const signedTx = await wallet1.signTx(unsignedTx);
const txHash = await wallet1.submitTx(signedTx);
console.log("Cancel order by owner tx hash:", txHash);
