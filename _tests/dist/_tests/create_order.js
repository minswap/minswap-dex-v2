import { mConStr0, mConStr1, mPubKeyAddress } from "@meshsdk/core";
import { authenPolicyId, orderValidatorAddress, txBuilder, wallet1, wallet1Address, wallet1Collateral, wallet1SK, wallet1Utxos, wallet1VK } from "./setup.js";
const orderStep = mConStr0([
    mConStr1([]), // True
    mConStr0([20]),
    20,
    mConStr1([]), // True
]);
const orderDatum = mConStr0([
    mConStr0([wallet1VK]),
    mPubKeyAddress(wallet1VK, wallet1SK),
    mConStr0([]),
    mPubKeyAddress(wallet1VK, wallet1SK),
    mConStr0([]),
    mConStr0([
        authenPolicyId, // policy id
        "my_asset" // asset name
    ]), // template lp_asset (just for an order to cancel) <=== To be editted when submitting a real order
    orderStep,
    10,
    mConStr0([[(Date.now() + (10 * 60 * 1000)), 0]]), // 10 mins exp time; tip 0
]);
const unsignedTx = await txBuilder
    .txOut(orderValidatorAddress, [{ unit: "lovelace", quantity: "120000000" }])
    .txOutInlineDatumValue(orderDatum)
    .txInCollateral(wallet1Collateral.input.txHash, wallet1Collateral.input.outputIndex, wallet1Collateral.output.amount, wallet1Collateral.output.address)
    .changeAddress(wallet1Address)
    .selectUtxosFrom(wallet1Utxos)
    .complete();
const signedTx = await wallet1.signTx(unsignedTx);
const txHash = await wallet1.submitTx(signedTx);
console.log("Create order tx hash:", txHash);
