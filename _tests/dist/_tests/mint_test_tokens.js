import blueprint from "./always_success_mint/plutus.json" with { type: "json" };
import { applyParamsToScript } from "@meshsdk/core-csl";
import { resolveScriptHash, stringToHex } from "@meshsdk/core";
// Always success mint validator
const alwaysSuccessMintValidator = blueprint.validators.filter(v => (v.title.includes("placeholder.placeholder.mint")));
export const alwaysSuccessValidatorMintScript = applyParamsToScript(alwaysSuccessMintValidator[0].compiledCode, [], "JSON");
export const alwaysSuccessMintValidatorHash = resolveScriptHash(alwaysSuccessValidatorMintScript, "V3");
// Change token name below to mint any token
const tokenName = "iMyTokenTwo";
const tokenNameHex = stringToHex(tokenName);
// const unsignedTx = await txBuilder
//     .mintPlutusScriptV3()
//     .mint("3000", alwaysSuccessMintValidatorHash, tokenNameHex)
//     .mintingScript(alwaysSuccessValidatorMintScript)
//     .mintRedeemerValue("")
//     .txInCollateral(
//         wallet1Collateral.input.txHash,
//         wallet1Collateral.input.outputIndex,
//         wallet1Collateral.output.amount,
//         wallet1Collateral.output.address,
//     )
//     .changeAddress(wallet1Address)
//     .selectUtxosFrom(wallet1Utxos)
//     .complete()
// const signedTx = await wallet1.signTx(unsignedTx);
// const txHash = await wallet1.submitTx(signedTx);
// console.log(`Mint ${tokenName} tx hash:`, txHash);
