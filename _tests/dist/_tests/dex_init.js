import { mConStr0 } from "@meshsdk/core";
import { authenAddress, authenPolicyId, authenValidatorScript, blockchainProvider, dexInitParamTxHash, dexInitParamTxIndex, factoryAddress, factoryAssetName, globalSettingAssetName, txBuilder, wallet1, wallet1Address, wallet1Collateral, wallet1Utxos, wallet1VK } from "./setup.js";
const factoryNftUnit = authenPolicyId + factoryAssetName;
const factoryDatum = mConStr0([
    "00",
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00",
]);
const globalSettingNftUnit = authenPolicyId + globalSettingAssetName;
const poolAuthorizationMethod = mConStr0([wallet1VK]);
const globalSettingDatum = mConStr0([
    [poolAuthorizationMethod],
    poolAuthorizationMethod,
    poolAuthorizationMethod,
    poolAuthorizationMethod,
    poolAuthorizationMethod,
    poolAuthorizationMethod,
]);
const txInput = (await blockchainProvider.fetchUTxOs(dexInitParamTxHash, dexInitParamTxIndex))[0];
console.log("Authen policy ID:", authenPolicyId);
const unsignedTx = await txBuilder
    .txIn(txInput.input.txHash, txInput.input.outputIndex, txInput.output.amount, txInput.output.address)
    .mintPlutusScriptV3()
    .mint("1", authenPolicyId, globalSettingAssetName)
    .mintingScript(authenValidatorScript)
    .mintRedeemerValue(mConStr0([]))
    .mintPlutusScriptV3()
    .mint("1", authenPolicyId, factoryAssetName)
    .mintingScript(authenValidatorScript)
    .mintRedeemerValue(mConStr0([]))
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
