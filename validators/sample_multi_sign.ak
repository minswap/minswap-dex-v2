use aiken/hash.{Blake2b_224, Hash}
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, Spend, Transaction, WithdrawFrom,
}
use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, VerificationKey,
}

type MultiSignDatum {
  pub_key_hashes: List<Hash<Blake2b_224, VerificationKey>>,
}

validator {
  fn withdraw(_redeemer: Data, context: ScriptContext) {
    expect ScriptContext {
      transaction: Transaction { reference_inputs, extra_signatories, .. },
      purpose: WithdrawFrom(stake_credential),
    } = context
    expect Inline(own_cred) = stake_credential
    expect ScriptCredential(own_hash) = own_cred
    expect Some(multi_sign_input) =
      reference_inputs
        |> list.find(
             fn(input) {
               let Input {
                 output: Output {
                   address: Address { payment_credential: payment_cred, .. },
                   ..
                 },
                 ..
               } = input
               when payment_cred is {
                 ScriptCredential(hash) -> hash == own_hash
                 _ -> False
               }
             },
           )
    expect Input { output: Output { datum: InlineDatum(raw_datum), .. }, .. } =
      multi_sign_input
    expect ref_datum: MultiSignDatum = raw_datum
    list.all(ref_datum.pub_key_hashes, fn(h) { list.has(extra_signatories, h) })
  }

  fn spend(datum: MultiSignDatum, _redeemer: Data, context: ScriptContext) {
    expect ScriptContext {
      transaction: Transaction { extra_signatories, .. },
      purpose: Spend(_),
    } = context
    let MultiSignDatum { pub_key_hashes } = datum
    list.all(pub_key_hashes, fn(h) { list.has(extra_signatories, h) })
  }
}
