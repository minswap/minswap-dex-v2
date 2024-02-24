use aiken/builtin
use aiken/list
use aiken/transaction.{ScriptContext, Spend, Transaction}
use aiken/transaction/value.{PolicyId}
use amm_dex_v2/pool_validation
use amm_dex_v2/types.{
  Batching, MultiRouting, PoolDatum, PoolRedeemer,
  UpdatePoolFeeOrStakeCredential, WithdrawLiquidityShare,
}
use amm_dex_v2/utils

validator(
  // The PolicyID of Authen Minting Policy
  authen_policy_id: PolicyId,
) {
  fn validate_pool(
    raw_datum: Data,
    redeemer: PoolRedeemer,
    context: ScriptContext,
  ) {
    expect ScriptContext { transaction, purpose: Spend(pool_input_ref) } =
      context
    when redeemer is {
      Batching(input_indexes, orders_fee, license_index) -> {
        expect datum: PoolDatum = raw_datum
        let Transaction { inputs, outputs, datums, validity_range, mint, .. } =
          transaction
        // Batching Redeemer provides @license_index which help save calculation cost
        let license_input = utils.list_at_index(inputs, license_index)
        // A valid license token is the token having expired timestamp as TokenName and must be within current time and current time + _maximum_deadline_range_
        let (batcher_address, end_valid_time_range) =
          pool_validation.validate_license_expiration_and_find_license_holder(
            license_pid: utils.batcher_license_policy_id,
            license_input: license_input,
            validity_range: validity_range,
          )
        and {
          // Input indexes must not be empty list
          !builtin.null_list(input_indexes),
          // Input indexes must be unique
          utils.is_list_unique(input_indexes),
          // Batcher need to provide all Batcher fee for each order
          utils.compare_list_length(input_indexes, orders_fee),
          // validate Transaction won't mint any assets
          value.is_zero(value.from_minted_value(mint)),
          pool_validation.validate_batching(
            authen_policy_id: authen_policy_id,
            all_inputs: inputs,
            all_outputs: outputs,
            all_datums: datums,
            pool_input_ref: pool_input_ref,
            pool_in_datum: datum,
            batcher_address: batcher_address,
            end_valid_time_range: end_valid_time_range,
            input_indexes: input_indexes,
            orders_fee: orders_fee,
          ),
        }
      }
      MultiRouting(
        license_index,
        routing_in_indexes,
        routing_out_indexes,
        order_fee,
      ) -> {
        let routing_in_indexes_len = list.length(routing_in_indexes)
        let routing_out_indexes_len = list.length(routing_out_indexes)
        // validate routing_in_indexes and routing_out_indexes must be unique, 
        // have the same length and contain more than 1 element.
        expect and {
            routing_in_indexes_len == routing_out_indexes_len,
            routing_out_indexes_len >= 2,
            utils.is_list_unique(routing_in_indexes),
            utils.is_list_unique(routing_out_indexes),
          }
        let Transaction { inputs, outputs, datums, validity_range, mint, .. } =
          transaction
        // Batching Redeemer provides @license_index which help save calculation cost
        let license_input = utils.list_at_index(inputs, license_index)
        let (batcher_address, end_valid_time_range) =
          pool_validation.validate_license_expiration_and_find_license_holder(
            license_pid: utils.batcher_license_policy_id,
            license_input: license_input,
            validity_range: validity_range,
          )
        and {
          // validate Transaction won't mint any assets
          value.is_zero(value.from_minted_value(mint)),
          pool_validation.validate_swap_multi_routing(
            authen_policy_id: authen_policy_id,
            all_inputs: inputs,
            all_outputs: outputs,
            all_datums: datums,
            pool_input_ref: pool_input_ref,
            batcher_address: batcher_address,
            end_valid_time_range: end_valid_time_range,
            routing_in_indexes: routing_in_indexes,
            routing_out_indexes: routing_out_indexes,
            order_fee: order_fee,
          ),
        }
      }
      UpdatePoolFeeOrStakeCredential(action) -> {
        expect datum: PoolDatum = raw_datum
        let Transaction {
          inputs,
          reference_inputs,
          outputs,
          datums,
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
            all_datums: datums,
          ),
        }
      }
      WithdrawLiquidityShare -> {
        expect datum: PoolDatum = raw_datum
        let Transaction {
          inputs,
          reference_inputs,
          outputs,
          datums,
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
            all_datums: datums,
          ),
        }
      }
    }
  }
}
