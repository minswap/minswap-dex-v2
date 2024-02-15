use aiken/dict
use aiken/list
use aiken/transaction.{
  Input, Mint, Output, OutputReference, ScriptContext, Spend, Transaction,
}
use aiken/transaction/value
use amm_dex_v2/pool_validation
use amm_dex_v2/types.{
  Asset, AuthenRedeemer, CreatePool, FactoryDatum, FactoryRedeemer,
  MintFactoryAuthen,
}
use amm_dex_v2/utils.{factory_auth_asset_name}

validator(
  // @out_ref is a Reference of an Unspent Transaction Output,
  // which will only be spent on `MintFactoryAuthen` redeemer to make sure this redeemer can only be called once
  out_ref: OutputReference,
) {
  fn validate_authen(redeemer: AuthenRedeemer, context: ScriptContext) {
    let ScriptContext { transaction, purpose } = context
    expect Mint(authen_policy_id) = purpose
    when redeemer is {
      CreatePool -> {
        let Transaction { inputs, mint, redeemers, .. } = transaction
        // validate that there's a single Factory UTxO in the Transaction Inputs. 
        // Factory UTxO must contain Factory NFT Token in the value
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
          lp_asset_name: lp_asset_name,
        )
      }
      // The redeemer can be called once to initialize the whole AMM V2 system
      MintFactoryAuthen -> {
        let Transaction { inputs, mint, outputs, datums, .. } = transaction

        // validate that `out_ref` must be presented in the Transaction Inputs
        expect [_] =
          list.filter(
            inputs,
            fn(input) {
              let Input { output_reference, .. } = input
              output_reference == out_ref
            },
          )

        // validate that the redeemer only mint a single Factory Token 
        let mint_value = value.from_minted_value(mint)
        expect [(minted_pid, minted_an, minted_amount)] =
          value.flatten(mint_value)
        expect and {
            minted_pid == authen_policy_id,
            minted_an == factory_auth_asset_name,
            minted_amount == 1,
          }
        // validate that there's only 1 Factory UTxO in the Transaction Outputs
        // The Factory UTxO must contain Factory Token in the value
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
        expect factory_datum: FactoryDatum =
          utils.must_find_script_datum(datums, factory_raw_datum)
        let FactoryDatum { head, tail } = factory_datum
        and {
          head == #"00",
          tail == #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00",
        }
      }
    }
  }
}
