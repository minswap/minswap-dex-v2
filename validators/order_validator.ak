use aiken/list
use aiken/transaction.{Input, Output, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use amm_dex_v2/types.{
  ApplyOrder, CancelOrder, OrderDatum, OrderRedeemer, ValidatorHash,
}

validator(pool_hash: ValidatorHash) {
  fn validate_order(
    raw_datum: Data,
    redeemer: OrderRedeemer,
    context: ScriptContext,
  ) {
    let ScriptContext { transaction, purpose } = context
    let Transaction { inputs, extra_signatories, .. } = transaction
    expect Spend(_) = purpose
    when redeemer is {
      ApplyOrder -> {
        let has_one_pool_input =
          list.length(
            list.filter(
              inputs,
              fn(i) {
                let Input { output, .. } = i
                let Output { address, .. } = output
                let Address { payment_credential, .. } = address
                when payment_credential is {
                  ScriptCredential(hash) -> pool_hash == hash
                  _ -> False
                }
              },
            ),
          ) == 1
        has_one_pool_input
      }
      CancelOrder -> {
        expect order_datum: OrderDatum = raw_datum
        let OrderDatum { sender, .. } = order_datum
        let Address { payment_credential, .. } = sender
        expect VerificationKeyCredential(owner_pkh) = payment_credential
        list.has(extra_signatories, owner_pkh)
      }
    }
  }
}
