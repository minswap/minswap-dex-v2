use aiken/dict
use aiken/list
use aiken/transaction.{
  Input, Output, ScriptContext, Spend, Transaction, WithdrawFrom,
}
use aiken/transaction/credential.{Address, ScriptCredential, StakeCredential}
use amm_dex_v2/order_validation
use amm_dex_v2/types.{
  ApplyOrder, CancelExpiredOrderByAnyone, CancelOrderByOwner, OrderDatum,
  OrderRedeemer,
}
use amm_dex_v2/utils

validator(
  // the Stake Credential of Pool Batching Validator
  pool_batching_credential: StakeCredential,
  // the Stake Credential of Expired Order Cancellation Validator
  expired_order_cancel_credential: StakeCredential,
) {
  fn validate_order(raw_datum: Data, raw_redeemer: Data, context: ScriptContext) {
    let ScriptContext { transaction, purpose } = context
    expect Spend(_) = purpose
    expect redeemer: OrderRedeemer = raw_redeemer
    when redeemer is {
      ApplyOrder -> {
        let Transaction { withdrawals, .. } = transaction
        // validate that an Order can be spent if there's a `Order Batching` validator in the `withdrawals`
        dict.has_key(withdrawals, pool_batching_credential)
      }
      CancelOrderByOwner -> {
        let Transaction { inputs, extra_signatories, withdrawals, mint, .. } =
          transaction
        expect order_datum: OrderDatum = raw_datum
        let OrderDatum { canceller, .. } = order_datum
        // Canceller can be one of 4 authorization methods
        utils.authorize_order_license(
          author: canceller,
          transaction_inputs: inputs,
          withdrawals: withdrawals,
          extra_signatories: extra_signatories,
          transaction_mint: mint,
        )
      }
      CancelExpiredOrderByAnyone -> {
        let Transaction { withdrawals, .. } = transaction
        // validate that an Order can be spent if there's a `Order Batching` validator in the `withdrawals`
        dict.has_key(withdrawals, expired_order_cancel_credential)
      }
    }
  }
}

validator {
  fn validate_expired_order_cancel(
    _redeemer: Data,
    context: ScriptContext,
  ) -> Bool {
    expect ScriptContext { transaction, purpose: WithdrawFrom(_) } = context
    let Transaction { inputs, outputs, validity_range, datums, .. } =
      transaction
    // Assume all script inputs are order scripts.
    // All scripts that have the same Order Datum structure will be accepted in this transaction.
    let order_inputs =
      list.filter(
        inputs,
        fn(input) {
          let Input {
            output: Output { address: Address { payment_credential, .. }, .. },
            ..
          } = input
          when payment_credential is {
            ScriptCredential(_) -> True
            _ -> False
          }
        },
      )

    let start_valid_time_range =
      utils.must_get_finite_start_validity(validity_range)
    order_validation.validate_cancel_expired_orders(
      order_inputs: order_inputs,
      all_outputs: outputs,
      datum_map: datums,
      start_valid_time_range: start_valid_time_range,
    )
  }
}
