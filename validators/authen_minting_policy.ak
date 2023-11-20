use aiken/dict
use aiken/list
use aiken/transaction.{
  Input, Mint, Output, OutputReference, ScriptContext, Spend, Transaction,
}
use aiken/transaction/value.{AssetName}
use amm_dex_v2/pool_validation
use amm_dex_v2/types.{
  Asset, AuthenRedeemer, CreatePool, FactoryDatum, FactoryRedeemer,
  MintFactoryAuthen, MintLiquidity,
}
use amm_dex_v2/utils

validator(
  out_ref: OutputReference,
  factory_auth_asset_name: AssetName,
  pool_auth_asset_name: AssetName,
) {
  fn validate_authen(redeemer: AuthenRedeemer, context: ScriptContext) {
    let ScriptContext { transaction, purpose } = context
    expect Mint(authen_policy_id) = purpose
    when redeemer is {
      MintFactoryAuthen -> {
        let Transaction { inputs, mint, outputs, datums, .. } = transaction

        // Transaction must has @out_ref in the input to make sure that this redeemer can only be executed once
        expect [_] =
          list.filter(
            inputs,
            fn(input) {
              let Input { output_reference, .. } = input
              output_reference == out_ref
            },
          )
        let mint_value = value.from_minted_value(mint)
        expect [(minted_pid, minted_an, minted_amount)] =
          value.flatten(mint_value)
        // Transaction must mint only 1 Factory Auth Asset
        expect and {
            minted_pid == authen_policy_id,
            minted_an == factory_auth_asset_name,
            minted_amount == 1,
          }
        expect [factory_output] =
          list.filter(
            outputs,
            fn(output) {
              let Output { value: out_value, .. } = output
              value.quantity_of(
                out_value,
                authen_policy_id,
                factory_auth_asset_name,
              ) == 1
            },
          )
        let Output { datum: factory_raw_datum, .. } = factory_output
        let FactoryDatum { head, tail } =
          utils.must_find_factory_datum(datums, factory_raw_datum)
        and {
          head == #"00",
          tail == #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00",
        }
      }
      CreatePool -> {
        let Transaction { inputs, mint, redeemers, .. } = transaction
        expect [factory_input] =
          list.filter(
            inputs,
            fn(input) {
              let Input { output, .. } = input
              let Output { value: out_value, .. } = output
              value.quantity_of(
                out_value,
                authen_policy_id,
                factory_auth_asset_name,
              ) == 1
            },
          )
        let Input { output_reference: factory_input_ref, .. } = factory_input
        let redeemer_list = dict.to_list(redeemers)
        expect [(_, raw_factory_redeemer)] =
          list.filter(
            redeemer_list,
            fn(r) {
              let (p, _) = r
              when p is {
                Spend(ref) -> factory_input_ref == ref
                _ -> False
              }
            },
          )
        expect factory_redeemer: FactoryRedeemer = raw_factory_redeemer
        let FactoryRedeemer { asset_a, asset_b } = factory_redeemer
        let Asset {
          policy_id: asset_a_policy_id,
          asset_name: asset_a_asset_name,
        } = asset_a
        let Asset {
          policy_id: asset_b_policy_id,
          asset_name: asset_b_asset_name,
        } = asset_b
        // todo, consider whether we need this logic or not?
        expect utils.sorted_asset(asset_a, asset_b)
        let lp_asset_name =
          utils.compute_lp_asset_name(
            asset_a_policy_id,
            asset_a_asset_name,
            asset_b_policy_id,
            asset_b_asset_name,
          )
        value.from_minted_value(mint) == pool_validation.get_pool_creation_expected_mint(
          authen_policy_id: authen_policy_id,
          factory_auth_asset_name: factory_auth_asset_name,
          pool_auth_asset_name: pool_auth_asset_name,
          lp_asset_name: lp_asset_name,
        )
      }
      MintLiquidity -> fail
    }
  }
}
