use aiken/builtin
use aiken/hash
use aiken/list
use aiken/transaction.{DatumHash, InlineDatum, Input, NoDatum, Output}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{Value, ada_asset_name, ada_policy_id}
use amm_dex_v2/math
use amm_dex_v2/types.{
  AToB, Asset, BToA, BatchingPool, CustomDatumHash, DatumMap, Deposit, OCO,
  OrderDatum, PartialSwap, PoolState, StopLoss, SwapExactIn, SwapExactOut,
  SwapMultiRouting, SwapRouting, Withdraw, ZapOut,
}
use amm_dex_v2/utils

fn validate_swap_exact_in(
  order_in_value: Value,
  order_out_value: Value,
  a_to_b_direction: Bool,
  asset_a: Asset,
  asset_b: Asset,
  batcher_fee: Int,
  output_ada: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  pool_state: PoolState,
  checking_slippage_fn: fn(Int) -> Bool,
) -> PoolState {
  let (
    datum_reserve_a,
    datum_reserve_b,
    value_reserve_a,
    value_reserve_b,
    total_liquidity,
  ) = pool_state
  let (asset_in, asset_out, reserve_in, reserve_out) =
    if a_to_b_direction {
      (asset_a, asset_b, datum_reserve_a, datum_reserve_b)
    } else {
      (asset_b, asset_a, datum_reserve_b, datum_reserve_a)
    }
  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let temp_amount_in =
    value.quantity_of(order_in_value, asset_in_policy_id, asset_in_asset_name)
  let amount_in =
    if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
      temp_amount_in - ( batcher_fee + output_ada )
    } else {
      temp_amount_in
    }
  let has_enough_amount_in = amount_in > 0
  let amount_out =
    math.calculate_amount_out(
      reserve_in: reserve_in,
      reserve_out: reserve_out,
      amount_in: amount_in,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
    )
  let earned_fee_in =
    when profit_sharing_opt is {
      Some((fee_sharing_numerator, fee_sharing_denominator)) ->
        math.calculate_earned_fee_in(
          amount_in: amount_in,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
          fee_sharing_numerator: fee_sharing_numerator,
          fee_sharing_denominator: fee_sharing_denominator,
        )
      None -> 0
    }
  let not_over_slippage = checking_slippage_fn(amount_out)
  let actual_amount_out =
    value.quantity_of(
      order_out_value,
      asset_out_policy_id,
      asset_out_asset_name,
    )
  let is_valid_amount_out =
    if utils.is_ada_asset(asset_out_policy_id, asset_out_asset_name) {
      amount_out + output_ada == actual_amount_out
    } else {
      let ada_amount =
        value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
      amount_out == actual_amount_out && ada_amount == output_ada
    }
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  if a_to_b_direction {
    (
      datum_reserve_a + amount_in - earned_fee_in,
      datum_reserve_b - amount_out,
      value_reserve_a + amount_in,
      value_reserve_b - amount_out,
      total_liquidity,
    )
  } else {
    (
      datum_reserve_a - amount_out,
      datum_reserve_b + amount_in - earned_fee_in,
      value_reserve_a - amount_out,
      value_reserve_b + amount_in,
      total_liquidity,
    )
  }
}

fn validate_swap_exact_out(
  order_in_value: Value,
  order_out_value: Value,
  a_to_b_direction: Bool,
  expected_receive: Int,
  asset_a: Asset,
  asset_b: Asset,
  batcher_fee: Int,
  output_ada: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  pool_state: PoolState,
) -> PoolState {
  let (
    datum_reserve_a,
    datum_reserve_b,
    value_reserve_a,
    value_reserve_b,
    total_liquidity,
  ) = pool_state
  let (asset_in, asset_out, reserve_in, reserve_out) =
    if a_to_b_direction {
      (asset_a, asset_b, datum_reserve_a, datum_reserve_b)
    } else {
      (asset_b, asset_a, datum_reserve_b, datum_reserve_a)
    }
  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let temp_amount_in =
    value.quantity_of(order_in_value, asset_in_policy_id, asset_in_asset_name)
  let maximum_amount_in =
    if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
      temp_amount_in - ( batcher_fee + output_ada )
    } else {
      temp_amount_in
    }
  let has_enough_amount_in = maximum_amount_in > 0
  let necessary_amount_in =
    math.calculate_amount_in(
      reserve_in,
      reserve_out,
      expected_receive,
      trading_fee_numerator,
      trading_fee_denominator,
    )
  let earned_fee_in =
    when profit_sharing_opt is {
      Some((fee_sharing_numerator, fee_sharing_denominator)) ->
        math.calculate_earned_fee_in(
          amount_in: necessary_amount_in,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
          fee_sharing_numerator: fee_sharing_numerator,
          fee_sharing_denominator: fee_sharing_denominator,
        )
      None -> 0
    }
  let not_over_slippage = necessary_amount_in <= maximum_amount_in
  let actual_amount_out =
    value.quantity_of(
      order_out_value,
      asset_out_policy_id,
      asset_out_asset_name,
    )
  let ada_amount =
    value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
  let change_amount_in =
    value.quantity_of(order_out_value, asset_in_policy_id, asset_in_asset_name)
  let is_valid_amount_out =
    if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
      actual_amount_out == expected_receive && ada_amount == output_ada + maximum_amount_in - necessary_amount_in
    } else if
    utils.is_ada_asset(asset_out_policy_id, asset_out_asset_name){
    
      actual_amount_out == expected_receive + output_ada && change_amount_in == maximum_amount_in - necessary_amount_in
    } else {
      actual_amount_out == expected_receive && change_amount_in == maximum_amount_in - necessary_amount_in && ada_amount == output_ada
    }
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  if a_to_b_direction {
    (
      datum_reserve_a + necessary_amount_in - earned_fee_in,
      datum_reserve_b - expected_receive,
      value_reserve_a + necessary_amount_in,
      value_reserve_b - expected_receive,
      total_liquidity,
    )
  } else {
    (
      datum_reserve_a - expected_receive,
      datum_reserve_b + necessary_amount_in - earned_fee_in,
      value_reserve_a - expected_receive,
      value_reserve_b + necessary_amount_in,
      total_liquidity,
    )
  }
}

fn validate_deposit(
  order_in_value: Value,
  order_out_value: Value,
  minimum_lp: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  batcher_fee: Int,
  output_ada: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  pool_state: PoolState,
) -> PoolState {
  let (
    datum_reserve_a,
    datum_reserve_b,
    value_reserve_a,
    value_reserve_b,
    total_liquidity,
  ) = pool_state
  let Asset { policy_id: asset_a_policy_id, asset_name: asset_a_asset_name } =
    asset_a
  let Asset { policy_id: asset_b_policy_id, asset_name: asset_b_asset_name } =
    asset_b
  let Asset { policy_id: lp_asset_policy_id, asset_name: lp_asset_asset_name } =
    lp_asset
  let temp_amount_a =
    value.quantity_of(order_in_value, asset_a_policy_id, asset_a_asset_name)
  let amount_b =
    value.quantity_of(order_in_value, asset_b_policy_id, asset_b_asset_name)
  let amount_a =
    if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
      temp_amount_a - ( batcher_fee + output_ada )
    } else {
      temp_amount_a
    }
  let has_enough_amount_in =
    amount_a >= 0 && amount_b >= 0 && amount_a + amount_b > 0
  let (earned_fee_a, earned_fee_b, lp_amount) =
    math.calculate_deposit_amount(
      amount_a: amount_a,
      amount_b: amount_b,
      reserve_a: datum_reserve_a,
      reserve_b: datum_reserve_b,
      total_liquidity: total_liquidity,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
      profit_sharing_opt: profit_sharing_opt,
    )
  let not_over_slippage = lp_amount >= minimum_lp
  let lp_amount_out =
    value.quantity_of(order_out_value, lp_asset_policy_id, lp_asset_asset_name)
  let ada_amount_out =
    value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)

  let is_valid_amount_out =
    ada_amount_out == output_ada && lp_amount_out == lp_amount
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  (
    datum_reserve_a + amount_a - earned_fee_a,
    datum_reserve_b + amount_b - earned_fee_b,
    value_reserve_a + amount_a,
    value_reserve_b + amount_b,
    total_liquidity + lp_amount,
  )
}

fn validate_withdraw(
  order_in_value: Value,
  order_out_value: Value,
  minimum_amount_a: Int,
  minimum_amount_b: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  output_ada: Int,
  pool_state: PoolState,
) -> PoolState {
  let (
    datum_reserve_a,
    datum_reserve_b,
    value_reserve_a,
    value_reserve_b,
    total_liquidity,
  ) = pool_state
  let Asset { policy_id: asset_a_policy_id, asset_name: asset_a_asset_name } =
    asset_a
  let Asset { policy_id: asset_b_policy_id, asset_name: asset_b_asset_name } =
    asset_b
  let Asset { policy_id: lp_policy_id, asset_name: lp_asset_name } = lp_asset
  let withdrawal_lp_amount =
    value.quantity_of(order_in_value, lp_policy_id, lp_asset_name)
  let has_enough_amount_in = withdrawal_lp_amount > 0
  let (amount_a_out, amount_b_out) =
    math.calculate_withdraw(
      datum_reserve_a,
      datum_reserve_b,
      withdrawal_lp_amount,
      total_liquidity,
    )
  let not_over_slippage =
    amount_a_out >= minimum_amount_a && amount_b_out >= minimum_amount_b
  let actual_amount_a_out =
    value.quantity_of(order_out_value, asset_a_policy_id, asset_a_asset_name)
  let actual_amount_b_out =
    value.quantity_of(order_out_value, asset_b_policy_id, asset_b_asset_name)
  let ada_amount_out =
    value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
  let is_valid_amount_out =
    if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
      actual_amount_a_out == amount_a_out + output_ada && actual_amount_b_out == amount_b_out
    } else {
      ada_amount_out == output_ada && actual_amount_a_out == amount_a_out && actual_amount_b_out == amount_b_out
    }
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  (
    datum_reserve_a - amount_a_out,
    datum_reserve_b - amount_b_out,
    value_reserve_a - amount_a_out,
    value_reserve_b - amount_b_out,
    total_liquidity - withdrawal_lp_amount,
  )
}

fn validate_zap_out(
  order_in_value: Value,
  order_out_value: Value,
  minimum_receive: Int,
  a_to_b_direction: Bool,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  output_ada: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  pool_state: PoolState,
) -> PoolState {
  let (
    datum_reserve_a,
    datum_reserve_b,
    value_reserve_a,
    value_reserve_b,
    total_liquidity,
  ) = pool_state
  let asset_out =
    if a_to_b_direction {
      asset_b
    } else {
      asset_a
    }
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let Asset { policy_id: lp_policy_id, asset_name: lp_asset_name } = lp_asset
  let withdrawal_lp_amount =
    value.quantity_of(
      self: order_in_value,
      policy_id: lp_policy_id,
      asset_name: lp_asset_name,
    )
  let has_enough_amount_in = withdrawal_lp_amount > 0

  let (earned_fee_a, earned_fee_b, amount_out) =
    math.calculate_zap_out(
      withdrawal_lp_amount: withdrawal_lp_amount,
      reserve_a: datum_reserve_a,
      reserve_b: datum_reserve_b,
      total_liquidity: total_liquidity,
      a_to_b_direction: a_to_b_direction,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
      profit_sharing_opt: profit_sharing_opt,
    )
  let not_over_slippage = amount_out >= minimum_receive
  let ada_amount =
    value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
  let actual_amount_out =
    value.quantity_of(
      order_out_value,
      asset_out_policy_id,
      asset_out_asset_name,
    )
  let is_valid_amount_out =
    if utils.is_ada_asset(asset_out_policy_id, asset_out_asset_name) {
      actual_amount_out == output_ada + amount_out
    } else {
      actual_amount_out == amount_out && output_ada == ada_amount
    }
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  if a_to_b_direction {
    (
      datum_reserve_a - earned_fee_a,
      datum_reserve_b - earned_fee_b - amount_out,
      value_reserve_a,
      value_reserve_b - amount_out,
      total_liquidity - withdrawal_lp_amount,
    )
  } else {
    (
      datum_reserve_a - amount_out - earned_fee_a,
      datum_reserve_b - earned_fee_b,
      value_reserve_a - amount_out,
      value_reserve_b,
      total_liquidity - withdrawal_lp_amount,
    )
  }
}

fn validate_partial_swap(
  order_in_value: Value,
  order_out_value: Value,
  a_to_b_direction: Bool,
  io_ratio_numerator: Int,
  io_ratio_denominator: Int,
  hops: Int,
  minimum_swap_amount_required: Int,
  asset_a: Asset,
  asset_b: Asset,
  batcher_fee: Int,
  output_ada: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  pool_state: PoolState,
) -> (Int, Int, Int, Int, Int, Bool) {
  let (
    datum_reserve_a,
    datum_reserve_b,
    value_reserve_a,
    value_reserve_b,
    total_liquidity,
  ) = pool_state
  let (asset_in, asset_out, reserve_in, reserve_out) =
    if a_to_b_direction {
      (asset_a, asset_b, datum_reserve_a, datum_reserve_b)
    } else {
      (asset_b, asset_a, datum_reserve_b, datum_reserve_a)
    }
  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let ada_in_require = batcher_fee * hops + output_ada
  let temp_amount_in =
    value.quantity_of(order_in_value, asset_in_policy_id, asset_in_asset_name)
  let amount_in =
    if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
      temp_amount_in - ada_in_require
    } else {
      temp_amount_in
    }
  let has_enough_amount_in = amount_in > 0
  let max_in_swap =
    math.calculate_max_in_swap(
      reserve_in: reserve_in,
      reserve_out: reserve_out,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
      io_ratio_numerator: io_ratio_numerator,
      io_ratio_denominator: io_ratio_denominator,
    )
  let (swap_amount_in, remaining_amount_in) =
    if amount_in <= max_in_swap {
      (amount_in, 0)
    } else {
      (max_in_swap, amount_in - max_in_swap)
    }
  expect swap_amount_in > 0 && swap_amount_in >= minimum_swap_amount_required
  let amount_out =
    math.calculate_amount_out(
      reserve_in: reserve_in,
      reserve_out: reserve_out,
      amount_in: swap_amount_in,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
    )
  let earned_fee_in =
    when profit_sharing_opt is {
      Some((fee_sharing_numerator, fee_sharing_denominator)) ->
        math.calculate_earned_fee_in(
          amount_in: swap_amount_in,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
          fee_sharing_numerator: fee_sharing_numerator,
          fee_sharing_denominator: fee_sharing_denominator,
        )
      None -> 0
    }
  let ada_out_require = batcher_fee * ( hops - 1 ) + output_ada
  let old_amount_out =
    value.quantity_of(order_in_value, asset_out_policy_id, asset_out_asset_name)
  let new_amount_out =
    value.quantity_of(
      order_out_value,
      asset_out_policy_id,
      asset_out_asset_name,
    )
  let new_amount_in =
    value.quantity_of(order_out_value, asset_in_policy_id, asset_in_asset_name)
  let is_valid_out_value =
    if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
      new_amount_in == remaining_amount_in + ada_out_require && new_amount_out == old_amount_out + amount_out
    } else if
    utils.is_ada_asset(asset_out_policy_id, asset_out_asset_name){
    
      new_amount_in == remaining_amount_in && new_amount_out == old_amount_out + amount_out * ada_out_require
    } else {
      let ada_amount =
        value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
      new_amount_in == remaining_amount_in && new_amount_out == old_amount_out + amount_out && ada_out_require == ada_amount
    }
  expect has_enough_amount_in && is_valid_out_value
  let has_next_swap =
    hops - 1 > 0 && remaining_amount_in >= minimum_swap_amount_required
  if a_to_b_direction {
    (
      datum_reserve_a + swap_amount_in - earned_fee_in,
      datum_reserve_b - amount_out,
      value_reserve_a + swap_amount_in,
      value_reserve_b - amount_out,
      total_liquidity,
      has_next_swap,
    )
  } else {
    (
      datum_reserve_a - amount_out,
      datum_reserve_b + swap_amount_in - earned_fee_in,
      value_reserve_a - amount_out,
      value_reserve_b + swap_amount_in,
      total_liquidity,
      has_next_swap,
    )
  }
}

fn get_multi_routing_swap_amount_out(
  amount_in: Int,
  pool: BatchingPool,
  routing: SwapRouting,
) -> Int {
  let BatchingPool {
    pool_state_in,
    pool_state_out,
    lp_asset: pool_lp_asset,
    trading_fee_numerator,
    trading_fee_denominator,
    profit_sharing,
    ..
  } = pool
  let (
    old_datum_reserve_a,
    old_datum_reserve_b,
    old_value_reserve_a,
    old_value_reserve_b,
    _,
  ) = pool_state_in
  let (
    new_datum_reserve_a,
    new_datum_reserve_b,
    new_value_reserve_a,
    new_value_reserve_b,
    _,
  ) = pool_state_out
  let SwapRouting { lp_asset: routing_lp_asset, direction } = routing
  expect pool_lp_asset == routing_lp_asset
  let (reserve_in, reserve_out) =
    when direction is {
      AToB -> (old_datum_reserve_a, old_datum_reserve_b)
      BToA -> (old_datum_reserve_b, old_datum_reserve_a)
    }

  expect amount_in > 0
  let amount_out =
    math.calculate_amount_out(
      reserve_in: reserve_in,
      reserve_out: reserve_out,
      amount_in: amount_in,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
    )
  let earned_fee_in =
    when profit_sharing is {
      Some((fee_sharing_numerator, fee_sharing_denominator)) ->
        math.calculate_earned_fee_in(
          amount_in: amount_in,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
          fee_sharing_numerator: fee_sharing_numerator,
          fee_sharing_denominator: fee_sharing_denominator,
        )
      None -> 0
    }
  expect amount_out > 0
  expect
    when direction is {
      AToB ->
        old_datum_reserve_a + amount_in - earned_fee_in == new_datum_reserve_a && // hihi
        old_datum_reserve_b - amount_out == new_datum_reserve_b && // hihi
        old_value_reserve_a + amount_in == new_value_reserve_a && // hihi
        old_value_reserve_b - amount_out == new_value_reserve_b
      // hihi
      BToA ->
        old_datum_reserve_a - amount_out == new_datum_reserve_a && // hihi
        old_datum_reserve_b + amount_in - earned_fee_in == new_datum_reserve_b && // hihi
        old_value_reserve_a - amount_out == new_value_reserve_a && // hihi
        old_value_reserve_b + amount_in == new_value_reserve_b
    }
  // hihi 
  amount_out
}

pub fn get_swap_multi_amount_out(
  amount_in: Int,
  current_amount_out: Int,
  all_pools: List<BatchingPool>,
  all_routings: List<SwapRouting>,
) -> Int {
  when all_pools is {
    [] -> current_amount_out
    [pool, ..pools] ->
      when all_routings is {
        [] -> current_amount_out
        [routing, ..routings] -> {
          let amount_out =
            get_multi_routing_swap_amount_out(amount_in, pool, routing)
          get_swap_multi_amount_out(
            amount_in: amount_out,
            current_amount_out: amount_out,
            all_pools: pools,
            all_routings: routings,
          )
        }
      }
  }
}

pub fn validate_swap_multi_routing_order(
  pools: List<BatchingPool>,
  routings: List<SwapRouting>,
  order_in_value: Value,
  order_out_value: Value,
  minimum_receive: Int,
  batcher_fee: Int,
  output_ada: Int,
) -> Bool {
  let first_routing = utils.list_at_index(routings, 0)
  let last_routing = utils.list_at_index(routings, list.length(routings) - 1)
  let first_pool = utils.list_at_index(pools, 0)
  let last_pool = utils.list_at_index(pools, list.length(pools) - 1)
  let SwapRouting { direction: first_routing_direction, .. } = first_routing
  let SwapRouting { direction: last_routing_direction, .. } = last_routing
  let BatchingPool {
    asset_a: first_pool_asset_a,
    asset_b: first_pool_asset_b,
    ..
  } = first_pool
  let BatchingPool {
    asset_a: last_pool_asset_a,
    asset_b: last_pool_asset_b,
    ..
  } = last_pool
  let asset_in =
    when first_routing_direction is {
      AToB -> first_pool_asset_a
      BToA -> first_pool_asset_b
    }
  let asset_out =
    when last_routing_direction is {
      AToB -> last_pool_asset_b
      BToA -> last_pool_asset_a
    }

  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let temp_amount_in =
    value.quantity_of(order_in_value, asset_in_policy_id, asset_in_asset_name)
  let amount_in =
    if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
      temp_amount_in - ( batcher_fee + output_ada )
    } else {
      temp_amount_in
    }
  let amount_out =
    get_swap_multi_amount_out(
      amount_in: amount_in,
      current_amount_out: 0,
      all_pools: pools,
      all_routings: routings,
    )
  expect amount_out >= minimum_receive
  let actual_amount_out =
    value.quantity_of(
      order_out_value,
      asset_out_policy_id,
      asset_out_asset_name,
    )
  let is_valid_amount_out =
    if utils.is_ada_asset(asset_out_policy_id, asset_out_asset_name) {
      amount_out + output_ada == actual_amount_out
    } else {
      let ada_amount =
        value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
      amount_out == actual_amount_out && ada_amount == output_ada
    }
  expect is_valid_amount_out
  True
}

pub fn validate_order_receiver(
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  output: Output,
) -> Bool {
  let Output { address: output_address, datum: raw_order_output_datum, .. } =
    output
  let is_valid_receiver_datum =
    when receiver_datum_hash_opt is {
      Some(receiver_datum_hash) ->
        when raw_order_output_datum is {
          NoDatum -> fail
          DatumHash(dh) -> dh == receiver_datum_hash
          InlineDatum(dat) ->
            hash.blake2b_256(builtin.serialise_data(dat)) == receiver_datum_hash
        }
      None -> raw_order_output_datum == NoDatum
    }
  expect receiver == output_address && is_valid_receiver_datum
  True
}

// TODO: validate order input value size
pub fn apply_orders(
  datum_map: DatumMap,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  order_hash: ByteArray,
  profit_sharing_opt: Option<(Int, Int)>,
  order_inputs: List<Input>,
  order_outputs: List<Output>,
  pool_state: PoolState,
) -> PoolState {
  when order_inputs is {
    [] -> pool_state
    [input, ..inputs] ->
      when order_outputs is {
        [] -> pool_state
        [output, ..outputs] -> {
          let Input {
            output: Output {
              value: order_in_value,
              datum: raw_order_in_datum,
              ..
            },
            ..
          } = input
          let Output { value: order_out_value, .. } = output
          let order_in_datum =
            utils.must_find_order_datum(datum_map, raw_order_in_datum)
          let OrderDatum {
            sender,
            receiver,
            receiver_datum_hash_opt,
            step: order_step,
            batcher_fee,
            output_ada,
            lp_asset: order_lp_asset,
          } = order_in_datum
          expect batcher_fee > 0 && output_ada > 0 && lp_asset == order_lp_asset
          let new_state =
            when order_step is {
              SwapExactIn(direction, minimum_receive) -> {
                expect minimum_receive > 0
                expect
                  validate_order_receiver(
                    receiver: receiver,
                    receiver_datum_hash_opt: receiver_datum_hash_opt,
                    output: output,
                  )
                let a_to_b_direction =
                  when direction is {
                    AToB -> True
                    BToA -> False
                  }
                validate_swap_exact_in(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  a_to_b_direction: a_to_b_direction,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  batcher_fee: batcher_fee,
                  output_ada: output_ada,
                  trading_fee_numerator: trading_fee_numerator,
                  trading_fee_denominator: trading_fee_denominator,
                  profit_sharing_opt: profit_sharing_opt,
                  pool_state: pool_state,
                  checking_slippage_fn: fn(amount_out) {
                    amount_out >= minimum_receive
                  },
                )
              }
              StopLoss(direction, stop_loss_receive) -> {
                expect stop_loss_receive > 0
                expect
                  validate_order_receiver(
                    receiver: receiver,
                    receiver_datum_hash_opt: receiver_datum_hash_opt,
                    output: output,
                  )
                let a_to_b_direction =
                  when direction is {
                    AToB -> True
                    BToA -> False
                  }
                validate_swap_exact_in(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  a_to_b_direction: a_to_b_direction,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  batcher_fee: batcher_fee,
                  output_ada: output_ada,
                  trading_fee_numerator: trading_fee_numerator,
                  trading_fee_denominator: trading_fee_denominator,
                  profit_sharing_opt: profit_sharing_opt,
                  pool_state: pool_state,
                  checking_slippage_fn: fn(amount_out) {
                    amount_out <= stop_loss_receive
                  },
                )
              }
              OCO(direction, minimum_receive, stop_loss_receive) -> {
                expect minimum_receive > 0 && stop_loss_receive > 0
                expect
                  validate_order_receiver(
                    receiver: receiver,
                    receiver_datum_hash_opt: receiver_datum_hash_opt,
                    output: output,
                  )
                let a_to_b_direction =
                  when direction is {
                    AToB -> True
                    BToA -> False
                  }
                validate_swap_exact_in(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  a_to_b_direction: a_to_b_direction,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  batcher_fee: batcher_fee,
                  output_ada: output_ada,
                  trading_fee_numerator: trading_fee_numerator,
                  trading_fee_denominator: trading_fee_denominator,
                  profit_sharing_opt: profit_sharing_opt,
                  pool_state: pool_state,
                  checking_slippage_fn: fn(amount_out) {
                    amount_out >= minimum_receive || amount_out <= stop_loss_receive
                  },
                )
              }
              SwapExactOut(direction, expected_receive) -> {
                expect expected_receive > 0
                expect
                  validate_order_receiver(
                    receiver: receiver,
                    receiver_datum_hash_opt: receiver_datum_hash_opt,
                    output: output,
                  )
                let a_to_b_direction =
                  when direction is {
                    AToB -> True
                    BToA -> False
                  }
                validate_swap_exact_out(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  a_to_b_direction: a_to_b_direction,
                  expected_receive: expected_receive,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  batcher_fee: batcher_fee,
                  output_ada: output_ada,
                  trading_fee_numerator: trading_fee_numerator,
                  trading_fee_denominator: trading_fee_denominator,
                  profit_sharing_opt: profit_sharing_opt,
                  pool_state: pool_state,
                )
              }
              Deposit(minimum_lp) -> {
                expect minimum_lp > 0
                expect
                  validate_order_receiver(
                    receiver: receiver,
                    receiver_datum_hash_opt: receiver_datum_hash_opt,
                    output: output,
                  )
                validate_deposit(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  minimum_lp: minimum_lp,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  lp_asset: lp_asset,
                  batcher_fee: batcher_fee,
                  output_ada: output_ada,
                  profit_sharing_opt: profit_sharing_opt,
                  trading_fee_numerator: trading_fee_numerator,
                  trading_fee_denominator: trading_fee_denominator,
                  pool_state: pool_state,
                )
              }
              Withdraw(minimum_asset_a, minimum_asset_b) -> {
                expect minimum_asset_a > 0 && minimum_asset_b > 0
                expect
                  validate_order_receiver(
                    receiver: receiver,
                    receiver_datum_hash_opt: receiver_datum_hash_opt,
                    output: output,
                  )
                validate_withdraw(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  minimum_amount_a: minimum_asset_a,
                  minimum_amount_b: minimum_asset_b,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  lp_asset: lp_asset,
                  output_ada: output_ada,
                  pool_state: pool_state,
                )
              }
              ZapOut(direction, minimum_receive) -> {
                expect minimum_receive > 0
                expect
                  validate_order_receiver(
                    receiver: receiver,
                    receiver_datum_hash_opt: receiver_datum_hash_opt,
                    output: output,
                  )
                let a_to_b_direction =
                  when direction is {
                    AToB -> True
                    BToA -> False
                  }
                validate_zap_out(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  minimum_receive: minimum_receive,
                  a_to_b_direction: a_to_b_direction,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  lp_asset: lp_asset,
                  output_ada: output_ada,
                  profit_sharing_opt: profit_sharing_opt,
                  trading_fee_numerator: trading_fee_numerator,
                  trading_fee_denominator: trading_fee_denominator,
                  pool_state: pool_state,
                )
              }
              PartialSwap(
                direction,
                io_ratio_numerator,
                io_ratio_denominator,
                hops,
                minimum_swap_amount_required,
              ) -> {
                expect
                  io_ratio_numerator > 0 && io_ratio_numerator > 0 && hops > 0
                let a_to_b_direction =
                  when direction is {
                    AToB -> True
                    BToA -> False
                  }
                let (
                  new_reserve_a,
                  new_reserve_b,
                  new_total_liquidity,
                  new_liquidity_share,
                  new_root_k_last,
                  has_next_swap,
                ) =
                  validate_partial_swap(
                    order_in_value: order_in_value,
                    order_out_value: order_out_value,
                    a_to_b_direction: a_to_b_direction,
                    io_ratio_numerator: io_ratio_numerator,
                    io_ratio_denominator: io_ratio_denominator,
                    hops: hops,
                    minimum_swap_amount_required: minimum_swap_amount_required,
                    asset_a: asset_a,
                    asset_b: asset_b,
                    batcher_fee: batcher_fee,
                    output_ada: output_ada,
                    trading_fee_numerator: trading_fee_numerator,
                    trading_fee_denominator: trading_fee_denominator,
                    profit_sharing_opt: profit_sharing_opt,
                    pool_state: pool_state,
                  )
                expect
                  if has_next_swap {
                    let Output {
                      address: Address {
                        payment_credential: order_out_payment_cred,
                        ..
                      },
                      datum: raw_order_out_datum,
                      ..
                    } = output
                    expect ScriptCredential(order_out_script_hash) =
                      order_out_payment_cred
                    let OrderDatum {
                      sender: order_out_sender,
                      receiver: order_out_receiver,
                      receiver_datum_hash_opt: order_out_receiver_datum_hash_opt,
                      step: order_out_step,
                      batcher_fee: order_out_batcher_fee,
                      output_ada: order_out_output_ada,
                      lp_asset: order_out_lp_asset,
                    } =
                      utils.must_find_order_datum(
                        datum_map,
                        raw_order_out_datum,
                      )
                    expect PartialSwap(
                      order_out_step_direction,
                      order_out_io_ratio_numerator,
                      order_out_io_ratio_denominator,
                      order_out_hops,
                      order_out_minimum_swap_amount_required,
                    ) = order_out_step
                    order_out_script_hash == order_hash && // hihi
                    sender == order_out_sender && // hihi
                    receiver == order_out_receiver && // hihi
                    receiver_datum_hash_opt == order_out_receiver_datum_hash_opt && // hihi
                    batcher_fee == order_out_batcher_fee && // hihi
                    output_ada == order_out_output_ada && // hihi
                    order_lp_asset == order_out_lp_asset && // hihi
                    direction == order_out_step_direction && // hihi
                    io_ratio_numerator == order_out_io_ratio_numerator && // hihi
                    io_ratio_denominator == order_out_io_ratio_denominator && // hihi
                    hops - 1 == order_out_hops && // hihi
                    minimum_swap_amount_required == order_out_minimum_swap_amount_required
                  } else {
                    validate_order_receiver(
                      receiver: receiver,
                      receiver_datum_hash_opt: receiver_datum_hash_opt,
                      output: output,
                    )
                  }
                (
                  new_reserve_a,
                  new_reserve_b,
                  new_total_liquidity,
                  new_liquidity_share,
                  new_root_k_last,
                )
              }
              SwapMultiRouting(_, _) -> fail
            }
          apply_orders(
            datum_map: datum_map,
            asset_a: asset_a,
            asset_b: asset_b,
            lp_asset: lp_asset,
            trading_fee_numerator: trading_fee_numerator,
            trading_fee_denominator: trading_fee_denominator,
            order_hash: order_hash,
            profit_sharing_opt: profit_sharing_opt,
            order_inputs: inputs,
            order_outputs: outputs,
            pool_state: new_state,
          )
        }
      }
  }
}

test test_validate_swap_exact_in_with_no_fee_sharing() {
  let asset_a = Asset { policy_id: ada_policy_id, asset_name: ada_asset_name }
  let asset_b =
    Asset {
      policy_id: #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
      asset_name: #"4d494e",
    }
  let batcher_fee = 2000000
  let output_ada = 2000000
  let amount_in = 1000000000
  let amount_out = 14834146387
  let order_in_value =
    value.zero()
      |> value.add(
           ada_policy_id,
           ada_asset_name,
           batcher_fee + output_ada + amount_in,
         )
  let order_out_value =
    value.zero()
      |> value.add(ada_policy_id, ada_asset_name, output_ada)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           amount_out,
         )
  let new_pool_state =
    validate_swap_exact_in(
      order_in_value: order_in_value,
      order_out_value: order_out_value,
      a_to_b_direction: True,
      asset_a: asset_a,
      asset_b: asset_b,
      batcher_fee: batcher_fee,
      output_ada: output_ada,
      trading_fee_numerator: 3,
      trading_fee_denominator: 1000,
      profit_sharing_opt: None,
      pool_state: (
        27877961987941,
        414804973691450,
        27877961987941,
        414804973691450,
        106241703280080,
      ),
      checking_slippage_fn: fn(o) { o > 1 },
    )
  // let fee_share = amount_in * 3 / ( 1000 * 6 )
  new_pool_state == (
    27878961987941,
    414790139545063,
    27878961987941,
    414790139545063,
    106241703280080,
  )
}

test test_validate_swap_exact_in_with_fee_sharing() {
  let asset_a = Asset { policy_id: ada_policy_id, asset_name: ada_asset_name }
  let asset_b =
    Asset {
      policy_id: #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
      asset_name: #"4d494e",
    }
  let batcher_fee = 2000000
  let output_ada = 2000000
  let amount_in = 1000000000
  let amount_out = 16200168971
  let order_in_value =
    value.zero()
      |> value.add(
           ada_policy_id,
           ada_asset_name,
           batcher_fee + output_ada + amount_in,
         )
  let order_out_value =
    value.zero()
      |> value.add(ada_policy_id, ada_asset_name, output_ada)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           amount_out,
         )
  let new_pool_state =
    validate_swap_exact_in(
      order_in_value: order_in_value,
      order_out_value: order_out_value,
      a_to_b_direction: True,
      asset_a: asset_a,
      asset_b: asset_b,
      batcher_fee: batcher_fee,
      output_ada: output_ada,
      trading_fee_numerator: 3,
      trading_fee_denominator: 1000,
      profit_sharing_opt: Some((1, 6)),
      pool_state: (
        25434557769208,
        413300185707175,
        25434557769208,
        413300185707175,
        101211362398220,
      ),
      checking_slippage_fn: fn(o) { o > 1 },
    )
  let fee_share = amount_in * 3 / ( 1000 * 6 )
  new_pool_state == (
    25434557769208 + amount_in - fee_share,
    413300185707175 - amount_out,
    25434557769208 + amount_in,
    413300185707175 - amount_out,
    101211362398220,
  )
}

test test_validate_swap_multi_routing_order() {
  let pool_1_asset_a =
    Asset { policy_id: ada_policy_id, asset_name: ada_asset_name }
  let pool_1_asset_b =
    Asset {
      policy_id: #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
      asset_name: #"4d494e",
    }
  let pool_1_lp_asset =
    Asset {
      policy_id: #"1a919d30617fcbc8a92c337c59c3aecb6c4ded8f154e4c24528ccea2",
      asset_name: #"6c3ea488e6ff940bb6fb1b18fd605b5931d9fefde6440117015ba484cf321200",
    }
  let pool_1_pool_state_in =
    (
      27877961987941,
      414804973691450,
      27877961987941,
      414804973691450,
      106241703280080,
    )

  let pool_1_pool_state_out =
    (
      27871263020717,
      414904973691450,
      27871263020717,
      414904973691450,
      106241703280080,
    )

  let pool1 =
    BatchingPool {
      asset_a: pool_1_asset_a,
      asset_b: pool_1_asset_b,
      lp_asset: pool_1_lp_asset,
      trading_fee_numerator: 3,
      trading_fee_denominator: 1000,
      profit_sharing: None,
      order_hash: #"6dc232f0f5832da2070a232ad2f58433883b9a277577048b40d17673",
      address: credential.from_script(
        #"11f3fb05033cb08e95f5c6d4b11891003dc762a46828a4b6f164efe2",
      ),
      pool_state_in: pool_1_pool_state_in,
      pool_state_out: pool_1_pool_state_out,
    }
  let pool_2_asset_a =
    Asset { policy_id: ada_policy_id, asset_name: ada_asset_name }
  let pool_2_asset_b =
    Asset {
      policy_id: #"f66d78b4a3cb3d37afa0ec36461e51ecbde00f26c8f0a68f94b69880",
      asset_name: #"69555344",
    }
  let pool_2_lp_asset =
    Asset {
      policy_id: #"1a919d30617fcbc8a92c337c59c3aecb6c4ded8f154e4c24528ccea2",
      asset_name: #"452089abb5bf8cc59b678a2cd7b9ee952346c6c0aa1cf27df324310a70d02fc3",
    }
  let pool_2_pool_state_in =
    (5281584632864, 1432277778019, 5281584632864, 1432277778019, 2450077671602)
  let pool_2_pool_state_out =
    (5288283600088, 1430468867110, 5288283600088, 1430468867110, 2450077671602)
  let pool2 =
    BatchingPool {
      asset_a: pool_2_asset_a,
      asset_b: pool_2_asset_b,
      lp_asset: pool_2_lp_asset,
      trading_fee_numerator: 3,
      trading_fee_denominator: 1000,
      profit_sharing: None,
      order_hash: #"6dc232f0f5832da2070a232ad2f58433883b9a277577048b40d17673",
      address: credential.from_script(
        #"11f3fb05033cb08e95f5c6d4b11891003dc762a46828a4b6f164efe2",
      ),
      pool_state_in: pool_2_pool_state_in,
      pool_state_out: pool_2_pool_state_out,
    }
  let pools =
    [pool1, pool2]
  let routing1 = SwapRouting { lp_asset: pool_1_lp_asset, direction: BToA }
  let routing2 = SwapRouting { lp_asset: pool_2_lp_asset, direction: AToB }
  let routings =
    [routing1, routing2]
  let amount_out =
    get_swap_multi_amount_out(
      amount_in: 100000000000,
      current_amount_out: 0,
      all_pools: pools,
      all_routings: routings,
    )
  amount_out == 1808910909
}

test test_validate_deposit() {
  let asset_a = Asset { policy_id: ada_policy_id, asset_name: ada_asset_name }
  let asset_b =
    Asset {
      policy_id: #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
      asset_name: #"4d494e",
    }
  let lp_asset =
    Asset {
      policy_id: #"51eee5fe126a1337497dd4d0a43efb31c9f791436b74472a4fc4536a",
      asset_name: #"6c3ea488e6ff940bb6fb1b18fd605b5931d9fefde6440117015ba484cf321200",
    }
  let batcher_fee = 2000000
  let output_ada = 2000000
  let amount_a = 1000000
  let amount_b = 123112
  let amount_out = 867556
  let order_in_value =
    value.zero()
      |> value.add(
           ada_policy_id,
           ada_asset_name,
           batcher_fee + output_ada + amount_a,
         )
      |> value.add(asset_b.policy_id, asset_b.asset_name, amount_b)
  let order_out_value =
    value.zero()
      |> value.add(ada_policy_id, ada_asset_name, output_ada)
      |> value.add(lp_asset.policy_id, lp_asset.asset_name, amount_out)
  let new_pool_state =
    validate_deposit(
      order_in_value: order_in_value,
      order_out_value: order_out_value,
      minimum_lp: amount_out,
      asset_a: asset_a,
      asset_b: asset_b,
      lp_asset: lp_asset,
      batcher_fee: batcher_fee,
      output_ada: output_ada,
      trading_fee_numerator: 1,
      trading_fee_denominator: 100,
      profit_sharing_opt: None,
      pool_state: (1000000, 4000000, 1000000, 4000000, 2000000),
    )
  new_pool_state == (2000000, 4123112, 2000000, 4123112, 2867556)
}
