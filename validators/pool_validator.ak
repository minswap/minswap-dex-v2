use aiken/builtin
use aiken/list
use aiken/transaction.{ScriptContext, Spend, Transaction}
use aiken/transaction/value.{AssetName, PolicyId}
use amm_dex_v2/pool_validation
use amm_dex_v2/types.{
  Batching, MultiRouting, PoolDatum, PoolRedeemer,
  UpdatePoolFeeOrStakeCredential, WithdrawLiquidityShare,
}
use amm_dex_v2/utils

validator(
  // The PolicyID of Authen Minting Policy
  authen_policy_id: PolicyId,
  // Policy ID managed by the Minswap team, used for minting Batcher License and Admin License assets
  license_policy_id: PolicyId,
  // the legitimate Pool TokenName
  pool_auth_asset_name: AssetName,
  // The TokenName of Admin Asset, determined by Minswap team
  admin_asset_name: AssetName,
  // Maximum expiration time of Batcher license from now (to prevent minting infinity license)
  maximum_deadline_range: Int,
) {
  fn validate_pool(
    datum: PoolDatum,
    redeemer: PoolRedeemer,
    context: ScriptContext,
  ) {
    expect ScriptContext { transaction, purpose: Spend(pool_input_ref) } =
      context
    when redeemer is {
      Batching(input_indexes, license_index) -> {
        let Transaction { inputs, outputs, datums, validity_range, mint, .. } =
          transaction
        // Batching Redeemer provides @license_index which help save calculation cost
        let license_input = utils.list_at_index(inputs, license_index)
        // A valid license token is the token having expired timestamp as TokenName and must be within current time and current time + _maximum_deadline_range_
        let batcher_address =
          pool_validation.validate_batcher_license_and_find_batcher_address(
            license_input: license_input,
            validity_range: validity_range,
            license_policy_id: license_policy_id,
            maximum_deadline_range: maximum_deadline_range,
          )
        and {
          // Input indexes must not be empty list
          !builtin.null_list(input_indexes),
          // Input indexes must be unique
          utils.is_list_unique(input_indexes),
          // validate Transaction won't mint any assets
          value.is_zero(value.from_minted_value(mint)),
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
          ),
        }
      }
      MultiRouting(license_index, routing_in_indexes, routing_out_indexes) -> {
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
        // let Address { payment_credential: batcher_payment_credential, .. } =
        //   batcher_address
        // expect VerificationKeyCredential(batcher_pkh) =
        //   batcher_payment_credential
        // Batching Redeemer provides @license_index which help save calculation cost
        let license_input = utils.list_at_index(inputs, license_index)
        let batcher_address =
          pool_validation.validate_batcher_license_and_find_batcher_address(
            license_input: license_input,
            validity_range: validity_range,
            license_policy_id: license_policy_id,
            maximum_deadline_range: maximum_deadline_range,
          )
        and {
          // validate Transaction won't mint any assets
          value.is_zero(value.from_minted_value(mint)),
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
          ),
        }
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
