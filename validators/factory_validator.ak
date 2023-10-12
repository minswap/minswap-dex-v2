use aiken/builtin
use aiken/list
use aiken/transaction.{Input, Output, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{AssetName, MintedValue, PolicyId}
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
    // Asset A must less than Asset B
    expect utils.sorted_asset(asset_a, asset_b)
    let lp_asset_name =
      utils.compute_lp_asset_name(
        asset_a_policy_id,
        asset_a_asset_name,
        asset_b_policy_id,
        asset_b_asset_name,
      )
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
    // Transaction must have a Factory Asset in the Spending Script
    expect
      value.quantity_of(
        factory_input_value,
        authen_policy_id,
        factory_auth_asset_name,
      ) == 1
    expect [factory_output_1, factory_output_2] =
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
    let Output { datum: factory_output_1_raw_datum, .. } = factory_output_1
    let Output { datum: factory_output_2_raw_datum, .. } = factory_output_2
    let FactoryDatum { head: new_head_1, tail: new_tail_1 } =
      utils.parse_factory_datum(factory_output_1_raw_datum)
    let FactoryDatum { head: new_head_2, tail: new_tail_2 } =
      utils.parse_factory_datum(factory_output_2_raw_datum)
    // Transaction must put new hash between old hashes, (current_head, current_tail) -> (current_head, new_hash) && (new_hash, current_tail)
    expect
      builtin.less_than_bytearray(new_head_1, new_tail_1) && builtin.less_than_bytearray(
        new_head_2,
        new_tail_2,
      ) && new_head_1 == current_head && new_tail_2 == current_tail && lp_asset_name == new_tail_1 && lp_asset_name == new_head_2
    expect [pool_output] =
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
    let Output { value: pool_output_value, datum: pool_output_raw_datum, .. } =
      pool_output
    let PoolDatum {
      asset_a: pool_datum_asset_a,
      asset_b: pool_datum_asset_b,
      total_liquidity: pool_datum_total_liquidity,
      root_k_last: pool_datum_root_k_last,
      liquidity_share: pool_datum_liquidity_share,
      trading_fee_numerator: pool_datum_trading_fee_numerator,
      trading_fee_denominator: pool_datum_trading_fee_denominator,
      order_hash: pool_datum_order_hash,
      profit_sharing_opt: pool_datum_profit_sharing_opt,
    } = utils.parse_pool_datum(pool_output_raw_datum)
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
    let total_liquidity = math.calculate_initial_liquidity(amount_a, amount_b)

    expect
      pool_datum_asset_a == asset_a && pool_datum_asset_b == asset_b && // Asset A & B must be existed in Pool Datum
      pool_datum_total_liquidity == total_liquidity && // Total Liquidity in PoolDatum must be sqrt(amount_a * amount_b)
      pool_datum_root_k_last == 0 && // RootKLast must be zero
      pool_datum_liquidity_share == 0 && // Liquidity Share must be zero 
      pool_datum_trading_fee_numerator > 0 && pool_datum_trading_fee_denominator > 0 && pool_datum_trading_fee_numerator < pool_datum_trading_fee_denominator && // Trading Fee Numenator & Denominator must be positive, Trading Fee Numenator must be less than Trading Fee Denominator
      pool_datum_order_hash == order_hash
    // Order Hash in Pool Datum must be matched with Order Hash in parameters
    let remaining_liquidity = 9223372036854775807 - total_liquidity
    // Remaining Liquidity must be MAX_LIQUIDITY - total_liquidity
    expect
      value.quantity_of(pool_output_value, authen_policy_id, lp_asset_name) == remaining_liquidity
    // Transaction must mint only 1 Factory Asset + 1 Pool Asset + MAX INT64 LP Asset
    expect
      validate_mint(
        mint,
        authen_policy_id,
        factory_auth_asset_name,
        pool_auth_asset_name,
        lp_asset_name,
      )
    True
  }
}

// This function will validate Mint part in Pool Creation Transaction
// Transaction must mint only 1 Factory Asset + 1 Pool Asset + MAX INT64 LP Asset
// Otherwise transaction must be failed
fn validate_mint(
  mint: MintedValue,
  authen_policy_id: PolicyId,
  factory_auth_asset_name: AssetName,
  pool_auth_asset_name: AssetName,
  lp_asset_name: AssetName,
) -> Bool {
  let mint_value = value.from_minted_value(mint)
  let flatten_mint_value = value.flatten(mint_value)
  let validate_num =
    list.foldr(
      flatten_mint_value,
      0,
      fn(v, acc) {
        let (pid, an, am) = v
        if acc < 0 {
          acc
        } else {
          if pid != authen_policy_id {
            -1
          } else {
            if an == factory_auth_asset_name && am == 1 {
              acc + 1
            } else if an == pool_auth_asset_name && am == 1 {
              acc + 1
            } else if an == lp_asset_name && am == 9223372036854775807 {
              acc + 1
            } else {
              -1
            }
          }
        }
      },
    )
  validate_num == 3
}
