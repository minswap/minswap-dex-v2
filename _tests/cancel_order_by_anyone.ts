import { mConStr1, mConStr2, SLOT_CONFIG_NETWORK, unixTimeToEnclosingSlot } from "@meshsdk/core";
import { blockchainProvider, orderValidatorScript, orderValidatorAddress, txBuilder, wallet1, wallet1Address, wallet1Collateral, wallet1Utxos, wallet1VK, orderValidatorRewardAddress, orderValidatorScriptHash, orderCanclValidatorRewardAddress, orderCanclValidatorScript } from "./setup.js"

console.log("orderValidatorAddress:", orderValidatorAddress);
const orderUtxo = (await blockchainProvider.fetchAddressUTxOs(orderValidatorAddress))[0];
if (!orderUtxo) {
    throw new Error("order utxo not found!");
}
console.log("orderUtxo:", orderUtxo);

const invalidBefore = unixTimeToEnclosingSlot(
    (Date.now() - 15000),
    SLOT_CONFIG_NETWORK.preprod
)

console.log('\n', "expired time: 1738668722616");
console.log(" current time:", Date.now() - 15000, '\n');

const unsignedTx = await txBuilder
    .spendingPlutusScriptV3()
    .txIn(
        orderUtxo.input.txHash,
        orderUtxo.input.outputIndex,
        orderUtxo.output.amount,
        orderUtxo.output.address,
    )
    .txInScript(orderValidatorScript)
    .spendingReferenceTxInInlineDatumPresent()
    .spendingReferenceTxInRedeemerValue("")
    // withdraw zero (order validator)
    .withdrawalPlutusScriptV3()
    .withdrawal(orderValidatorRewardAddress, "0")
    .withdrawalScript(orderValidatorScript)
    .withdrawalRedeemerValue(mConStr2([]))
    // order cancellation validator withdrawal
    .withdrawalPlutusScriptV3()
    .withdrawal(orderCanclValidatorRewardAddress, "0")
    .withdrawalScript(orderCanclValidatorScript)
    .withdrawalRedeemerValue("")
    .txOut(wallet1Address, orderUtxo.output.amount)
    .txInCollateral(
        wallet1Collateral.input.txHash,
        wallet1Collateral.input.outputIndex,
        wallet1Collateral.output.amount,
        wallet1Collateral.output.address,
    )
    .invalidBefore(invalidBefore)
    .changeAddress(wallet1Address)
    .selectUtxosFrom(wallet1Utxos)
    .complete()

const signedTx = await wallet1.signTx(unsignedTx);
const txHash = await wallet1.submitTx(signedTx);

console.log("Cancel order by anyone tx hash:", txHash);
