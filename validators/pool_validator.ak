use aiken/builtin
use aiken/list
use aiken/transaction.{ScriptContext, Spend, Transaction}
use aiken/transaction/value.{AssetName, PolicyId}
use amm_dex_v2/pool_validation
use amm_dex_v2/types.{
  Batching, MultiRouting, PoolDatum, PoolRedeemer,
  UpdatePoolFeeOrStakeCredential, WithdrawLiquidityShare,
}

validator(
  authen_policy_id: PolicyId,
  license_policy_id: PolicyId,
  pool_auth_asset_name: AssetName,
  admin_asset_name: AssetName,
  maximum_deadline_range: Int,
) {
  fn validate_pool(
    datum: PoolDatum,
    redeemer: PoolRedeemer,
    context: ScriptContext,
  ) {
    let ScriptContext { transaction, purpose } = context
    expect Spend(pool_input_ref) = purpose
    when redeemer is {
      Batching(batcher_address, input_indexes, license_index) -> {
        expect license_index >= 0 && !builtin.null_list(input_indexes)
        let Transaction {
          inputs,
          outputs,
          datums,
          extra_signatories,
          validity_range,
          mint,
          ..
        } = transaction
        expect
          pool_validation.validate_common_batching(
            inputs: inputs,
            validity_range: validity_range,
            extra_signatories: extra_signatories,
            batcher_address: batcher_address,
            license_policy_id: license_policy_id,
            license_index: license_index,
            maximum_deadline_range: maximum_deadline_range,
            mint: mint,
          )
        pool_validation.validate_batching(
          authen_policy_id: authen_policy_id,
          pool_auth_asset_name: pool_auth_asset_name,
          all_inputs: inputs,
          all_outputs: outputs,
          all_datums: datums,
          pool_input_ref: pool_input_ref,
          pool_in_datum: datum,
          batcher_address: batcher_address,
          input_indexes: input_indexes,
        )
      }
      MultiRouting(
        batcher_address,
        license_index,
        routing_in_indexes,
        routing_out_indexes,
      ) -> {
        let routing_in_indexes_len = list.length(routing_in_indexes)
        let routing_out_indexes_len = list.length(routing_out_indexes)
        // TODO: Validate distinct indexes
        expect
          license_index >= 0 && routing_in_indexes_len == routing_out_indexes_len && routing_out_indexes_len >= 2
        let Transaction {
          inputs,
          outputs,
          datums,
          extra_signatories,
          validity_range,
          mint,
          ..
        } = transaction
        expect
          pool_validation.validate_common_batching(
            inputs: inputs,
            validity_range: validity_range,
            extra_signatories: extra_signatories,
            batcher_address: batcher_address,
            license_policy_id: license_policy_id,
            license_index: license_index,
            maximum_deadline_range: maximum_deadline_range,
            mint: mint,
          )
        pool_validation.validate_swap_multi_routing(
          authen_policy_id: authen_policy_id,
          pool_auth_asset_name: pool_auth_asset_name,
          all_inputs: inputs,
          all_outputs: outputs,
          all_datums: datums,
          pool_input_ref: pool_input_ref,
          batcher_address: batcher_address,
          routing_in_indexes: routing_in_indexes,
          routing_out_indexes: routing_out_indexes,
        )
      }
      UpdatePoolFeeOrStakeCredential(action, admin_index) -> {
        let Transaction { inputs, outputs, datums, redeemers, mint, .. } =
          transaction
        expect Some(pool_input) = transaction.find_input(inputs, pool_input_ref)
        pool_validation.validate_update_pool_datum_or_stake_credential(
          action: action,
          authen_policy_id: authen_policy_id,
          pool_auth_asset_name: pool_auth_asset_name,
          license_policy_id: license_policy_id,
          admin_asset_name: admin_asset_name,
          admin_index: admin_index,
          pool_input: pool_input,
          pool_in_datum: datum,
          all_inputs: inputs,
          all_outputs: outputs,
          all_datums: datums,
          all_mints: mint,
          all_redeemers: redeemers,
        )
      }
      WithdrawLiquidityShare(admin_index) -> {
        let Transaction { inputs, outputs, datums, redeemers, mint, .. } =
          transaction
        expect Some(pool_input) = transaction.find_input(inputs, pool_input_ref)
        pool_validation.validate_withdraw_liquidity_share(
          authen_policy_id: authen_policy_id,
          pool_auth_asset_name: pool_auth_asset_name,
          license_policy_id: license_policy_id,
          admin_asset_name: admin_asset_name,
          admin_index: admin_index,
          pool_input: pool_input,
          pool_in_datum: datum,
          all_inputs: inputs,
          all_outputs: outputs,
          all_datums: datums,
          all_mints: mint,
          all_redeemers: redeemers,
        )
      }
    }
  }
}
