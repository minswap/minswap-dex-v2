use aiken/builtin
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/transaction.{
  Input, Output, ScriptContext, Spend, Transaction, WithdrawFrom,
}
use aiken/transaction/credential.{
  Address, Credential, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{PolicyId}
use amm_dex_v2/order_validation
use amm_dex_v2/pool_validation
use amm_dex_v2/types.{
  Batching, BatchingPool, GlobalSetting, OrderDatum, PAMSignature,
  PAMSpendScript, PAMWithdrawScript, PoolBatchingRedeemer, PoolDatum,
  PoolRedeemer, SwapMultiRouting, SwapRouting, UpdateDynamicFee, UpdatePoolFee,
  UpdatePoolParameters, UpdatePoolStakeCredential, WithdrawFeeSharing,
}
use amm_dex_v2/utils

validator(
  // The PolicyID of Authen Minting Policy
  authen_policy_id: PolicyId,
) {
  fn validate_pool(
    datum: PoolDatum,
    redeemer: PoolRedeemer,
    context: ScriptContext,
  ) {
    expect ScriptContext { transaction, purpose: Spend(pool_input_ref) } =
      context
    when redeemer is {
      Batching -> {
        let Transaction { withdrawals, .. } = transaction
        let PoolDatum { pool_batching_stake_credential, .. } = datum
        dict.has_key(withdrawals, pool_batching_stake_credential)
      }
      UpdatePoolParameters(action) -> {
        let Transaction {
          inputs,
          reference_inputs,
          outputs,
          mint,
          withdrawals,
          extra_signatories,
          ..
        } = transaction
        expect Some(pool_input) = transaction.find_input(inputs, pool_input_ref)
        let Input { output: Output { address: pool_address, .. }, .. } =
          pool_input
        let global_setting =
          pool_validation.get_and_validate_global_setting(
            reference_inputs: reference_inputs,
            authen_policy_id: authen_policy_id,
          )
        let GlobalSetting {
          pool_fee_updater,
          pool_stake_key_updater,
          pool_dynamic_fee_updater,
          ..
        } = global_setting
        let authorizer =
          when action is {
            UpdatePoolFee -> pool_fee_updater
            UpdateDynamicFee -> pool_dynamic_fee_updater
            UpdatePoolStakeCredential -> pool_stake_key_updater
          }
        and {
          // Transaction must be executed by the correct authorizer
          utils.authorize_pool_license(
            author: authorizer,
            transaction_inputs: inputs,
            withdrawals: withdrawals,
            extra_signatories: extra_signatories,
          ),
          // Verify that the transaction spends only one Single Pool Script and does not contain any other scripts in its inputs, except for the Author, in cases where the Author is a script
          pool_validation.has_only_pool_and_author(
            inputs: inputs,
            pool_address: pool_address,
            pool_author: authorizer,
          ),
          // This Redeemer won't mint anything 
          value.is_zero(value.from_minted_value(mint)),
          pool_validation.validate_update_pool_parameters(
            action: action,
            authen_policy_id: authen_policy_id,
            pool_input: pool_input,
            pool_in_datum: datum,
            all_outputs: outputs,
          ),
        }
      }
      WithdrawFeeSharing -> {
        let Transaction {
          inputs,
          reference_inputs,
          outputs,
          mint,
          withdrawals,
          extra_signatories,
          ..
        } = transaction
        expect Some(pool_input) = transaction.find_input(inputs, pool_input_ref)
        let Input { output: Output { address: pool_address, .. }, .. } =
          pool_input
        let global_setting =
          pool_validation.get_and_validate_global_setting(
            reference_inputs: reference_inputs,
            authen_policy_id: authen_policy_id,
          )
        let GlobalSetting { fee_sharing_taker, .. } = global_setting
        and {
          // Transaction must be executed by the correct authorizer
          utils.authorize_pool_license(
            author: fee_sharing_taker,
            transaction_inputs: inputs,
            withdrawals: withdrawals,
            extra_signatories: extra_signatories,
          ),
          // Verify that the transaction spends only one Single Pool Script and does not contain any other scripts in its inputs, except for the Author, in cases where the Author is a script
          pool_validation.has_only_pool_and_author(
            inputs: inputs,
            pool_address: pool_address,
            pool_author: fee_sharing_taker,
          ),
          // This Redeemer won't mint anything 
          value.is_zero(value.from_minted_value(mint)),
          pool_validation.validate_withdraw_fee_sharing(
            authen_policy_id: authen_policy_id,
            pool_input: pool_input,
            pool_in_datum: datum,
            all_outputs: outputs,
          ),
        }
      }
    }
  }
}

validator(
  // The PolicyID of Authen Minting Policy
  authen_policy_id: PolicyId,
  // The Payment Credential of Pool Validator
  pool_payment_cred: Credential,
) {
  fn validate_pool_batching(
    redeemer: PoolBatchingRedeemer,
    context: ScriptContext,
  ) {
    expect ScriptContext {
      transaction,
      purpose: WithdrawFrom(stake_credential),
    } = context
    let Transaction {
      inputs,
      outputs,
      datums,
      validity_range,
      mint,
      reference_inputs,
      extra_signatories,
      withdrawals,
      ..
    } = transaction
    let PoolBatchingRedeemer {
      batcher_index,
      orders_fee,
      input_indexes,
      pool_input_indexes_opt,
      vol_fees,
    } = redeemer
    let global_setting =
      pool_validation.get_and_validate_global_setting(
        reference_inputs: reference_inputs,
        authen_policy_id: authen_policy_id,
      )
    let GlobalSetting { batchers, .. } = global_setting
    let current_time_approximation =
      utils.must_get_current_time_approximation(validity_range)

    // Due to authorized batchers is a list so we use @batcher_index to save the On-chain cost 
    // on searching the batcher address in this section 
    let batcher_address = utils.list_at_index(batchers, batcher_index)
    expect and {
        // Transaction must be executed by the authorized batchers
        utils.authorize_pool_license(
          author: batcher_address,
          transaction_inputs: inputs,
          withdrawals: withdrawals,
          extra_signatories: extra_signatories,
        ),
        // Input indexes must not be empty list and be unique
        utils.is_unique_bytearray_unsorted(input_indexes),
        // validate Transaction won't mint any assets
        value.is_zero(value.from_minted_value(mint)),
      }

    let pool_inputs =
      list.filter(
        inputs,
        fn(input) {
          let Input { output: Output { address: addr, .. }, .. } = input
          let Address { payment_credential: payment_cred, .. } = addr
          payment_cred == pool_payment_cred
        },
      )
    let pool_outputs =
      list.filter(
        outputs,
        fn(output) {
          let Output { address: addr, .. } = output
          let Address { payment_credential: payment_cred, .. } = addr
          payment_cred == pool_payment_cred
        },
      )

    // We assume that inputs not belonging to the batcher or liquidity pool are orders. 
    // These inputs' structure will be verified in the @apply_orders function and SwapMultiRouting branch. 
    // We do not force finding the order script hash here, as we allow for the possibility of upgrading the order contract (possibly to Plutus V3).
    let order_inputs =
      list.filter(
        inputs,
        fn(input) {
          let Input { output: out, .. } = input
          let Output { address: addr, .. } = out
          let Address { payment_credential: payment_cred, .. } = addr
          and {
            payment_cred != pool_payment_cred,
            when batcher_address is {
              PAMSignature(pkh) ->
                payment_cred != VerificationKeyCredential(pkh)
              PAMSpendScript(sh) -> payment_cred != ScriptCredential(sh)
              PAMWithdrawScript(sh) -> payment_cred != ScriptCredential(sh)
            },
          }
        },
      )
    // Currently, transaction inputs will be sorted by TxId and TxIndex of UTxO.
    // We have to calculate indexes of orders inputs sorting by the ASC created time
    // on the off-chain and on-chain will sort the TxIns by the indexes
    // Input Indexes in parameter will be the index indexes of @order_inputs
    let sorted_order_inputs =
      bytearray.foldr(
        input_indexes,
        [],
        fn(idx, ips) { list.push(ips, utils.list_at_index(order_inputs, idx)) },
      )

    expect and {
        // Order Inputs and Input Indexes must have the same length
        builtin.length_of_bytearray(input_indexes) == list.length(order_inputs),
        // Pool Inputs & Outputs must have the same length
        utils.compare_list_length(pool_inputs, pool_outputs),
      }

    when pool_inputs is {
      [pool_input] -> {
        // In case transaction only contains 1 Pool Input & Output, all order types are accepted except SwapMultiRouting
        let pool_output = pool_outputs |> builtin.head_list
        expect [vol_fee] = vol_fees
        let Input { output: pool_in_output, .. } = pool_input
        let BatchingPool {
          asset_a,
          asset_b,
          lp_asset,
          trading_fee_a_numerator,
          trading_fee_b_numerator,
          fee_sharing_numerator_opt,
          pool_state_in,
          pool_state_out,
        } =
          pool_validation.get_batching_pool(
            stake_credential: stake_credential,
            pool_input: pool_in_output,
            pool_output: pool_output,
            authen_policy_id: authen_policy_id,
            require_total_liquidity_unchange: False,
            vol_fee: vol_fee,
          )
        pool_state_out == order_validation.apply_orders(
          datum_map: datums,
          asset_a: asset_a,
          asset_b: asset_b,
          lp_asset: lp_asset,
          trading_fee_a_numerator: trading_fee_a_numerator,
          trading_fee_b_numerator: trading_fee_b_numerator,
          fee_sharing_numerator_opt: fee_sharing_numerator_opt,
          current_time_approximation: current_time_approximation,
          order_inputs: sorted_order_inputs,
          all_outputs: outputs,
          orders_fee: orders_fee,
          pool_state: pool_state_in,
        )
      }
      [] -> False
      _ -> {
        // In case transaction only contains more than 1 Pool Input & Output, only single SwapMultiRouting Order is accepted
        expect [order_input] = sorted_order_inputs
        let order_output = outputs |> builtin.head_list
        expect [order_fee] = orders_fee
        let Input {
          output: Output {
            value: order_in_value,
            datum: raw_order_in_datum,
            ..
          },
          ..
        } = order_input
        let Output { value: order_out_value, .. } = order_output
        expect order_in_datum: OrderDatum =
          utils.must_find_script_datum(datums, raw_order_in_datum)
        let OrderDatum {
          success_receiver,
          success_receiver_datum,
          step: order_step,
          max_batcher_fee,
          lp_asset: order_lp_asset,
          expiry_setting_opt,
          ..
        } = order_in_datum
        expect SwapMultiRouting(routings, swap_amount_option, minimum_receive) =
          order_step
        let SwapRouting { lp_asset: first_routing_lp_asset, .. } =
          routings |> builtin.head_list
        expect Some(pool_input_indexes) = pool_input_indexes_opt
        expect and {
            // max_batcher_fee must be positive
            max_batcher_fee > 0,
            // Used Batcher Fee must be positive and less than or equal batcher fee
            order_fee > 0,
            order_fee <= max_batcher_fee,
            // Order Output must be returned to receiver and might have receiver_datum
            order_validation.validate_order_receiver(
              receiver: success_receiver,
              receiver_datum: success_receiver_datum,
              output: order_output,
            ),
            // In case expired setting is turned on, the execution time must not exceed the expired_time
            when expiry_setting_opt is {
              None -> True
              Some((expired_time, _)) ->
                current_time_approximation <= expired_time
            },
            // Order LP Asset must be the first LP Asset on the routing config
            order_lp_asset == first_routing_lp_asset,
            // minimum_receive must be positive
            minimum_receive > 0,
            // The number of Pool Inputs and Pool Outputs must be the same with _routings_ length
            utils.compare_list_length(pool_inputs, routings),
            // Pool Input Indexes must be unique
            utils.is_unique_bytearray_unsorted(pool_input_indexes),
            // This contract allows the order routing through at most 3 Pools 
            builtin.length_of_bytearray(pool_input_indexes) <= 3,
          }
        let sorted_pool_inputs =
          bytearray.foldr(
            pool_input_indexes,
            [],
            fn(idx, ps) { list.push(ps, utils.list_at_index(pool_inputs, idx)) },
          )
        let batching_pools =
          utils.zip_with(
            sorted_pool_inputs,
            pool_outputs,
            vol_fees,
            fn(pool_in, pool_out, vol_fee) {
              let Input { output: pool_in_output, .. } = pool_in
              pool_validation.get_batching_pool(
                stake_credential: stake_credential,
                pool_input: pool_in_output,
                pool_output: pool_out,
                authen_policy_id: authen_policy_id,
                require_total_liquidity_unchange: True,
                vol_fee: vol_fee,
              )
            },
          )
        order_validation.validate_swap_multi_routing_order(
          pools: batching_pools,
          routings: routings,
          order_in_value: order_in_value,
          order_out_value: order_out_value,
          swap_amount_option: swap_amount_option,
          minimum_receive: minimum_receive,
          used_batcher_fee: order_fee,
        )
      }
    }
  }
}
