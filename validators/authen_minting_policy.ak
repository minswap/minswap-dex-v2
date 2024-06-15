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
  Asset, AuthenRedeemer, CreatePool, DexInitialization, FactoryDatum,
  FactoryRedeemer, GlobalSetting, PAMSignature, PAMSpendScript,
  PAMWithdrawScript, PoolAuthorizationMethod,
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
      DexInitialization -> {
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

        // there are two NFT tokens that are minted in this transaction
        // - 1 Factory NFT that have the same policy id with the own script hash 
        //        and token name is defined in @factory_auth_asset_name
        // - 1 Global Setting NFT that have the same policy id with the own script hash 
        //        and token name is defined in @global_setting_asset_name
        let mint_value = value.from_minted_value(mint)
        expect and {
            list.length(value.flatten(mint_value)) == 2,
            value.quantity_of(
              mint_value,
              authen_policy_id,
              utils.global_setting_asset_name,
            ) == 1,
            value.quantity_of(
              mint_value,
              authen_policy_id,
              utils.factory_auth_asset_name,
            ) == 1,
          }
        // validate that there's only 1 Factory UTxO in the Transaction Outputs
        // The Factory UTxO must contain 1 Factory Token in the value
        expect [factory_output] =
          list.filter(
            outputs,
            fn(output) {
              let Output { value: out_value, .. } = output
              value.without_lovelace(out_value) == value.from_asset(
                authen_policy_id,
                utils.factory_auth_asset_name,
                1,
              )
            },
          )
        let Output { datum: factory_raw_datum, .. } = factory_output
        expect factory_datum: FactoryDatum =
          utils.must_find_script_inline_datum(factory_raw_datum)
        let FactoryDatum { head, tail } = factory_datum

        // validate that there's only 1 Global Setting UTxO in the Transaction Outputs
        // The Global Setting UTxO must contain 1 Global Setting Token in the value
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
        and {
          head == #"00",
          tail == #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00",
          validate_global_setting(global_setting),
          // The Global Setting UTxO must contain 1 Global Setting Token in the value
          value.without_lovelace(global_setting_value) == value.from_asset(
            authen_policy_id,
            utils.global_setting_asset_name,
            1,
          ),
        }
      }
    }
  }

  fn validate_spend_global_setting(
    datum: GlobalSetting,
    _redeemer: Data,
    context: ScriptContext,
  ) {
    let ScriptContext { transaction, purpose } = context
    expect Spend(global_setting_input_ref) = purpose
    let Transaction {
      inputs,
      outputs,
      extra_signatories,
      withdrawals,
      mint,
      ..
    } = transaction
    expect Some(global_setting_input) =
      transaction.find_input(inputs, global_setting_input_ref)
    let Input {
      output: Output {
        value: global_setting_value_input,
        address: Address {
          payment_credential: global_setting_payment_credential,
          ..
        },
        ..
      },
      ..
    } = global_setting_input
    expect ScriptCredential(global_setting_script_hash) =
      global_setting_payment_credential

    let GlobalSetting { admin, .. } = datum
    let global_setting_output = outputs |> builtin.head_list
    let Output {
      value: global_setting_value_out,
      address: Address {
        payment_credential: global_setting_payment_credential_out,
        ..
      },
      datum: global_setting_out_raw_datum,
      ..
    } = global_setting_output
    expect global_setting_out_datum: GlobalSetting =
      utils.must_find_script_inline_datum(global_setting_out_raw_datum)

    and {
      // Transaction must be executed by the correct admin
      utils.authorize_pool_license(
        author: admin,
        transaction_inputs: inputs,
        withdrawals: withdrawals,
        extra_signatories: extra_signatories,
      ),
      // Both Global Setting input and output must have the same payment credential 
      // and keep the Global Setting Token
      value.quantity_of(
        global_setting_value_input,
        global_setting_script_hash,
        utils.global_setting_asset_name,
      ) == 1,
      value.without_lovelace(global_setting_value_out) == value.from_asset(
        global_setting_script_hash,
        utils.global_setting_asset_name,
        1,
      ),
      global_setting_payment_credential_out == global_setting_payment_credential,
      // transaction won't mint anything 
      value.is_zero(value.from_minted_value(mint)),
      validate_global_setting(global_setting_out_datum),
    }
  }
}

fn validate_global_setting(global_setting: GlobalSetting) -> Bool {
  let GlobalSetting {
    batchers,
    pool_fee_updater,
    fee_sharing_taker,
    pool_stake_key_updater,
    pool_dynamic_fee_updater,
    admin,
  } = global_setting
  and {
    validate_pool_authorization_method(pool_fee_updater),
    validate_pool_authorization_method(fee_sharing_taker),
    validate_pool_authorization_method(pool_stake_key_updater),
    validate_pool_authorization_method(pool_dynamic_fee_updater),
    validate_pool_authorization_method(admin),
    !builtin.null_list(batchers),
    list.all(
      batchers,
      fn(batcher) { validate_pool_authorization_method(batcher) },
    ),
  }
}

fn validate_pool_authorization_method(method: PoolAuthorizationMethod) -> Bool {
  let hash =
    when method is {
      PAMSignature(h) -> h
      PAMSpendScript(h) -> h
      PAMWithdrawScript(h) -> h
    }
  builtin.length_of_bytearray(hash) == 28
}
