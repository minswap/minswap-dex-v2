import { stringToHex } from "@meshsdk/core";
import { alwaysSuccessMintValidatorHash, alwaysSuccessValidatorMintScript, txBuilder, wallet1, wallet1Address, wallet1Collateral, wallet1Utxos } from "./setup.js";
// Change token name below to mint any token
// const tokenName = "iMyTokenTwo";
const tokenName = "myTokenOne";
const tokenNameHex = stringToHex(tokenName);
const unsignedTx = await txBuilder
    .mintPlutusScriptV3()
    .mint("10000", alwaysSuccessMintValidatorHash, tokenNameHex)
    .mintingScript(alwaysSuccessValidatorMintScript)
    .mintRedeemerValue("")
    .txInCollateral(wallet1Collateral.input.txHash, wallet1Collateral.input.outputIndex, wallet1Collateral.output.amount, wallet1Collateral.output.address)
    .changeAddress(wallet1Address)
    .selectUtxosFrom(wallet1Utxos)
    .complete();
const signedTx = await wallet1.signTx(unsignedTx);
const txHash = await wallet1.submitTx(signedTx);
console.log(`Mint ${tokenName} tx hash:`, txHash);
