use aiken/collection/list
use aiken/collection/pairs
use amm_dex_v2/order_validation
use amm_dex_v2/types.{
  ApplyOrder, CancelExpiredOrderByAnyone, CancelOrderByOwner, OrderDatum,
  OrderRedeemer,
}
use amm_dex_v2/utils
use cardano/address.{Address, Credential, Script}
use cardano/transaction.{Input, Output, OutputReference, Transaction}

validator order_validator(
  // the Stake Credential of Pool Batching Validator
  pool_batching_credential: Credential,
  // the Stake Credential of Expired Order Cancellation Validator
  expired_order_cancel_credential: Credential,
) {
  // fn validate_order
  spend(
    raw_datum_opt: Option<OrderDatum>,
    raw_redeemer: Data,
    _own_ref: OutputReference,
    transaction: Transaction,
  ) {
    expect Some(order_datum) = raw_datum_opt
    expect redeemer: OrderRedeemer = raw_redeemer
    when redeemer is {
      ApplyOrder -> {
        let Transaction { withdrawals, .. } = transaction
        // validate that an Order can be spent if there's a `Order Batching` validator in the `withdrawals`
        pairs.has_key(withdrawals, pool_batching_credential)
      }
      CancelOrderByOwner -> {
        let Transaction { inputs, extra_signatories, withdrawals, mint, .. } =
          transaction
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
        pairs.has_key(withdrawals, expired_order_cancel_credential)
      }
    }
  }

  else(_) {
    fail
  }
}

validator validate_expired_order_cancel {
  withdraw(_redeemer: Data, _account: Credential, transaction: Transaction) {
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
            Script(_) -> True
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

  else(_) {
    fail
  }
}
