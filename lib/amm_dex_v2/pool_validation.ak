use aiken/dict.{Dict}
use aiken/hash.{Blake2b_224, Hash}
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list
use aiken/transaction.{
  Input, Output, Redeemer, ScriptPurpose, Spend, ValidityRange,
}
use aiken/transaction/credential.{
  Address, Inline, PaymentCredential, ScriptCredential, StakeCredential,
  VerificationKey, VerificationKeyCredential,
}
use aiken/transaction/value.{
  AssetName, PolicyId, Value, ada_asset_name, ada_policy_id,
}
use amm_dex_v2/types.{
  Asset, BatchingPool, PoolDatum, UpdatePoolFee,
  UpdatePoolFeeOrStakeCredentialAction, UpdatePoolStakeCredential,
}
use amm_dex_v2/utils

pub fn validate_license_expiration_and_find_license_holder(
  license_pid: PolicyId,
  license_input: Input,
  validity_range: ValidityRange,
) -> (Address, Int) {
  let Input {
    output: Output { address: license_holder_addr, value: license_value, .. },
    ..
  } = license_input
  expect [(license_asset_name, license_amount)] =
    license_value
      |> value.tokens(license_pid)
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
      license_deadline <= start_valid_time_range + utils.maximum_deadline_range,
    }
  (license_holder_addr, end_valid_time_range)
}

pub fn get_batching_pool(
  stake_credential: StakeCredential,
  pool_input: Output,
  pool_output: Output,
  authen_policy_id: PolicyId,
  require_total_liquidity_unchange: Bool,
  vol_fee: Option<Int>,
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
    utils.must_find_script_inline_datum(pool_in_datum_raw)

  let PoolDatum {
    pool_batching_stake_credential: pool_in_stake_credential,
    asset_a: pool_in_asset_a,
    asset_b: pool_in_asset_b,
    total_liquidity: pool_in_total_liquidity,
    reserve_a: pool_in_datum_reserve_a,
    reserve_b: pool_in_datum_reserve_b,
    base_fee_a_numerator: pool_in_base_fee_a_numerator,
    base_fee_b_numerator: pool_in_base_fee_b_numerator,
    fee_sharing_numerator_opt: pool_in_fee_sharing_numerator_opt,
    allow_dynamic_fee: pool_in_allow_dynamic_fee,
  } = pool_in_datum
  expect pool_out_datum: PoolDatum =
    utils.must_find_script_inline_datum(pool_out_datum_raw)
  let PoolDatum {
    pool_batching_stake_credential: pool_out_stake_credential,
    asset_a: pool_out_asset_a,
    asset_b: pool_out_asset_b,
    total_liquidity: pool_out_total_liquidity,
    reserve_a: pool_out_datum_reserve_a,
    reserve_b: pool_out_datum_reserve_b,
    base_fee_a_numerator: pool_out_base_fee_a_numerator,
    base_fee_b_numerator: pool_out_base_fee_b_numerator,
    fee_sharing_numerator_opt: pool_out_fee_sharing_numerator_opt,
    allow_dynamic_fee: pool_out_allow_dynamic_fee,
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
      pool_in_base_fee_a_numerator == pool_out_base_fee_a_numerator,
      pool_in_base_fee_b_numerator == pool_out_base_fee_b_numerator,
      pool_in_fee_sharing_numerator_opt == pool_out_fee_sharing_numerator_opt,
      pool_in_allow_dynamic_fee == pool_out_allow_dynamic_fee,
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
      |> value.add(authen_policy_id, utils.pool_auth_asset_name, 1)
      |> value.add(asset_a_policy_id, asset_a_asset_name, value_reserve_a_in)
      |> value.add(asset_b_policy_id, asset_b_asset_name, value_reserve_b_in)
      |> value.add(authen_policy_id, lp_asset_name, remaining_liquidity_supply_in)
  let estimate_pool_out_value =
    value.zero()
      |> value.add(ada_policy_id, ada_asset_name, 3000000)
      |> value.add(authen_policy_id, utils.pool_auth_asset_name, 1)
      |> value.add(asset_a_policy_id, asset_a_asset_name, value_reserve_a_out)
      |> value.add(asset_b_policy_id, asset_b_asset_name, value_reserve_b_out)
      |> value.add(authen_policy_id, lp_asset_name, remaining_liquidity_supply_out)
  expect and {
      estimate_pool_in_value == pool_in_value,
      estimate_pool_out_value == pool_out_value,
      remaining_liquidity_supply_out - remaining_liquidity_supply_in == pool_in_total_liquidity - pool_out_total_liquidity,
    }

  let trading_fee_a_numerator =
    get_trading_fee_numerator(
      base_fee_num: pool_in_base_fee_a_numerator,
      vol_fee_opt: vol_fee,
      allow_dynamic_fee: pool_in_allow_dynamic_fee,
    )
  let trading_fee_b_numerator =
    get_trading_fee_numerator(
      base_fee_num: pool_in_base_fee_b_numerator,
      vol_fee_opt: vol_fee,
      allow_dynamic_fee: pool_in_allow_dynamic_fee,
    )
  BatchingPool {
    asset_a: pool_in_asset_a,
    asset_b: pool_in_asset_b,
    lp_asset,
    trading_fee_a_numerator,
    trading_fee_b_numerator,
    fee_sharing_numerator_opt: pool_in_fee_sharing_numerator_opt,
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
  pool_input: Input,
  pool_in_datum: PoolDatum,
  all_outputs: List<Output>,
) -> Bool {
  let Input { output: pool_in_output, .. } = pool_input
  let Output { address: pool_in_address, value: pool_in_value, .. } =
    pool_in_output
  let Address { payment_credential: pool_in_address_payment_credential, .. } =
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
      pool_payment_credential: pool_in_address_payment_credential,
    )
  expect and {
      // Pool Input contains 1 valid Pool NFT Token
      value.quantity_of(
        pool_in_value,
        authen_policy_id,
        utils.pool_auth_asset_name,
      ) == 1,
      // Pool Value must be unchanged
      pool_in_value == pool_out_value,
    }
  expect pool_out_datum: PoolDatum =
    utils.must_find_script_inline_datum(raw_pool_out_datum)
  when action is {
    UpdatePoolFee -> {
      let PoolDatum {
        pool_batching_stake_credential: pool_in_stake_credential,
        asset_a: pool_in_asset_a,
        asset_b: pool_in_asset_b,
        total_liquidity: pool_in_total_liquidity,
        reserve_a: pool_in_reserve_a,
        reserve_b: pool_in_reserve_b,
        ..
      } = pool_in_datum
      let PoolDatum {
        pool_batching_stake_credential: pool_out_stake_credential,
        asset_a: pool_out_asset_a,
        asset_b: pool_out_asset_b,
        total_liquidity: pool_out_total_liquidity,
        reserve_a: pool_out_reserve_a,
        reserve_b: pool_out_reserve_b,
        base_fee_a_numerator: pool_out_base_fee_a_numerator,
        base_fee_b_numerator: pool_out_base_fee_b_numerator,
        fee_sharing_numerator_opt: pool_out_fee_sharing_numerator_opt,
        ..
      } = pool_out_datum
      // Profit Sharing can be on/off by setting fee_sharing_numerator_opt is None or Some. 
      // Profit Sharing must be between **16.66%** and **50%**
      let is_valid_fee_sharing =
        when pool_out_fee_sharing_numerator_opt is {
          None -> True
          Some(pool_out_fee_sharing_numerator) ->
            validate_fee_percent(
              fee_num: pool_out_fee_sharing_numerator,
              max_fee_num: utils.max_fee_sharing_numerator,
              min_fee_num: utils.min_fee_sharing_numerator,
            )
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
        validate_fee_percent(
          fee_num: pool_out_base_fee_a_numerator,
          max_fee_num: utils.max_base_fee_numerator,
          min_fee_num: utils.min_base_fee_numerator,
        ),
        validate_fee_percent(
          fee_num: pool_out_base_fee_b_numerator,
          max_fee_num: utils.max_base_fee_numerator,
          min_fee_num: utils.min_base_fee_numerator,
        ),
        is_valid_fee_sharing,
      }
    }
    // Pool Datum must be unchanged
    UpdatePoolStakeCredential -> pool_in_datum == pool_out_datum
  }
}

pub fn validate_fee_percent(
  fee_num: Int,
  max_fee_num: Int,
  min_fee_num: Int,
) -> Bool {
  and {
    // less than max
    fee_num <= max_fee_num,
    // greater than min
    fee_num >= min_fee_num,
  }
}

pub fn validate_withdraw_liquidity_share(
  authen_policy_id: PolicyId,
  pool_input: Input,
  pool_in_datum: PoolDatum,
  all_outputs: List<Output>,
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
    utils.must_find_script_inline_datum(raw_pool_out_datum)
  expect and {
      // Pool Input and Output Address must be unchanged (both Payment and Stake Credential)
      pool_in_address == pool_out_address,
      // Pool Datum must be unchanged
      pool_in_datum == pool_out_datum,
      value.quantity_of(
        pool_in_value,
        authen_policy_id,
        utils.pool_auth_asset_name,
      ) == 1,
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
    |> value.add(authen_policy_id, utils.factory_auth_asset_name, 1)
    |> value.add(authen_policy_id, utils.pool_auth_asset_name, 1)
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

pub fn get_trading_fee_numerator(
  base_fee_num: Int,
  vol_fee_opt: Option<Int>,
  allow_dynamic_fee: Bool,
) -> Int {
  let trading_fee_num =
    if allow_dynamic_fee {
      when vol_fee_opt is {
        None -> base_fee_num
        Some(vol_fee_num) -> {
          expect
            validate_fee_percent(
              fee_num: vol_fee_num,
              max_fee_num: utils.max_vol_fee_numerator,
              min_fee_num: utils.min_vol_fee_numerator,
            )
          vol_fee_num + base_fee_num
        }
      }
    } else {
      base_fee_num
    }

  expect
    validate_fee_percent(
      fee_num: trading_fee_num,
      max_fee_num: utils.max_trading_fee_numerator,
      min_fee_num: utils.min_trading_fee_numerator,
    )
  trading_fee_num
}

test test_get_trading_fee_numerator() {
  and {
    get_trading_fee_numerator(
      base_fee_num: 1000,
      vol_fee_opt: None,
      allow_dynamic_fee: False,
    ) == 1000,
    get_trading_fee_numerator(
      base_fee_num: 1000,
      vol_fee_opt: Some(200),
      allow_dynamic_fee: False,
    ) == 1000,
    get_trading_fee_numerator(
      base_fee_num: 800,
      vol_fee_opt: Some(200),
      allow_dynamic_fee: True,
    ) == 1000,
    get_trading_fee_numerator(
      base_fee_num: 900,
      vol_fee_opt: Some(100),
      allow_dynamic_fee: True,
    ) == 1000,
  }
}

test test_get_trading_fee_numerator_fail_1() fail {
  get_trading_fee_numerator(
    base_fee_num: 900,
    vol_fee_opt: Some(300),
    allow_dynamic_fee: True,
  ) == 1200
}

test test_get_trading_fee_numerator_fail_2() fail {
  get_trading_fee_numerator(
    base_fee_num: 1100,
    vol_fee_opt: Some(200),
    allow_dynamic_fee: True,
  ) == 1300
}

test test_get_trading_fee_numerator_fail_3() fail {
  get_trading_fee_numerator(
    base_fee_num: 900,
    vol_fee_opt: Some(200),
    allow_dynamic_fee: True,
  ) == 1100
}

pub fn has_single_spending(redeemers: Dict<ScriptPurpose, Redeemer>) -> Bool {
  expect [_] =
    redeemers
      |> dict.to_list
      |> list.filter(
           fn(r) {
             let (p, _) = r
             when p is {
               Spend(_) -> True
               _ -> False
             }
           },
         )
  True
}

pub fn is_admin_existence(
  admin_policy_id: PolicyId,
  reference_inputs: List<Input>,
  withdrawals: Dict<StakeCredential, Int>,
  signatories: List<Hash<Blake2b_224, VerificationKey>>,
  validity_range: ValidityRange,
) -> Bool {
  let admin_input_opt =
    list.find(
      reference_inputs,
      fn(input) {
        let Input { output: Output { value: val, .. }, .. } = input
        ( val |> value.tokens(admin_policy_id) |> dict.size() ) > 0
      },
    )
  when admin_input_opt is {
    Some(admin_input) -> {
      let (_, _) =
        validate_license_expiration_and_find_license_holder(
          license_pid: admin_policy_id,
          license_input: admin_input,
          validity_range: validity_range,
        )
      let Input {
        output: Output {
          address: Address { payment_credential: payment_cred, .. },
          ..
        },
        ..
      } = admin_input
      when payment_cred is {
        VerificationKeyCredential(pub_key_hash) ->
          list.has(signatories, pub_key_hash)
        ScriptCredential(_) -> dict.has_key(withdrawals, Inline(payment_cred))
      }
    }
    _ -> False
  }
}
