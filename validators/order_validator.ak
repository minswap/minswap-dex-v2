use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list
use aiken/transaction.{
  Input, Output, ScriptContext, Spend, Transaction, WithdrawFrom,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, StakeCredential, VerificationKeyCredential,
}
use amm_dex_v2/order_validation
use amm_dex_v2/types.{
  ApplyOrder, CancelExpiredOrderByAnyone, CancelOrderByOwner,
  OrderBatchingRedeemer, OrderDatum, OrderRedeemer, ValidatorHash,
}
use amm_dex_v2/utils

validator(
  // the Stake Credential of Order Batching Validator
  batching_withdrawal_cred: StakeCredential,
  expired_order_withdrawal_cred: StakeCredential,
) {
  fn validate_order(raw_datum: Data, raw_redeemer: Data, context: ScriptContext) {
    let ScriptContext { transaction, purpose } = context
    expect Spend(_) = purpose
    expect redeemer: OrderRedeemer = raw_redeemer
    when redeemer is {
      ApplyOrder -> {
        let Transaction { withdrawals, .. } = transaction
        // validate that an Order can be spent if there's a `Order Batching` validator in the `withdrawals`
        dict.has_key(withdrawals, batching_withdrawal_cred)
      }
      CancelOrderByOwner -> {
        let Transaction { inputs, extra_signatories, .. } = transaction
        expect order_datum: OrderDatum = raw_datum
        let OrderDatum {
          sender: Address { payment_credential: owner_payment_credential, .. },
          ..
        } = order_datum
        // validate that the transaction has _sender_'s signature or _sender_ script UTxO in the Transaction Inputs
        when owner_payment_credential is {
          VerificationKeyCredential(owner_pkh) ->
            // Verify transaction must be signed by Owner
            list.has(extra_signatories, owner_pkh)
          ScriptCredential(_) ->
            // In case owner is script address, this script will require at least 1 owner UTxO in input
            // If owner UTxO has enough condition to unlock itself, it can unlock this script as well
            list.any(
              inputs,
              fn(input) {
                let Input { output, .. } = input
                let Output { address: out_address, .. } = output
                let Address { payment_credential: out_payment_credential, .. } =
                  out_address
                out_payment_credential == owner_payment_credential
              },
            )
        }
      }
      CancelExpiredOrderByAnyone -> {
        let Transaction { withdrawals, .. } = transaction
        // validate that an Order can be spent if there's a `Expired Order Cancelling` validator in the `withdrawals`
        dict.has_key(withdrawals, expired_order_withdrawal_cred)
      }
    }
  }
}

// This validator will be used in Batching transaction.
// It will make sure that Pool contract is presented in the Transaction Input
// The rest validation logic is forwared to Pool Contract
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

// This validator will be used in cancelling Expired Orders transaction.
// It only allows PubKey Address can trigger the cancel
validator {
  fn validate_expired_order_cancelling(
    _raw_redeemer: Data,
    context: ScriptContext,
  ) -> Bool {
    expect ScriptContext { transaction, purpose: WithdrawFrom(_) } = context

    let Transaction { inputs, outputs, redeemers, validity_range, datums, .. } =
      transaction
    // Assume all script inputs are order scripts.
    // All scripts that have the same Order Datum structure will be accepted in this transaction.
    let order_inputs =
      list.filter(
        inputs,
        fn(input) {
          let Input {
            output: Output {
              address: Address { payment_credential: payment_cred, .. },
              ..
            },
            ..
          } = input
          when payment_cred is {
            ScriptCredential(_) -> True
            _ -> False
          }
        },
      )

    let orders_input_length = list.length(order_inputs)
    let outputs_length = list.length(outputs)
    let redeemers_list = dict.to_list(redeemers)
    expect and {
        // Redeemers contains a Withdrawal element, so we subtract 1 here
        orders_input_length == dict.size(redeemers) - 1,
        outputs_length >= orders_input_length,
        list.all(
          redeemers_list,
          fn(r) {
            let (pp, redeemer) = r
            when pp is {
              Spend(_) -> {
                expect x: OrderRedeemer = redeemer
                x == CancelExpiredOrderByAnyone
              }
              _ -> True
            }
          },
        ),
      }
    let Interval {
      lower_bound: IntervalBound { bound_type: lower_bound_type, .. },
      ..
    } = validity_range
    expect Finite(start_valid_time_range) = lower_bound_type
    order_validation.validate_cancel_expired_orders(
      order_inputs: order_inputs,
      all_outputs: outputs,
      datum_map: datums,
      start_valid_time_range: start_valid_time_range,
    )
  }
}
