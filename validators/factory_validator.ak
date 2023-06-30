use aiken/builtin
use aiken/bytearray
use aiken/hash
use aiken/list
use aiken/transaction.{
  Datum, InlineDatum, Input, Output, ScriptContext, Spend, Transaction,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{AssetName, PolicyId}
use amm_dex_v2/math
use amm_dex_v2/types.{
  Asset, FactoryDatum, FactoryRedeemer, PoolDatum, ValidatorHash,
}
use amm_dex_v2/utils

validator(
  authen_policy_id: PolicyId,
  pool_hash: ValidatorHash,
  order_hash: ValidatorHash,
  factory_auth_asset_name: AssetName,
  pool_auth_asset_name: AssetName,
) {
  fn validate_factory(
    datum: FactoryDatum,
    redeemer: FactoryRedeemer,
    context: ScriptContext,
  ) {
    let ScriptContext { transaction, purpose } = context
    expect Spend(factory_ref) = purpose
    let Transaction { inputs, mint, outputs, .. } = transaction
    let FactoryRedeemer { asset_a, asset_b } = redeemer
    let FactoryDatum { head: current_head, tail: current_tail } = datum
    let Asset { policy_id: asset_a_policy_id, asset_name: asset_a_asset_name } =
      asset_a
    let Asset { policy_id: asset_b_policy_id, asset_name: asset_b_asset_name } =
      asset_b
    let is_sorted_asset = utils.sorted_asset(asset_a, asset_b)
    let asset_a_ident = bytearray.concat(asset_a_policy_id, asset_a_asset_name)
    let asset_b_ident = bytearray.concat(asset_b_policy_id, asset_b_asset_name)
    let pair_ident = bytearray.concat(asset_a_ident, asset_b_ident)
    let lp_asset_name = hash.sha3_256(pair_ident)

    let factory_input_opt =
      list.find(
        inputs,
        fn(input) {
          let Input { output_reference: out_ref, .. } = input
          out_ref == factory_ref
        },
      )
    expect Some(factory_input) = factory_input_opt
    let Input { output: factory_input_out, .. } = factory_input
    let Output { value: factory_input_value, address: factory_address, .. } =
      factory_input_out
    let has_factory_auth_asset =
      value.quantity_of(
        factory_input_value,
        authen_policy_id,
        factory_auth_asset_name,
      ) == 1

    let factory_outputs =
      list.filter(
        outputs,
        fn(output) {
          let Output { address: out_addr, value: out_value, .. } = output
          out_addr == factory_address && value.quantity_of(
            out_value,
            authen_policy_id,
            factory_auth_asset_name,
          ) == 1
        },
      )
    expect [factory_output_1, factory_output_2] = factory_outputs
    let Output { datum: factory_output_1_raw_datum, .. } = factory_output_1
    let Output { datum: factory_output_2_raw_datum, .. } = factory_output_2
    let FactoryDatum { head: new_head_1, tail: new_tail_1 } =
      parse_factory_datum(factory_output_1_raw_datum)
    let FactoryDatum { head: new_head_2, tail: new_tail_2 } =
      parse_factory_datum(factory_output_2_raw_datum)
    let is_valid_linked_list =
      builtin.less_than_bytearray(new_head_1, new_tail_1) && builtin.less_than_bytearray(
        new_head_2,
        new_tail_2,
      ) && new_head_1 == current_head && new_tail_2 == current_tail && lp_asset_name == new_tail_1 && lp_asset_name == new_head_2

    let pool_outputs =
      list.filter(
        outputs,
        fn(output) {
          let Output { address: out_addr, value: out_value, .. } = output
          let Address { payment_credential: out_addr_payment_credential, .. } =
            out_addr
          when out_addr_payment_credential is {
            ScriptCredential(hash) ->
              pool_hash == hash && value.quantity_of(
                out_value,
                authen_policy_id,
                pool_auth_asset_name,
              ) == 1
            _ -> False
          }
        },
      )
    expect [pool_output] = pool_outputs
    let Output { value: pool_output_value, datum: pool_output_raw_datum, .. } =
      pool_output
    let pool_out_datum = parse_pool_datum(pool_output_raw_datum)
    let PoolDatum {
      asset_a: pool_datum_asset_a,
      asset_b: pool_datum_asset_b,
      total_liquidity: pool_datum_total_liquidity,
      root_k_last: pool_datum_root_k_last,
      trading_fee_numerator: pool_datum_trading_fee_numerator,
      trading_fee_denominator: pool_datum_trading_fee_denominator,
      order_hash: pool_datum_order_hash,
      profit_sharing_opt: pool_datum_profit_sharing_opt,
    } = pool_out_datum
    expect None = pool_datum_profit_sharing_opt
    let estimated_amount_a =
      value.quantity_of(
        pool_output_value,
        asset_a_policy_id,
        asset_a_asset_name,
      )
    let amount_a =
      if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
        estimated_amount_a - 3000000
      } else {
        estimated_amount_a
      }
    let amount_b =
      value.quantity_of(
        pool_output_value,
        asset_b_policy_id,
        asset_b_asset_name,
      )
    let total_liquidity = math.calculate_sqrt(amount_a * amount_b)
    let remaining_liquidity = 9223372036854775807 - total_liquidity - 1000
    let is_liquidity_correct =
      value.quantity_of(pool_output_value, authen_policy_id, lp_asset_name) == remaining_liquidity
    is_sorted_asset && // todo
    has_factory_auth_asset && // todo
    is_valid_linked_list && // todo
    pool_datum_asset_a == asset_a && // todo
    pool_datum_asset_b == asset_b && // todo
    pool_datum_total_liquidity == total_liquidity && // todo
    pool_datum_root_k_last == 0 && // todo
    pool_datum_trading_fee_numerator > 0 && // todo
    pool_datum_trading_fee_denominator > 0 && // todo
    pool_datum_trading_fee_numerator < pool_datum_trading_fee_denominator && // todo
    pool_datum_order_hash == order_hash && // todo
    is_liquidity_correct
  }
}

fn parse_factory_datum(datum: Datum) -> FactoryDatum {
  expect InlineDatum(data) = datum
  expect factory_datum: FactoryDatum = data
  factory_datum
}

fn parse_pool_datum(datum: Datum) -> PoolDatum {
  expect InlineDatum(data) = datum
  expect pool_datum: PoolDatum = data
  pool_datum
}
