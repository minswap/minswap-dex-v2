use aiken/builtin
use aiken/dict
use aiken/list
use aiken/transaction.{
  Input, Output, ScriptContext, Spend, Transaction, WithdrawFrom,
}
use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, StakeCredential,
}
use aiken/transaction/value
use amm_dex_v2/order_validation
use amm_dex_v2/types.{
  ApplyOrder, CancelExpiredOrderByAnyone, CancelOrderByOwner, OAMMintScript,
  OAMSignature, OAMSpendScript, OAMWithdrawScript, OrderDatum, OrderRedeemer,
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
        when canceller is {
          // In case the wallet is a PubKey, its signature is required 
          OAMSignature(pub_key_hash) ->
            list.has(extra_signatories, pub_key_hash)
          // In case the wallet is a Script and offer Spend method
          // its Utxo has to present in the transaction inputs
          OAMSpendScript(script_hash) -> {
            let canceller_credential = ScriptCredential(script_hash)
            !builtin.null_list(
              list.filter(
                inputs,
                fn(input) {
                  let Input { output, .. } = input
                  let Output { address: out_address, .. } = output
                  let Address { payment_credential: out_payment_credential, .. } =
                    out_address
                  out_payment_credential == canceller_credential
                },
              ),
            )
          }
          // In case the wallet is a Script and offer Withdrawal method
          // it has to make a withdrawal and present in transaction withdrawals
          OAMWithdrawScript(script_hash) -> {
            let credential = Inline(ScriptCredential(script_hash))
            dict.has_key(withdrawals, credential)
          }
          // In case the wallet is a Script and offer Minting method
          // it has to mint tokens that has defined policy id and present in transaction minting
          // Token's quantity must not be zero
          OAMMintScript(script_hash) -> {
            let fst_token_quantity =
              mint
                |> value.from_minted_value()
                |> value.tokens(script_hash)
                |> dict.to_list()
                |> builtin.head_list
                |> builtin.snd_pair
            fst_token_quantity != 0
          }
        }
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
