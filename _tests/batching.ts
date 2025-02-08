import { txBuilder, wallet2, wallet2Address, wallet2Collateral, wallet2Utxos } from "./setup";

// wallet 2 acting as the batcher
const unsignedTx = await txBuilder
    .txInCollateral(
        wallet2Collateral.input.txHash,
        wallet2Collateral.input.outputIndex,
        wallet2Collateral.output.amount,
        wallet2Collateral.output.address,
    )
    .changeAddress(wallet2Address)
    .selectUtxosFrom(wallet2Utxos)
    .complete();

const signedTx = await wallet2.signTx(unsignedTx);
const txHash = await wallet2.submitTx(signedTx);

console.log("pool batching tx hash:", txHash);
