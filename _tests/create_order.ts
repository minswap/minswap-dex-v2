import { mConStr0, mConStr1, mPubKeyAddress, stringToHex } from "@meshsdk/core";
import { alwaysSuccessMintValidatorHash, authenPolicyId, lpAssetName, orderLovelaceAmount, orderValidatorAddress, swapAmount, txBuilder, wallet1, wallet1Address, wallet1Collateral, wallet1SK, wallet1Utxos, wallet1VK } from "./setup.js"

const orderStep = mConStr0([
    mConStr1([]), // True
    mConStr0([swapAmount]), // swap_amount_option
    18, // minimum_receive
    mConStr0([]), // False
]);
const orderDatum = mConStr0([
    mConStr0([wallet1VK]),
    mPubKeyAddress(wallet1VK, wallet1SK),
    mConStr0([]),
    mPubKeyAddress(wallet1VK, wallet1SK), // <-----------
    mConStr0([]),
    mConStr0([
        authenPolicyId, // policy id
        lpAssetName // asset name
    ]), // changes according to the related liquidity pool
    orderStep,
    6000000, // max_batcher_fee: 6 ADA
    mConStr1([]), // mConStr0([[(Date.now() + (10 * 60 * 1000)), 0]]), // 10 mins exp time; tip 0
]);

const unsignedTx = await txBuilder
    .txOut(
        orderValidatorAddress,
        [
            { unit: "lovelace", quantity: String(orderLovelaceAmount) }, // batcher fee is deducted from here
            { unit: alwaysSuccessMintValidatorHash + stringToHex("iMyTokenTwo"), quantity: String(swapAmount) }, // the asset A to swap for asset B using the pool asset in the order datum
        ]
    )
    .txOutInlineDatumValue(orderDatum)
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

console.log("Create order tx hash:", txHash);
