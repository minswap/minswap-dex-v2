use aiken/builtin
use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list
use aiken/transaction.{Input, Output, OutputReference, ValidityRange}
use aiken/transaction/credential.{Address, PaymentCredential, ScriptCredential}
use aiken/transaction/value.{
  AssetName, PolicyId, Value, ada_asset_name, ada_policy_id,
}
use amm_dex_v2/order_validation
use amm_dex_v2/types.{
  Asset, BatchingPool, DatumMap, OrderDatum, PoolDatum, SwapMultiRouting,
  UpdatePoolFee, UpdatePoolFeeOrStakeCredentialAction, UpdatePoolStakeCredential,
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

fn find_pool_input_and_output_in_batching(
  pool_input_ref: OutputReference,
  inputs: List<Input>,
  outputs: List<Output>,
) -> (Output, Output) {
  expect Some(pool_input) =
    list.find(
      inputs,
      fn(input) {
        let Input { output_reference: out_ref, .. } = input
        pool_input_ref == out_ref
      },
    )
  let Input { output: pool_in_output, .. } = pool_input
  let Output { address: pool_in_address, .. } = pool_in_output
  let Address { payment_credential: pool_payment_credential, .. } =
    pool_in_address

  // Batching transaction requires single Pool UTxO in both Inputs and Outputs
  let pool_output =
    get_single_pool_output(
      all_outputs: outputs,
      pool_payment_credential: pool_payment_credential,
    )
  let Output { address: pool_out_address, .. } = pool_output
  expect pool_out_address == pool_in_address
  // Due to combination with Minswap Stake Address, Pool Contract can have multiple Base Addresses
  // This logic will verify that the transaction is processing in single Pool
  // Verify that having only one Pool Input and Pool Output in the transaction
  expect [_] =
    list.filter(
      inputs,
      fn(input) {
        let Input { output: o, .. } = input
        let Output { address: addr, .. } = o
        let Address { payment_credential: payment_cred, .. } = addr
        payment_cred == pool_payment_credential
      },
    )
  (pool_in_output, pool_output)
}

fn get_batching_pool(
  pool_input: Output,
  pool_output: Output,
  authen_policy_id: PolicyId,
  pool_in_datum: PoolDatum,
  datum_map: DatumMap,
  require_total_liquidity_unchange: Bool,
) -> BatchingPool {
  let Output { address: pool_in_address, value: pool_in_value, .. } = pool_input
  let Output { value: pool_out_value, datum: pool_out_datum_raw, .. } =
    pool_output

  let PoolDatum {
    asset_a: pool_in_asset_a,
    asset_b: pool_in_asset_b,
    total_liquidity: pool_in_total_liquidity,
    reserve_a: pool_in_datum_reserve_a,
    reserve_b: pool_in_datum_reserve_b,
    trading_fee_numerator: pool_in_trading_fee_numerator,
    trading_fee_denominator: pool_in_trading_fee_denominator,
    order_hash: pool_in_order_hash,
    profit_sharing_opt: pool_in_profit_sharing_opt,
  } = pool_in_datum
  expect pool_out_datum: PoolDatum =
    utils.must_find_script_datum(datum_map, pool_out_datum_raw)
  let PoolDatum {
    asset_a: pool_out_asset_a,
    asset_b: pool_out_asset_b,
    total_liquidity: pool_out_total_liquidity,
    reserve_a: pool_out_datum_reserve_a,
    reserve_b: pool_out_datum_reserve_b,
    trading_fee_numerator: pool_out_trading_fee_numerator,
    trading_fee_denominator: pool_out_trading_fee_denominator,
    order_hash: pool_out_order_hash,
    profit_sharing_opt: pool_out_profit_sharing_opt,
  } = pool_out_datum

  expect
    if require_total_liquidity_unchange {
      pool_in_total_liquidity == pool_out_total_liquidity
    } else {
      True
    }
  expect and {
      pool_in_asset_a == pool_out_asset_a,
      pool_in_asset_b == pool_out_asset_b,
      pool_in_trading_fee_numerator == pool_out_trading_fee_numerator,
      pool_in_trading_fee_denominator == pool_out_trading_fee_denominator,
      pool_in_order_hash == pool_out_order_hash,
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
    order_hash: pool_in_order_hash,
    address: pool_in_address,
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

pub fn validate_batching(
  authen_policy_id: PolicyId,
  all_inputs: List<Input>,
  all_outputs: List<Output>,
  all_datums: DatumMap,
  pool_input_ref: OutputReference,
  pool_in_datum: PoolDatum,
  batcher_address: Address,
  end_valid_time_range: Int,
  input_indexes: List<Int>,
  orders_fee: List<Int>,
) -> Bool {
  let (pool_input, pool_output) =
    find_pool_input_and_output_in_batching(
      pool_input_ref: pool_input_ref,
      inputs: all_inputs,
      outputs: all_outputs,
    )
  let BatchingPool {
    asset_a,
    asset_b,
    lp_asset,
    trading_fee_numerator,
    trading_fee_denominator,
    profit_sharing,
    order_hash,
    address: pool_address,
    pool_state_in,
    pool_state_out,
  } =
    get_batching_pool(
      pool_input: pool_input,
      pool_output: pool_output,
      authen_policy_id: authen_policy_id,
      pool_in_datum: pool_in_datum,
      datum_map: all_datums,
      require_total_liquidity_unchange: False,
    )
  let user_inputs =
    list.filter(
      all_inputs,
      fn(input) {
        let Input { output: out, .. } = input
        let Output { address: addr, .. } = out
        let Address { payment_credential: payment_cred, .. } = addr
        when payment_cred is {
          ScriptCredential(hash) -> hash == order_hash
          _ -> False
        }
      },
    )
  // Currently, transaction inputs will be sorted by TxId and TxIndex of UTxO.
  // We have to calculate indexes of orders inputs sorting by the ASC created time
  // on the off-chain and on-chain will sort the TxIns by the indexes
  // Input Indexes in parameter will be reversed indexs of @order_inputs to reduce calculate step in On-Chain
  let sorted_user_inputs =
    list.foldl(
      input_indexes,
      [],
      fn(idx, ips) { list.push(ips, utils.list_at_index(user_inputs, idx)) },
    )

  // Order Outputs are Outputs which aren't Pool & Batcher UTxOs
  // Their ordering must be the same with @sorted_order_inputs, so @order_outputs at index i is the output if @sorted_order_inputs at index i
  let user_outputs =
    list.filter(
      all_outputs,
      fn(output) {
        let Output { address: addr, .. } = output
        addr != pool_address && addr != batcher_address
      },
    )

  expect and {
      // User Inputs and Input Indexes must have the same length
      utils.compare_list_length(input_indexes, user_inputs),
      // User Inputs and Outputs must have the same length
      utils.compare_list_length(sorted_user_inputs, user_outputs),
    }
  pool_state_out == order_validation.apply_orders(
    datum_map: all_datums,
    asset_a: asset_a,
    asset_b: asset_b,
    lp_asset: lp_asset,
    trading_fee_numerator: trading_fee_numerator,
    trading_fee_denominator: trading_fee_denominator,
    order_hash: order_hash,
    profit_sharing_opt: profit_sharing,
    end_valid_time_range: end_valid_time_range,
    order_inputs: sorted_user_inputs,
    order_outputs: user_outputs,
    orders_fee: orders_fee,
    pool_state: pool_state_in,
  )
}

pub fn validate_swap_multi_routing(
  authen_policy_id: PolicyId,
  all_inputs: List<Input>,
  all_outputs: List<Output>,
  all_datums: DatumMap,
  pool_input_ref: OutputReference,
  batcher_address: Address,
  end_valid_time_range: Int,
  routing_in_indexes: List<Int>,
  routing_out_indexes: List<Int>,
  order_fee: Int,
) -> Bool {
  let batching_pools =
    find_multi_routing_pools(
      authen_policy_id: authen_policy_id,
      pool_input_ref: pool_input_ref,
      inputs: all_inputs,
      outputs: all_outputs,
      routing_in_indexes: routing_in_indexes,
      routing_out_indexes: routing_out_indexes,
      datum_map: all_datums,
    )

  let BatchingPool {
    order_hash,
    address: Address { payment_credential: pool_payment_credential, .. },
    lp_asset: pool_lp_asset,
    ..
  } = batching_pools |> builtin.head_list

  expect [order_input] =
    list.filter(
      all_inputs,
      fn(input) {
        let Input {
          output: Output {
            address: Address { payment_credential: payment_cred, .. },
            ..
          },
          ..
        } = input
        when payment_cred is {
          ScriptCredential(hash) -> hash == order_hash
          _ -> False
        }
      },
    )
  expect [order_output] =
    list.filter(
      all_outputs,
      fn(output) {
        let Output { address: addr, .. } = output
        let Address { payment_credential: payment_cred, .. } = addr
        addr != batcher_address && payment_cred != pool_payment_credential
      },
    )
  let Input {
    output: Output { value: order_in_value, datum: raw_order_in_datum, .. },
    ..
  } = order_input
  let Output { value: order_out_value, .. } = order_output
  expect order_in_datum: OrderDatum =
    utils.must_find_script_datum(all_datums, raw_order_in_datum)
  let OrderDatum {
    receiver,
    receiver_datum_hash_opt,
    step: order_step,
    max_batcher_fee,
    output_ada,
    lp_asset: order_lp_asset,
    expired_time_opt,
    ..
  } = order_in_datum
  expect and {
      // max_batcher_fee and output_ada must be positive
      max_batcher_fee > 0,
      output_ada > 0,
      // Used Batcher Fee must be positive and less than or equal batcher fee
      order_fee > 0,
      order_fee <= max_batcher_fee,
      // Order Output must be returned to receiver and might have receiver_datum_hash_opt
      order_validation.validate_order_receiver(
        receiver: receiver,
        receiver_datum_hash_opt: receiver_datum_hash_opt,
        output: order_output,
      ),
      // lp_asset in OrderDatum must be the same with LP Asset of first Liquidity Pool in routing list
      pool_lp_asset == order_lp_asset,
      when expired_time_opt is {
        None -> True
        Some(expired_time) -> end_valid_time_range <= expired_time
      },
    }
  when order_step is {
    SwapMultiRouting(routings, swap_amount, minimum_receive) -> {
      expect and {
          swap_amount > 0,
          minimum_receive > 0,
          // The number of Pool Inputs and Pool Outputs must be the same with _routings_ length
          utils.compare_list_length(batching_pools, routings),
        }
      order_validation.validate_swap_multi_routing_order(
        pools: batching_pools,
        routings: routings,
        order_in_value: order_in_value,
        order_out_value: order_out_value,
        swap_amount: swap_amount,
        minimum_receive: minimum_receive,
        used_batcher_fee: order_fee,
      )
    }
    _ -> False
  }
}

// TODO: We need carefully verify these logic below 
fn find_multi_routing_pools(
  authen_policy_id: PolicyId,
  pool_input_ref: OutputReference,
  inputs: List<Input>,
  outputs: List<Output>,
  routing_in_indexes: List<Int>,
  routing_out_indexes: List<Int>,
  datum_map: DatumMap,
) -> List<BatchingPool> {
  let pool_ins =
    list.map(routing_in_indexes, fn(idx) { utils.list_at_index(inputs, idx) })

  let pool_outs =
    list.map(routing_out_indexes, fn(idx) { utils.list_at_index(outputs, idx) })

  let pool_len = list.length(pool_ins)

  // find input of current script
  expect [own_pool_input] =
    list.filter(
      inputs,
      fn(input) {
        let Input { output_reference: out_ref, .. } = input
        pool_input_ref == out_ref
      },
    )
  let Input {
    output: Output {
      address: Address { payment_credential: own_pool_payment_credential, .. },
      ..
    },
    ..
  } = own_pool_input
  // verify that there's only 2 pools the inputs
  expect
    list.length(
      list.filter(
        inputs,
        fn(input) {
          let Input {
            output: Output { address: Address { payment_credential, .. }, .. },
            ..
          } = input
          payment_credential == own_pool_payment_credential
        },
      ),
    ) == pool_len
  // verify that there's only 2 pools the outputs
  expect
    list.length(
      list.filter(
        outputs,
        fn(output) {
          let Output { address: Address { payment_credential, .. }, .. } =
            output
          payment_credential == own_pool_payment_credential
        },
      ),
    ) == pool_len
  utils.zip_with(
    pool_ins,
    pool_outs,
    fn(pool_in, pool_out) {
      let Input { output: pool_in_output, .. } = pool_in
      let Output { address: pool_in_address, datum: pool_in_datum_raw, .. } =
        pool_in_output
      let Output { address: pool_out_address, .. } = pool_out
      expect pool_in_datum: PoolDatum =
        utils.must_find_script_datum(datum_map, pool_in_datum_raw)

      expect pool_in_address == pool_out_address
      get_batching_pool(
        pool_input: pool_in_output,
        pool_output: pool_out,
        authen_policy_id: authen_policy_id,
        pool_in_datum: pool_in_datum,
        datum_map: datum_map,
        require_total_liquidity_unchange: True,
      )
    },
  )
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
        asset_a: pool_in_asset_a,
        asset_b: pool_in_asset_b,
        total_liquidity: pool_in_total_liquidity,
        reserve_a: pool_in_reserve_a,
        reserve_b: pool_in_reserve_b,
        order_hash: pool_in_order_hash,
        ..
      } = pool_in_datum
      let PoolDatum {
        asset_a: pool_out_asset_a,
        asset_b: pool_out_asset_b,
        total_liquidity: pool_out_total_liquidity,
        reserve_a: pool_out_reserve_a,
        reserve_b: pool_out_reserve_b,
        trading_fee_numerator: pool_out_trading_fee_numerator,
        trading_fee_denominator: pool_out_trading_fee_denominator,
        order_hash: pool_out_order_hash,
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
        pool_in_asset_a == pool_out_asset_a,
        pool_in_asset_b == pool_out_asset_b,
        pool_in_total_liquidity == pool_out_total_liquidity,
        pool_in_reserve_a == pool_out_reserve_a,
        pool_in_reserve_b == pool_out_reserve_b,
        pool_in_order_hash == pool_out_order_hash,
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
