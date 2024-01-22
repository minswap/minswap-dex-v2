use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list
use aiken/transaction.{Input, Output, ValidityRange}
use aiken/transaction/credential.{Address, PaymentCredential, StakeCredential}
use aiken/transaction/value.{
  AssetName, PolicyId, Value, ada_asset_name, ada_policy_id,
}
use amm_dex_v2/types.{
  Asset, BatchingPool, DatumMap, PoolDatum, UpdatePoolFee,
  UpdatePoolFeeOrStakeCredentialAction, UpdatePoolStakeCredential,
}
use amm_dex_v2/utils.{
  admin_asset_name, admin_policy_id, factory_auth_asset_name, license_policy_id,
  maximum_deadline_range, pool_auth_asset_name,
}

pub fn validate_batcher_license_and_find_batcher_address(
  license_input: Input,
  validity_range: ValidityRange,
) -> (Address, Int) {
  let Input {
    output: Output { address: batcher_address, value: license_value, .. },
    ..
  } = license_input
  expect [(license_asset_name, license_amount)] =
    license_value
      |> value.tokens(license_policy_id)
      |> dict.to_list()
  let license_deadline = utils.bytearray_to_positive_int(license_asset_name)
  let Interval {
    lower_bound: IntervalBound { bound_type: lower_bound_type, .. },
    upper_bound: IntervalBound { bound_type: upper_bound_type, .. },
  } = validity_range
  expect Finite(start_valid_time_range) = lower_bound_type
  expect Finite(end_valid_time_range) = upper_bound_type
  // - Only Batcher with valid license token can trigger @ApplyPool redeemer validation.  
  // - A valid license token is the token with @tokenName (representing for expired milliseconds) 
  //   and must be within the time range from current_time to current_time + maximum_deadline_range
  expect and {
      license_amount == 1,
      license_deadline >= end_valid_time_range,
      license_deadline <= start_valid_time_range + maximum_deadline_range,
    }
  (batcher_address, end_valid_time_range)
}

pub fn get_batching_pool(
  stake_credential: StakeCredential,
  pool_input: Output,
  pool_output: Output,
  authen_policy_id: PolicyId,
  datum_map: DatumMap,
  require_total_liquidity_unchange: Bool,
) -> BatchingPool {
  let Output {
    address: pool_in_address,
    value: pool_in_value,
    datum: pool_in_datum_raw,
    ..
  } = pool_input
  let Output {
    address: pool_out_address,
    value: pool_out_value,
    datum: pool_out_datum_raw,
    ..
  } = pool_output

  expect pool_in_datum: PoolDatum =
    utils.must_find_script_datum(datum_map, pool_in_datum_raw)

  let PoolDatum {
    stake_credential: pool_in_stake_credential,
    asset_a: pool_in_asset_a,
    asset_b: pool_in_asset_b,
    total_liquidity: pool_in_total_liquidity,
    reserve_a: pool_in_datum_reserve_a,
    reserve_b: pool_in_datum_reserve_b,
    trading_fee_numerator: pool_in_trading_fee_numerator,
    trading_fee_denominator: pool_in_trading_fee_denominator,
    profit_sharing_opt: pool_in_profit_sharing_opt,
  } = pool_in_datum
  expect pool_out_datum: PoolDatum =
    utils.must_find_script_datum(datum_map, pool_out_datum_raw)
  let PoolDatum {
    stake_credential: pool_out_stake_credential,
    asset_a: pool_out_asset_a,
    asset_b: pool_out_asset_b,
    total_liquidity: pool_out_total_liquidity,
    reserve_a: pool_out_datum_reserve_a,
    reserve_b: pool_out_datum_reserve_b,
    trading_fee_numerator: pool_out_trading_fee_numerator,
    trading_fee_denominator: pool_out_trading_fee_denominator,
    profit_sharing_opt: pool_out_profit_sharing_opt,
  } = pool_out_datum

  expect
    if require_total_liquidity_unchange {
      pool_in_total_liquidity == pool_out_total_liquidity
    } else {
      True
    }
  expect and {
      pool_in_stake_credential == pool_out_stake_credential,
      pool_in_stake_credential == stake_credential,
      pool_in_address == pool_out_address,
      pool_in_asset_a == pool_out_asset_a,
      pool_in_asset_b == pool_out_asset_b,
      pool_in_trading_fee_numerator == pool_out_trading_fee_numerator,
      pool_in_trading_fee_denominator == pool_out_trading_fee_denominator,
      pool_in_profit_sharing_opt == pool_out_profit_sharing_opt,
    }
  let Asset { policy_id: asset_a_policy_id, asset_name: asset_a_asset_name } =
    pool_in_asset_a
  let Asset { policy_id: asset_b_policy_id, asset_name: asset_b_asset_name } =
    pool_in_asset_b

  let lp_asset_name =
    utils.compute_lp_asset_name(
      asset_a_policy_id,
      asset_a_asset_name,
      asset_b_policy_id,
      asset_b_asset_name,
    )
  let lp_asset =
    Asset { policy_id: authen_policy_id, asset_name: lp_asset_name }

  let estimate_value_reserve_a_in =
    value.quantity_of(pool_in_value, asset_a_policy_id, asset_a_asset_name)
  let estimate_value_reserve_a_out =
    value.quantity_of(pool_out_value, asset_a_policy_id, asset_a_asset_name)
  let (value_reserve_a_in, value_reserve_a_out) =
    if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
      (
        estimate_value_reserve_a_in - 3000000,
        estimate_value_reserve_a_out - 3000000,
      )
    } else {
      (estimate_value_reserve_a_in, estimate_value_reserve_a_out)
    }
  let value_reserve_b_in =
    value.quantity_of(pool_in_value, asset_b_policy_id, asset_b_asset_name)
  let value_reserve_b_out =
    value.quantity_of(pool_out_value, asset_b_policy_id, asset_b_asset_name)

  let remaining_liquidity_supply_in =
    value.quantity_of(pool_in_value, authen_policy_id, lp_asset_name)
  let remaining_liquidity_supply_out =
    value.quantity_of(pool_out_value, authen_policy_id, lp_asset_name)
  let estimate_pool_in_value =
    value.zero()
      |> value.add(ada_policy_id, ada_asset_name, 3000000)
      |> value.add(authen_policy_id, pool_auth_asset_name, 1)
      |> value.add(asset_a_policy_id, asset_a_asset_name, value_reserve_a_in)
      |> value.add(asset_b_policy_id, asset_b_asset_name, value_reserve_b_in)
      |> value.add(authen_policy_id, lp_asset_name, remaining_liquidity_supply_in)
  let estimate_pool_out_value =
    value.zero()
      |> value.add(ada_policy_id, ada_asset_name, 3000000)
      |> value.add(authen_policy_id, pool_auth_asset_name, 1)
      |> value.add(asset_a_policy_id, asset_a_asset_name, value_reserve_a_out)
      |> value.add(asset_b_policy_id, asset_b_asset_name, value_reserve_b_out)
      |> value.add(authen_policy_id, lp_asset_name, remaining_liquidity_supply_out)
  expect and {
      estimate_pool_in_value == pool_in_value,
      estimate_pool_out_value == pool_out_value,
      remaining_liquidity_supply_out - remaining_liquidity_supply_in == pool_in_total_liquidity - pool_out_total_liquidity,
    }
  BatchingPool {
    asset_a: pool_in_asset_a,
    asset_b: pool_in_asset_b,
    lp_asset,
    trading_fee_numerator: pool_in_trading_fee_numerator,
    trading_fee_denominator: pool_in_trading_fee_denominator,
    profit_sharing: pool_in_profit_sharing_opt,
    pool_state_in: (
      pool_in_datum_reserve_a,
      pool_in_datum_reserve_b,
      value_reserve_a_in,
      value_reserve_b_in,
      pool_in_total_liquidity,
    ),
    pool_state_out: (
      pool_out_datum_reserve_a,
      pool_out_datum_reserve_b,
      value_reserve_a_out,
      value_reserve_b_out,
      pool_out_total_liquidity,
    ),
  }
}

pub fn validate_update_pool_datum_or_stake_credential(
  action: UpdatePoolFeeOrStakeCredentialAction,
  authen_policy_id: PolicyId,
  admin_index: Int,
  pool_input: Input,
  pool_in_datum: PoolDatum,
  all_inputs: List<Input>,
  all_outputs: List<Output>,
  all_datums: DatumMap,
) -> Bool {
  let Input { output: pool_in_output, .. } = pool_input
  let Output { address: pool_in_address, value: pool_in_value, .. } =
    pool_in_output
  let Address { payment_credential: pool_in_address_payment_credential, .. } =
    pool_in_address

  let admin_input = utils.list_at_index(all_inputs, admin_index)
  let Input { output: Output { value: admin_value, .. }, .. } = admin_input
  // validate there is a single Pool UTxO in Transaction Outputs
  let Output {
    address: pool_out_address,
    value: pool_out_value,
    datum: raw_pool_out_datum,
    ..
  } =
    get_single_pool_output(
      all_outputs: all_outputs,
      pool_payment_credential: pool_in_address_payment_credential,
    )

  expect and {
      // Pool Input contains 1 valid Pool NFT Token
      value.quantity_of(pool_in_value, authen_policy_id, pool_auth_asset_name) == 1,
      // validate Admin with valid Admin License Token must be presented in Transaction Inputs
      value.quantity_of(admin_value, admin_policy_id, admin_asset_name) == 1,
      // Pool Value must be unchanged
      pool_in_value == pool_out_value,
    }
  expect pool_out_datum: PoolDatum =
    utils.must_find_script_datum(all_datums, raw_pool_out_datum)
  when action is {
    UpdatePoolFee -> {
      let PoolDatum {
        stake_credential: pool_in_stake_credential,
        asset_a: pool_in_asset_a,
        asset_b: pool_in_asset_b,
        total_liquidity: pool_in_total_liquidity,
        reserve_a: pool_in_reserve_a,
        reserve_b: pool_in_reserve_b,
        ..
      } = pool_in_datum
      let PoolDatum {
        stake_credential: pool_out_stake_credential,
        asset_a: pool_out_asset_a,
        asset_b: pool_out_asset_b,
        total_liquidity: pool_out_total_liquidity,
        reserve_a: pool_out_reserve_a,
        reserve_b: pool_out_reserve_b,
        trading_fee_numerator: pool_out_trading_fee_numerator,
        trading_fee_denominator: pool_out_trading_fee_denominator,
        profit_sharing_opt: pool_out_profit_sharing_opt,
      } = pool_out_datum
      // Profit Sharing can be on/off by setting profit_sharing_opt is None or Some. 
      // Profit Sharing must be between **16.66%** and **50%**
      let is_valid_fee_sharing =
        when pool_out_profit_sharing_opt is {
          None -> True
          Some(pool_out_profit_sharing) -> {
            let (
              pool_out_fee_sharing_numerator,
              pool_out_fee_sharing_denominator,
            ) = pool_out_profit_sharing
            validate_fee_sharing_percent(
              fee_sharing_numerator: pool_out_fee_sharing_numerator,
              fee_sharing_denominator: pool_out_fee_sharing_denominator,
            )
          }
        }
      and {
        // Irrelevant fields on Pool Datum must be unchanged
        pool_in_stake_credential == pool_out_stake_credential,
        pool_in_asset_a == pool_out_asset_a,
        pool_in_asset_b == pool_out_asset_b,
        pool_in_total_liquidity == pool_out_total_liquidity,
        pool_in_reserve_a == pool_out_reserve_a,
        pool_in_reserve_b == pool_out_reserve_b,
        // Pool Address must be unchanged (both Payment and Stake Credential)
        pool_in_address == pool_out_address,
        // Trading Fee must be between **0.05%** and **10%**
        validate_trading_fee_percent(
          trading_fee_numerator: pool_out_trading_fee_numerator,
          trading_fee_denominator: pool_out_trading_fee_denominator,
        ),
        is_valid_fee_sharing,
      }
    }
    // Pool Datum must be unchanged
    UpdatePoolStakeCredential -> pool_in_datum == pool_out_datum
  }
}

pub fn validate_trading_fee_percent(
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
) -> Bool {
  // Max 10%, Min 0.05%
  let max_trading_fee_numerator = 1
  let max_trading_fee_denominator = 10
  let min_trading_fee_numerator = 5
  let min_trading_fee_denominator = 10000

  let less_than_max =
    trading_fee_numerator * max_trading_fee_denominator <= trading_fee_denominator * max_trading_fee_numerator
  let greater_than_min =
    trading_fee_numerator * min_trading_fee_denominator >= trading_fee_denominator * min_trading_fee_numerator
  less_than_max && greater_than_min
}

pub fn validate_fee_sharing_percent(
  fee_sharing_numerator: Int,
  fee_sharing_denominator: Int,
) -> Bool {
  // Max 50%, Min 16.66%
  let max_fee_sharing_numerator = 1
  let max_fee_sharing_denominator = 2
  let min_fee_sharing_numerator = 1
  let min_fee_sharing_denominator = 6

  let less_than_max =
    fee_sharing_numerator * max_fee_sharing_denominator <= fee_sharing_denominator * max_fee_sharing_numerator
  let greater_than_min =
    fee_sharing_numerator * min_fee_sharing_denominator >= fee_sharing_denominator * min_fee_sharing_numerator
  less_than_max && greater_than_min
}

pub fn validate_withdraw_liquidity_share(
  authen_policy_id: PolicyId,
  admin_index: Int,
  pool_input: Input,
  pool_in_datum: PoolDatum,
  all_inputs: List<Input>,
  all_outputs: List<Output>,
  all_datums: DatumMap,
) -> Bool {
  let Input {
    output: Output { address: pool_in_address, value: pool_in_value, .. },
    ..
  } = pool_input
  let Address { payment_credential: pool_in_payment_credential, .. } =
    pool_in_address
  // validate there is a single Pool UTxO in Transaction Outputs
  let Output {
    address: pool_out_address,
    value: pool_out_value,
    datum: raw_pool_out_datum,
    ..
  } =
    get_single_pool_output(
      all_outputs: all_outputs,
      pool_payment_credential: pool_in_payment_credential,
    )
  expect pool_out_datum: PoolDatum =
    utils.must_find_script_datum(all_datums, raw_pool_out_datum)
  let admin_input = utils.list_at_index(all_inputs, admin_index)
  let Input { output: Output { value: admin_value, .. }, .. } = admin_input
  expect and {
      // Pool Input and Output Address must be unchanged (both Payment and Stake Credential)
      pool_in_address == pool_out_address,
      // Pool Datum must be unchanged
      pool_in_datum == pool_out_datum,
      value.quantity_of(pool_in_value, authen_policy_id, pool_auth_asset_name) == 1,
      // validate Admin with valid Admin License Token must be presented in Transaction Inputs.
      value.quantity_of(admin_value, admin_policy_id, admin_asset_name) == 1,
    }
  let PoolDatum {
    asset_a,
    asset_b,
    reserve_a: datum_reserve_a_in,
    reserve_b: datum_reserve_b_in,
    ..
  } = pool_in_datum
  let Asset { policy_id: asset_a_policy_id, asset_name: asset_a_asset_name } =
    asset_a
  let Asset { policy_id: asset_b_policy_id, asset_name: asset_b_asset_name } =
    asset_b
  let temp_value_reserve_a_in =
    value.quantity_of(pool_in_value, asset_a_policy_id, asset_a_asset_name)
  let value_reserve_a_in =
    if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
      temp_value_reserve_a_in - 3000000
    } else {
      temp_value_reserve_a_in
    }
  let value_reserve_b_in =
    value.quantity_of(pool_in_value, asset_b_policy_id, asset_b_asset_name)
  // validate Admin withdraws the exact earned Profit Sharing amount:
  //    Earned Asset A: Reserve A in Value - Reserve A in Datum
  //    Earned Asset B: Reserve B in Value - Reserve B in Datum
  let expected_pool_out_value =
    pool_in_value
      |> value.add(
           asset_a_policy_id,
           asset_a_asset_name,
           datum_reserve_a_in - value_reserve_a_in,
         )
      |> value.add(
           asset_b_policy_id,
           asset_b_asset_name,
           datum_reserve_b_in - value_reserve_b_in,
         )
  pool_out_value == expected_pool_out_value
}

// This function will validate Mint part in Pool Creation Transaction
// Transaction must mint only 1 Factory Asset + 1 Pool Asset + MAX INT64 LP Asset
// Otherwise transaction must be failed
pub fn get_pool_creation_expected_mint(
  authen_policy_id: PolicyId,
  lp_asset_name: AssetName,
) -> Value {
  value.zero()
    |> value.add(authen_policy_id, factory_auth_asset_name, 1)
    |> value.add(authen_policy_id, pool_auth_asset_name, 1)
    |> value.add(authen_policy_id, lp_asset_name, 9223372036854775807)
}

// This function get Pool output from output list and make sure there's single Pool Output
fn get_single_pool_output(
  all_outputs: List<Output>,
  pool_payment_credential: PaymentCredential,
) -> Output {
  expect [pool_output] =
    list.filter(
      all_outputs,
      fn(o) {
        let Output { address: addr, .. } = o
        let Address { payment_credential, .. } = addr
        payment_credential == pool_payment_credential
      },
    )
  pool_output
}
