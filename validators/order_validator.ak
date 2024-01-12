use aiken/builtin
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
  ApplyOrder, CancelExpiredOrderByAnyone, CancelOrderByOwner, OrderDatum,
  OrderRedeemer, ValidatorHash,
}

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
        let Transaction { withdrawals, .. } = transaction
        // validate that an Order can be spent if there's a `Order Batching` validator in the `withdrawals`
        dict.has_key(withdrawals, stake_credential)
      }
    }
  }
}

validator(
  // the hash of Liquidity Pool Script
  pool_hash: ValidatorHash,
) {
  fn validate_order_spending_in_batching(
    _redeemer: Data,
    context: ScriptContext,
  ) -> Bool {
    expect ScriptContext { transaction, purpose: WithdrawFrom(_) } = context
    let Transaction { inputs, outputs, validity_range, datums, .. } =
      transaction
    let having_pool =
      list.any(
        inputs,
        fn(input) {
          let Input {
            output: Output { address: Address { payment_credential, .. }, .. },
            ..
          } = input
          when payment_credential is {
            ScriptCredential(hash) -> hash == pool_hash
            _ -> False
          }
        },
      )
    if having_pool {
      True
    } else {
      let script_inputs =
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
      let first_script_input = script_inputs |> builtin.head_list

      let Input { output: Output { address: first_script_address, .. }, .. } =
        first_script_input
      expect [] =
        list.filter(
          script_inputs,
          fn(input) {
            let Input { output: Output { address, .. }, .. } = input
            first_script_address != address
          },
        )
      let Interval {
        lower_bound: IntervalBound { bound_type: lower_bound_type, .. },
        ..
      } = validity_range
      expect Finite(start_valid_time_range) = lower_bound_type
      order_validation.validate_cancel_expired_orders(
        order_inputs: script_inputs,
        all_outputs: outputs,
        datum_map: datums,
        start_valid_time_range: start_valid_time_range,
      )
    }
  }
}
