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
  stake_credential: StakeCredential,
) {
  fn validate_order(raw_datum: Data, raw_redeemer: Data, context: ScriptContext) {
    let ScriptContext { transaction, purpose } = context
    expect Spend(_) = purpose
    expect redeemer: OrderRedeemer = raw_redeemer
    when redeemer is {
      ApplyOrder -> {
        let Transaction { withdrawals, .. } = transaction
        // validate that an Order can be spent if there's a `Order Batching` validator in the `withdrawals`
        dict.has_key(withdrawals, stake_credential)
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
            list.length(
              list.filter(
                inputs,
                fn(input) {
                  let Input { output, .. } = input
                  let Output { address: out_address, .. } = output
                  let Address { payment_credential: out_payment_credential, .. } =
                    out_address
                  out_payment_credential == owner_payment_credential
                },
              ),
            ) > 0
        }
      }
      CancelExpiredOrderByAnyone -> {
        let Transaction {
          inputs,
          outputs,
          redeemers,
          validity_range,
          fee,
          datums,
          ..
        } = transaction
        expect Spend(order_ref) = purpose
        expect Some(own_order_input) =
          list.find(
            inputs,
            fn(input) {
              let Input { output_reference: out_ref, .. } = input
              out_ref == order_ref
            },
          )
        let Input { output: Output { address: own_order_address, .. }, .. } =
          own_order_input
        let Address { payment_credential: own_order_payment_cred, .. } =
          own_order_address
        let order_inputs =
          list.filter(
            inputs,
            fn(input) {
              let Input { output: Output { address: addr, .. }, .. } = input
              let Address { payment_credential: payment_cred, .. } = addr
              when payment_cred is {
                ScriptCredential(_) -> {
                  expect payment_cred == own_order_payment_cred
                  True
                }
                VerificationKeyCredential(_) -> False
              }
            },
          )
        let orders_input_length = list.length(order_inputs)
        let outputs_length = list.length(outputs)
        let redeemers_list = dict.to_list(redeemers)
        expect and {
            orders_input_length == dict.size(redeemers),
            outputs_length >= orders_input_length,
            list.all(
              redeemers_list,
              fn(r) {
                let (_, redeemer) = r
                redeemer == raw_redeemer
              },
            ),
          }
        let Interval {
          lower_bound: IntervalBound { bound_type: lower_bound_type, .. },
          ..
        } = validity_range
        expect Finite(start_valid_time_range) = lower_bound_type

        // We need to consider this logic
        let weighted_tx_fee =
          utils.calculate_weighed_fee(fee: fee, num: orders_input_length)
        order_validation.validate_cancel_expired_orders(
          order_inputs: order_inputs,
          all_outputs: outputs,
          weighted_tx_fee: weighted_tx_fee,
          datum_map: datums,
          start_valid_time_range: start_valid_time_range,
        )
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
