use aiken/builtin
use aiken/dict
use aiken/list
use aiken/transaction.{
  Input, Mint, Output, OutputReference, ScriptContext, Spend, Transaction,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value
use amm_dex_v2/pool_validation
use amm_dex_v2/types.{
  Asset, AuthenRedeemer, CreatePool, FactoryDatum, FactoryRedeemer,
  GlobalSetting, MintFactoryAuthen,
}
use amm_dex_v2/utils

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
                utils.factory_auth_asset_name,
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
        let Transaction { inputs, mint, outputs, .. } = transaction

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
        expect [
          (minted_pid_1, minted_an_1, minted_amount_1),
          (minted_pid_2, minted_an_2, minted_amount_2),
        ] = value.flatten(mint_value)
        let is_valid_minted_asset_name =
          if builtin.less_than_bytearray(minted_an_1, minted_an_2) {
            and {
              minted_an_1 == utils.global_setting_asset_name,
              minted_an_2 == utils.factory_auth_asset_name,
            }
          } else {
            and {
              minted_an_1 == utils.factory_auth_asset_name,
              minted_an_2 == utils.global_setting_asset_name,
            }
          }
        expect and {
            minted_pid_1 == authen_policy_id,
            minted_pid_2 == authen_policy_id,
            minted_amount_1 == 1,
            minted_amount_2 == 1,
            is_valid_minted_asset_name,
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
                utils.factory_auth_asset_name,
              ) == 1
            },
          )
        let Output { datum: factory_raw_datum, .. } = factory_output
        expect factory_datum: FactoryDatum =
          utils.must_find_script_inline_datum(factory_raw_datum)
        let FactoryDatum { head, tail } = factory_datum

        expect [global_setting_output] =
          list.filter(
            outputs,
            fn(output) {
              let Output {
                address: Address { payment_credential: payment_cred, .. },
                ..
              } = output
              when payment_cred is {
                ScriptCredential(h) -> h == authen_policy_id
                _ -> False
              }
            },
          )
        let Output {
          value: global_setting_value,
          datum: global_setting_datum_raw,
          ..
        } = global_setting_output
        expect global_setting: GlobalSetting =
          utils.must_find_script_inline_datum(global_setting_datum_raw)
        let GlobalSetting { batchers, .. } = global_setting
        and {
          head == #"00",
          tail == #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00",
          !builtin.null_list(batchers),
          value.quantity_of(
            global_setting_value,
            authen_policy_id,
            utils.global_setting_asset_name,
          ) == 1,
        }
      }
    }
  }

  fn validate_spend_global_setting(
    _data: Data,
    _r: Data,
    context: ScriptContext,
  ) {
    expect ScriptContext { purpose: Spend(_), .. } = context
    True
  }
}
