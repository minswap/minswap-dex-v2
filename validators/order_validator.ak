use aiken/list
use aiken/transaction.{Input, Output, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use amm_dex_v2/types.{
  ApplyOrder, CancelOrder, OrderDatum, OrderRedeemer, ValidatorHash,
}

validator(pool_hash: ValidatorHash) {
  fn validate_order(raw_datum: Data, raw_redeemer: Data, context: ScriptContext) {
    let ScriptContext { transaction, purpose } = context
    expect Spend(_) = purpose
    expect redeemer: OrderRedeemer = raw_redeemer
    when redeemer is {
      ApplyOrder -> {
        let Transaction { inputs, .. } = transaction
        // TODO: Consider this line
        when
          list.filter(
            inputs,
            fn(i) {
              let Input {
                output: Output {
                  address: Address { payment_credential, .. },
                  ..
                },
                ..
              } = i
              when payment_credential is {
                ScriptCredential(hash) -> pool_hash == hash
                _ -> False
              }
            },
          )
        is {
          [] -> False
          _ -> True
        }
      }
      CancelOrder -> {
        let Transaction { extra_signatories, .. } = transaction
        expect order_datum: OrderDatum = raw_datum
        let OrderDatum { sender: Address { payment_credential, .. }, .. } =
          order_datum
        expect VerificationKeyCredential(owner_pkh) = payment_credential
        list.has(extra_signatories, owner_pkh)
      }
    }
  }
}
