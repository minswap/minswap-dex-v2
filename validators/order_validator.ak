use aiken/collection/list
use aiken/collection/pairs
use amm_dex_v2/order_validation
use amm_dex_v2/types.{
  ApplyOrder, CancelExpiredOrderByAnyone, CancelOrderByOwner, OrderDatum,
  OrderRedeemer,
}
use amm_dex_v2/utils
use cardano/address.{Address, Credential, Inline, Script}
use cardano/transaction.{Input,
  Output, OutputReference, Transaction, find_input}

validator order_validator(
  // the Stake Credential of Pool Batching Validator
  pool_batching_credential: Credential,
  // the Stake Credential of Expired Order Cancellation Validator
  expired_order_cancel_credential: Credential,
) {
  // fn validate_order
  spend(
    _raw_datum: Option<OrderDatum>,
    _raw_redeemer: Data,
    own_ref: OutputReference,
    transaction: Transaction,
  ) {
    let Transaction { inputs, withdrawals, .. } = transaction
    expect Some(own_input) = find_input(inputs, own_ref)
    expect Some(own_stake_cred) = own_input.output.address.stake_credential
    expect Inline(own_cred) = own_stake_cred
    withdrawals |> pairs.has_key(own_cred)
  }

  // fn validate_order & validate_expired_order_cancel
  withdraw(raw_redeemer: Data, account: Credential, transaction: Transaction) {
    let Transaction { inputs, outputs, validity_range, datums, .. } =
      transaction
    expect redeemer: OrderRedeemer = raw_redeemer
    expect Script(own_hash) = account

    // Assume all script inputs are order scripts.
    // All scripts that have the same Order Datum structure will be accepted in this transaction.
    let order_inputs =
      list.filter(
        inputs,
        fn(input) {
          let Input {
            output: Output {
              address: Address { payment_credential, stake_credential },
              ..
            },
            ..
          } = input
          or {
            Script(own_hash) == payment_credential,
            Some(Inline(Script(own_hash))) == stake_credential,
          }
        },
      )

    let start_valid_time_range =
      utils.must_get_finite_start_validity(validity_range)
    let cancel_expired_orders_validation =
      order_validation.validate_cancel_expired_orders(
        order_inputs: order_inputs,
        all_outputs: outputs,
        datum_map: datums,
        start_valid_time_range: start_valid_time_range,
      )

    when redeemer is {
      ApplyOrder -> {
        let Transaction { withdrawals, .. } = transaction
        and {
          // validate that an Order can be spent if there's a `Order Batching` validator in the `withdrawals`
          pairs.has_key(withdrawals, pool_batching_credential),
          cancel_expired_orders_validation,
        }
      }
      CancelOrderByOwner -> {
        let Transaction {
          inputs,
          extra_signatories,
          withdrawals,
          mint,
          datums,
          ..
        } = transaction
        // Check all order inputs for the condition below
        order_inputs
          |> list.all(
              fn(own_input) {
                let Input { output: Output { datum: own_input_datum, .. }, .. } =
                  own_input
                let order_datum =
                  utils.must_find_script_datum(datums, own_input_datum)
                expect OrderDatum { canceller, .. } = order_datum
                and {
                  // Canceller can be one of 4 authorization methods
                  utils.authorize_order_license(
                    author: canceller,
                    transaction_inputs: inputs,
                    withdrawals: withdrawals,
                    extra_signatories: extra_signatories,
                    transaction_mint: mint,
                  ),
                  cancel_expired_orders_validation,
                }
              },
            )
      }
      CancelExpiredOrderByAnyone -> {
        let Transaction { withdrawals, .. } = transaction
        and {
          // validate that an Order can be spent if there's a `Order Batching` validator in the `withdrawals`
          pairs.has_key(withdrawals, expired_order_cancel_credential),
          cancel_expired_orders_validation,
        }
      }
    }
  }

  else(_) {
    fail
  }
}
