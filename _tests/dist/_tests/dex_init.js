import { mConStr0, mConStr1 } from "@meshsdk/core";
import { authenAddress, authenPolicyId, authenValidatorScript, factoryAddress, txBuilder, wallet1, wallet1Address, wallet1Collateral, wallet1Utxos, wallet1VK } from "./setup.js";
const factoryNftUnit = authenPolicyId + "4d5346";
const factoryDatum = mConStr0([
    "00",
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00",
]);
const globalSettingNftUnit = authenPolicyId + "4d534753";
const poolAuthorizationMethod = mConStr0([wallet1VK]);
const globalSettingDatum = mConStr0([
    [poolAuthorizationMethod],
    poolAuthorizationMethod,
    poolAuthorizationMethod,
    poolAuthorizationMethod,
    poolAuthorizationMethod,
    poolAuthorizationMethod,
]);
const unsignedTx = await txBuilder
    .mintPlutusScriptV3()
    .mint("1", authenPolicyId, "4d534753")
    .mintingScript(authenValidatorScript)
    .mintRedeemerValue(mConStr1([]))
    .mintPlutusScriptV3()
    .mint("1", authenPolicyId, "4d5346")
    .mintingScript(authenValidatorScript)
    .mintRedeemerValue(mConStr1([]))
    .txOut(factoryAddress, [{ unit: factoryNftUnit, quantity: "1" }])
    .txOutInlineDatumValue(factoryDatum)
    .txOut(authenAddress, [{ unit: globalSettingNftUnit, quantity: "1" }])
    .txOutInlineDatumValue(globalSettingDatum)
    .txInCollateral(wallet1Collateral.input.txHash, wallet1Collateral.input.outputIndex, wallet1Collateral.output.amount, wallet1Collateral.output.address)
    .changeAddress(wallet1Address)
    .selectUtxosFrom(wallet1Utxos)
    .complete();
const signedTx = await wallet1.signTx(unsignedTx);
const txHash = await wallet1.submitTx(signedTx);
console.log("Dex initialization tx hash:", txHash);
