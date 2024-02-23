use aiken/hash.{Blake2b_224, Hash}
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, Spend, Transaction, WithdrawFrom,
}
use aiken/transaction/credential.{Address, Inline, VerificationKey}
use aiken/transaction/value
use amm_dex_v2/types.{Asset}

type MultiSignDatum {
  pub_key_hashes: List<Hash<Blake2b_224, VerificationKey>>,
}

validator(admin: Asset) {
  fn withdraw(_redeemer: Data, context: ScriptContext) {
    expect ScriptContext {
      transaction: Transaction { reference_inputs, extra_signatories, .. },
      purpose: WithdrawFrom(stake_cred),
    } = context
    let admin_input_opt =
      list.find(
        reference_inputs,
        fn(input) {
          let Input { output: Output { value: val, .. }, .. } = input
          value.quantity_of(val, admin.policy_id, admin.asset_name) == 1
        },
      )
    expect Some(admin_input) = admin_input_opt
    expect Input {
      output: Output {
        address: Address { payment_credential: payment_cred, .. },
        datum: InlineDatum(raw_datum),
        ..
      },
      ..
    } = admin_input
    expect stake_cred == Inline(payment_cred)
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
