use aiken/dict
use aiken/list
use aiken/transaction.{
  Input, Output, ScriptContext, Spend, Transaction, WithdrawFrom,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, StakeCredential, VerificationKeyCredential,
}
use amm_dex_v2/types.{
  ApplyOrder, CancelOrder, OrderBatchingRedeemer, OrderDatum, OrderRedeemer,
  ValidatorHash,
}
use amm_dex_v2/utils

validator(
  // the Stake Credential of Order Batching Validator
  stake_credential: StakeCredential,
) {
  fn validate_order(raw_datum: Data, raw_redeemer: Data, context: ScriptContext) {
    expect ScriptContext { transaction, purpose: Spend(_) } = context
    expect redeemer: OrderRedeemer = raw_redeemer
    when redeemer is {
      ApplyOrder -> {
        let Transaction { withdrawals, .. } = transaction
        // validate that an Order can be spent if there's a `Order Batching` validator in the `withdrawals`
        dict.has_key(withdrawals, stake_credential)
      }
      CancelOrder -> {
        let Transaction { extra_signatories, .. } = transaction
        expect order_datum: OrderDatum = raw_datum
        let OrderDatum { sender: Address { payment_credential, .. }, .. } =
          order_datum
        expect VerificationKeyCredential(owner_pkh) = payment_credential
        // validate that the transaction has _sender_'s signature or _sender_ script UTxO in the Transaction Inputs
        list.has(extra_signatories, owner_pkh)
      }
    }
  }
}

validator(
  // the hash of Liquidity Pool Script
  pool_hash: ValidatorHash,
) {
  fn validate_order_spending_in_batching(
    redeemer: OrderBatchingRedeemer,
    context: ScriptContext,
  ) -> Bool {
    expect ScriptContext { transaction, purpose: WithdrawFrom(_) } = context
    let OrderBatchingRedeemer { pool_input_index } = redeemer

    let Transaction { inputs, .. } = transaction
    let Input {
      output: Output { address: Address { payment_credential, .. }, .. },
      ..
    } = utils.list_at_index(inputs, pool_input_index)
    expect ScriptCredential(hash) = payment_credential
    // validate that there's a Pool Input which have Address's Payment Credential matching with `pool_hash`
    pool_hash == hash
  }
}
