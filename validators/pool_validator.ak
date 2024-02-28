use aiken/builtin
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/transaction.{
  Input, Output, ScriptContext, Spend, Transaction, WithdrawFrom,
}
use aiken/transaction/credential.{Address, Credential}
use aiken/transaction/value.{PolicyId}
use amm_dex_v2/order_validation
use amm_dex_v2/pool_validation
use amm_dex_v2/types.{
  Batching, BatchingPool, OrderDatum, PoolBatchingRedeemer, PoolDatum,
  PoolRedeemer, SwapMultiRouting, SwapRouting, UpdatePoolFeeOrStakeCredential,
  WithdrawLiquidityShare,
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
      UpdatePoolFeeOrStakeCredential(action) -> {
        let Transaction {
          inputs,
          reference_inputs,
          outputs,
          redeemers,
          mint,
          withdrawals,
          extra_signatories,
          validity_range,
          ..
        } = transaction
        expect Some(pool_input) = transaction.find_input(inputs, pool_input_ref)
        and {
          // Transaction requires admin token to execute
          pool_validation.is_admin_existence(
            admin_policy_id: utils.admin_policy_id,
            reference_inputs: reference_inputs,
            withdrawals: withdrawals,
            signatories: extra_signatories,
            validity_range: validity_range,
          ),
          // Transaction contain only 1 Spending Script (Pool Script). 
          // It will avoid bad Admin can steal money from Order Contract.
          pool_validation.has_single_spending(redeemers),
          // This Redeemer won't mint anything 
          value.is_zero(value.from_minted_value(mint)),
          pool_validation.validate_update_pool_datum_or_stake_credential(
            action: action,
            authen_policy_id: authen_policy_id,
            pool_input: pool_input,
            pool_in_datum: datum,
            all_outputs: outputs,
          ),
        }
      }
      WithdrawLiquidityShare -> {
        let Transaction {
          inputs,
          reference_inputs,
          outputs,
          redeemers,
          mint,
          withdrawals,
          extra_signatories,
          validity_range,
          ..
        } = transaction
        expect Some(pool_input) = transaction.find_input(inputs, pool_input_ref)
        and {
          // Transaction requires admin token to execute
          pool_validation.is_admin_existence(
            admin_policy_id: utils.admin_policy_id,
            reference_inputs: reference_inputs,
            withdrawals: withdrawals,
            signatories: extra_signatories,
            validity_range: validity_range,
          ),
          // Transaction contain only 1 Spending Script (Pool Script). 
          // It will avoid bad Admin can steal money from Order Contract.
          pool_validation.has_single_spending(redeemers),
          // This Redeemer won't mint anything 
          value.is_zero(value.from_minted_value(mint)),
          pool_validation.validate_withdraw_liquidity_share(
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
    let Transaction { inputs, outputs, datums, validity_range, mint, .. } =
      transaction
    let PoolBatchingRedeemer {
      license_index,
      orders_fee,
      input_indexes,
      pool_input_indexes_opt,
      vol_fees,
    } = redeemer
    // Batching Redeemer provides @license_index which help save calculation cost
    let license_input = utils.list_at_index(inputs, license_index)
    // A valid license token is the token having expired timestamp as TokenName and must be within current time and current time + _maximum_deadline_range_
    let (batcher_address, end_valid_time_range) =
      pool_validation.validate_license_expiration_and_find_license_holder(
        license_pid: utils.batcher_license_policy_id,
        license_input: license_input,
        validity_range: validity_range,
      )
    expect and {
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

    let user_inputs =
      list.filter(
        inputs,
        fn(input) {
          let Input { output: out, .. } = input
          let Output { address: addr, .. } = out
          let Address { payment_credential: payment_cred, .. } = addr
          addr != batcher_address && payment_cred != pool_payment_cred
        },
      )
    // Currently, transaction inputs will be sorted by TxId and TxIndex of UTxO.
    // We have to calculate indexes of orders inputs sorting by the ASC created time
    // on the off-chain and on-chain will sort the TxIns by the indexes
    // Input Indexes in parameter will be reversed indexs of @order_inputs to reduce calculate step in On-Chain
    let sorted_user_inputs =
      bytearray.foldl(
        input_indexes,
        [],
        fn(idx, ips) { list.push(ips, utils.list_at_index(user_inputs, idx)) },
      )

    // Order Outputs are Outputs which aren't Pool & Batcher UTxOs
    // Their ordering must be the same with @sorted_order_inputs, so @order_outputs at index i is the output if @sorted_order_inputs at index i
    let user_outputs =
      list.filter(
        outputs,
        fn(output) {
          let Output { address: addr, .. } = output
          let Address { payment_credential: payment_cred, .. } = addr
          addr != batcher_address && payment_cred != pool_payment_cred
        },
      )

    expect and {
        // User Inputs and Input Indexes must have the same length
        builtin.length_of_bytearray(input_indexes) == list.length(user_inputs),
        // Pool Inputs & Outputs must have the same length
        utils.compare_list_length(pool_inputs, pool_outputs),
      }

    when pool_inputs is {
      [pool_input] -> {
        // In case transaction only contains 1 Pool Input & Output, all order types are accepted except SwapMultiRouting
        expect [pool_output] = pool_outputs
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
          end_valid_time_range: end_valid_time_range,
          order_inputs: sorted_user_inputs,
          order_outputs: user_outputs,
          orders_fee: orders_fee,
          pool_state: pool_state_in,
        )
      }
      [] -> False
      _ -> {
        // In case transaction only contains more than 1 Pool Input & Output, only single SwapMultiRouting Order is accepted
        expect [order_input] = sorted_user_inputs
        expect [order_output] = user_outputs
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
          receiver,
          receiver_datum,
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
              receiver: receiver,
              receiver_datum: receiver_datum,
              output: order_output,
            ),
            // In case expired setting is turned on, the execution time must not exceed the expired_time
            when expiry_setting_opt is {
              None -> True
              Some((expired_time, _)) -> end_valid_time_range <= expired_time
            },
            // Order LP Asset must be the first LP Asset on the routing config
            order_lp_asset == first_routing_lp_asset,
            // minimum_receive must be positive
            minimum_receive > 0,
            // The number of Pool Inputs and Pool Outputs must be the same with _routings_ length
            utils.compare_list_length(pool_inputs, routings),
            // Pool Input Indexes must be unique
            utils.is_unique_bytearray_unsorted(pool_input_indexes),
          }
        let sorted_pool_inputs =
          bytearray.foldl(
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
