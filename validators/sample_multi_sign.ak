use aiken/builtin
use aiken/hash.{Blake2b_224, Hash}
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, Spend, Transaction, WithdrawFrom,
}
use aiken/transaction/credential.{VerificationKey}

type MultiSignDatum {
  pub_key_hashes: List<Hash<Blake2b_224, VerificationKey>>,
}

validator {
  fn withdraw(_redeemer: Data, context: ScriptContext) {
    expect ScriptContext {
      transaction: Transaction { reference_inputs, extra_signatories, .. },
      purpose: WithdrawFrom(_),
    } = context
    let multi_sign_input =
      reference_inputs |> builtin.tail_list |> builtin.head_list
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
