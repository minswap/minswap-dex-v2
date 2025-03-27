import { orderCanclValidatorRewardAddress, orderValidatorRewardAddress, poolBatchingValidatorRewardAddress, poolValidatorRewardAddress, txBuilder, wallet1, wallet1Address, wallet1Utxos } from "./setup.js";

// withdraw zero setup (register all stake cert) - Merged
const unsignedTx = await txBuilder
    .registerStakeCertificate(orderValidatorRewardAddress)
    // .registerStakeCertificate(orderCanclValidatorRewardAddress)
    .registerStakeCertificate(poolValidatorRewardAddress)
    .registerStakeCertificate(poolBatchingValidatorRewardAddress)
    .selectUtxosFrom(wallet1Utxos)
    .changeAddress(wallet1Address)
    .complete();
const signedTx = await wallet1.signTx(unsignedTx);
const txHash = await wallet1.submitTx(signedTx);
console.log("register all stake certificate tx hash:", txHash);


// withdraw zero setup (register order validator stake cert)
// const unsignedTx = await txBuilder
//     .registerStakeCertificate(orderValidatorRewardAddress)
//     .selectUtxosFrom(wallet1Utxos)
//     .changeAddress(wallet1Address)
//     .complete();
// const signedTx = await wallet1.signTx(unsignedTx);
// const txHash = await wallet1.submitTx(signedTx);
// console.log("register order stake certificate tx hash:", txHash);


// register order cancellation validator stake key
// const unsignedTx = await txBuilder
//     .registerStakeCertificate(orderCanclValidatorRewardAddress)
//     .selectUtxosFrom(wallet1Utxos)
//     .changeAddress(wallet1Address)
//     .complete();
// const signedTx = await wallet1.signTx(unsignedTx);
// const txHash = await wallet1.submitTx(signedTx);
// console.log("register order cancel stake certificate tx hash:", txHash);


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
