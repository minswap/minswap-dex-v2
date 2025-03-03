use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Address, Credential, Script}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}

pub type MultiSignDatum {
  pub_key_hashes: List<VerificationKeyHash>,
}

validator sample_multi_sign {
  withdraw(_redeemer: Data, own_cred: Credential, transaction: Transaction) {
    let Transaction { reference_inputs, extra_signatories, .. } = transaction
    expect Script(own_hash) = own_cred
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
                Script(hash) -> hash == own_hash
                _ -> False
              }
            },
          )
    expect Input { output: Output { datum: InlineDatum(raw_datum), .. }, .. } =
      multi_sign_input
    expect ref_datum: MultiSignDatum = raw_datum
    list.all(ref_datum.pub_key_hashes, fn(h) { list.has(extra_signatories, h) })
  }

  spend(
    datum: Option<MultiSignDatum>,
    _redeemer: Data,
    _o: OutputReference,
    transaction: Transaction,
  ) {
    let Transaction { extra_signatories, .. } = transaction
    expect Some(MultiSignDatum { pub_key_hashes }) = datum
    list.all(pub_key_hashes, fn(h) { list.has(extra_signatories, h) })
  }

  else(_) {
    fail
  }
}
