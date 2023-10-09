use aiken/dict.{Dict}
use aiken/hash.{Blake2b_256, Hash}
use aiken/list
use aiken/transaction.{DatumHash, Input, NoDatum, Output}
use aiken/transaction/credential
use aiken/transaction/value.{Value, ada_asset_name, ada_policy_id}
use amm_dex_v2/math
use amm_dex_v2/types.{
  AToB, Asset, BToA, BatchingPool, Deposit, OrderDatum, PoolState, ProfitSharing,
  SwapExactIn, SwapExactOut, SwapMultiRouting, SwapRouting, Withdraw, ZapOut,
}
use amm_dex_v2/utils

fn validate_swap_exact_in(
  order_in_value: Value,
  order_out_value: Value,
  a_to_b_direction: Bool,
  minimum_receive: Int,
  asset_a: Asset,
  asset_b: Asset,
  batcher_fee: Int,
  output_ada: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  let (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) =
    pool_state
  let (asset_in, asset_out, reserve_in, reserve_out) =
    if a_to_b_direction {
      (asset_a, asset_b, reserve_a, reserve_b)
    } else {
      (asset_b, asset_a, reserve_b, reserve_a)
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
  let not_over_slippage = amount_out >= minimum_receive
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
      reserve_a + amount_in,
      reserve_b - amount_out,
      total_liquidity,
      liquidity_share,
      root_k_last,
    )
  } else {
    (
      reserve_a - amount_out,
      reserve_b + amount_in,
      total_liquidity,
      liquidity_share,
      root_k_last,
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
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  let (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) =
    pool_state
  let (asset_in, asset_out, reserve_in, reserve_out) =
    if a_to_b_direction {
      (asset_a, asset_b, reserve_a, reserve_b)
    } else {
      (asset_b, asset_a, reserve_b, reserve_a)
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
  let necessary_amount_in_opt =
    math.calculate_amount_in(
      reserve_in,
      reserve_out,
      expected_receive,
      trading_fee_numerator,
      trading_fee_denominator,
    )
  let necessary_amount_in = utils.must_parse_option(necessary_amount_in_opt)
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
      reserve_a + necessary_amount_in,
      reserve_b - expected_receive,
      total_liquidity,
      liquidity_share,
      root_k_last,
    )
  } else {
    (
      reserve_a - expected_receive,
      reserve_b + necessary_amount_in,
      total_liquidity,
      liquidity_share,
      root_k_last,
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
  profit_sharing_opt: Option<ProfitSharing>,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  let (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) =
    pool_state
  let Asset { policy_id: asset_a_policy_id, asset_name: asset_a_asset_name } =
    asset_a
  let Asset { policy_id: asset_b_policy_id, asset_name: asset_b_asset_name } =
    asset_b
  let Asset { policy_id: lp_asset_policy_id, asset_name: lp_asset_asset_name } =
    lp_asset
  let temp_amount_a =
    value.quantity_of(order_in_value, asset_a_policy_id, asset_a_asset_name)
  let temp_amount_b =
    value.quantity_of(order_in_value, asset_b_policy_id, asset_b_asset_name)
  let amount_a =
    if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
      temp_amount_a - ( batcher_fee + output_ada )
    } else {
      temp_amount_a
    }
  let amount_b =
    if utils.is_ada_asset(asset_b_policy_id, asset_b_asset_name) {
      temp_amount_b - ( batcher_fee + output_ada )
    } else {
      temp_amount_b
    }
  let has_enough_amount_in = amount_a > 0 && amount_b > 0
  let (reserve_product_after_swap, lp_amount) =
    math.calculate_deposit_amount(
      amount_a: amount_a,
      amount_b: amount_b,
      reserve_a: reserve_a,
      reserve_b: reserve_b,
      total_liquidity: total_liquidity,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
    )
  let not_over_slippage = lp_amount >= minimum_lp
  let lp_amount_out =
    value.quantity_of(order_out_value, lp_asset_policy_id, lp_asset_asset_name)
  let ada_amount_out =
    value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)

  let is_valid_amount_out =
    ada_amount_out == output_ada && lp_amount_out == lp_amount
  let new_reserve_a = reserve_a + amount_a
  let new_reserve_b = reserve_b + amount_b

  let (delta_liquidity_share, new_root_k_last) =
    when profit_sharing_opt is {
      Some(profit_sharing) -> {
        let ProfitSharing { fee_sharing_numerator, fee_sharing_denominator, .. } =
          profit_sharing
        let delta_liquidity_share =
          math.calculate_profit_sharing(
            root_k_last,
            reserve_product_after_swap,
            total_liquidity,
            fee_sharing_numerator,
            fee_sharing_denominator,
          )
        let new_root_k_last = math.calculate_sqrt(new_reserve_a * new_reserve_b)
        (delta_liquidity_share, new_root_k_last)
      }
      None -> (0, root_k_last)
    }
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  (
    new_reserve_a,
    new_reserve_b,
    total_liquidity + lp_amount + delta_liquidity_share,
    liquidity_share + delta_liquidity_share,
    new_root_k_last,
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
  profit_sharing_opt: Option<ProfitSharing>,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  let (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) =
    pool_state
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
      reserve_a,
      reserve_b,
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
    } else if
    utils.is_ada_asset(asset_b_policy_id, asset_b_asset_name){
    
      actual_amount_b_out == amount_b_out + output_ada && actual_amount_a_out == amount_a_out
    } else {
      ada_amount_out == output_ada && actual_amount_a_out == amount_a_out && actual_amount_b_out == amount_b_out
    }
  let new_reserve_a = reserve_a - amount_a_out
  let new_reserve_b = reserve_b - amount_b_out
  let (delta_liquidity_share, new_root_k_last) =
    when profit_sharing_opt is {
      Some(profit_sharing) -> {
        let ProfitSharing { fee_sharing_numerator, fee_sharing_denominator, .. } =
          profit_sharing
        let delta_liquidity_share =
          math.calculate_profit_sharing(
            root_k_last,
            reserve_a * reserve_b,
            total_liquidity,
            fee_sharing_numerator,
            fee_sharing_denominator,
          )
        let new_root_k_last = math.calculate_sqrt(new_reserve_a * new_reserve_b)
        (delta_liquidity_share, new_root_k_last)
      }
      None -> (0, root_k_last)
    }
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  (
    new_reserve_a,
    new_reserve_b,
    total_liquidity - withdrawal_lp_amount + delta_liquidity_share,
    liquidity_share + delta_liquidity_share,
    new_root_k_last,
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
  profit_sharing_opt: Option<ProfitSharing>,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  let (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) =
    pool_state
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

  let (reserve_product_after_withdraw, amount_out) =
    math.calculate_zap_out(
      withdrawal_lp_amount: withdrawal_lp_amount,
      reserve_a: reserve_a,
      reserve_b: reserve_b,
      total_liquidity: total_liquidity,
      a_to_b_direction: a_to_b_direction,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
    )
  let (delta_liquidity_share, new_root_k_last) =
    when profit_sharing_opt is {
      Some(profit_sharing) -> {
        let ProfitSharing { fee_sharing_numerator, fee_sharing_denominator, .. } =
          profit_sharing
        let delta_liquidity_share =
          math.calculate_profit_sharing(
            root_k_last,
            reserve_a * reserve_b,
            total_liquidity,
            fee_sharing_numerator,
            fee_sharing_denominator,
          )
        let new_root_k_last =
          math.calculate_sqrt(reserve_product_after_withdraw)
        (delta_liquidity_share, new_root_k_last)
      }
      None -> (0, root_k_last)
    }
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
      reserve_a,
      reserve_b - amount_out,
      total_liquidity - withdrawal_lp_amount + delta_liquidity_share,
      liquidity_share + delta_liquidity_share,
      new_root_k_last,
    )
  } else {
    (
      reserve_a - amount_out,
      reserve_b,
      total_liquidity - withdrawal_lp_amount + delta_liquidity_share,
      liquidity_share + delta_liquidity_share,
      new_root_k_last,
    )
  }
}

fn validate_multi_routing_swap(
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
    ..
  } = pool
  let PoolState { reserve_a: old_reserve_a, reserve_b: old_reserve_b, .. } =
    pool_state_in
  let PoolState { reserve_a: new_reserve_a, reserve_b: new_reserve_b, .. } =
    pool_state_out
  let SwapRouting { lp_asset: rounting_lp_asset, direction } = routing
  expect pool_lp_asset == rounting_lp_asset
  let (reserve_in, reserve_out) =
    when direction is {
      AToB -> (old_reserve_a, old_reserve_b)
      BToA -> (old_reserve_b, old_reserve_a)
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
  expect amount_out > 0
  expect
    when direction is {
      AToB ->
        old_reserve_a + amount_in == new_reserve_a && old_reserve_b - amount_out == new_reserve_b
      BToA ->
        old_reserve_a - amount_out == new_reserve_a && old_reserve_b + amount_in == new_reserve_b
    }
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
          let amount_out = validate_multi_routing_swap(amount_in, pool, routing)
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
    PoolState {
      reserve_a: 27877961987941,
      reserve_b: 414804973691450,
      root_k_last: 0,
      total_liquidity: 106241703280080,
      liquidity_share: 0,
      remaining_liquidity_supply: 9223372036854775807 - 106241703280080,
    }
  let pool_1_pool_state_out =
    PoolState {
      reserve_a: 27871263020717,
      reserve_b: 414904973691450,
      root_k_last: 0,
      total_liquidity: 106241703280080,
      liquidity_share: 0,
      remaining_liquidity_supply: 9223372036854775807 - 106241703280080,
    }
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
    PoolState {
      reserve_a: 5281584632864,
      reserve_b: 1432277778019,
      root_k_last: 0,
      total_liquidity: 2450077671602,
      liquidity_share: 0,
      remaining_liquidity_supply: 9223372036854775807 - 2450077671602,
    }
  let pool_2_pool_state_out =
    PoolState {
      reserve_a: 5288283600088,
      reserve_b: 1430468867110,
      root_k_last: 0,
      total_liquidity: 2450077671602,
      liquidity_share: 0,
      remaining_liquidity_supply: 9223372036854775807 - 2450077671602,
    }
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

pub fn apply_orders(
  all_outputs: List<Output>,
  datum_dict: Dict<Hash<Blake2b_256, Data>, Data>,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  profit_sharing_opt: Option<ProfitSharing>,
  order_inputs: List<Input>,
  order_outputs: List<Output>,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  when order_inputs is {
    [] -> pool_state
    [input, ..inputs] ->
      when order_outputs is {
        [] -> pool_state
        [output, ..outputs] -> {
          let Input { output: order_in_output, .. } = input
          let Output { value: order_in_value, .. } = order_in_output
          let Output {
            value: order_out_value,
            address: output_address,
            datum: order_output_datum,
            ..
          } = output
          let OrderDatum {
            receiver,
            receiver_datum_hash_opt,
            step: order_step,
            batcher_fee,
            output_ada,
            lp_asset: order_lp_asset,
            ..
          } =
            utils.must_find_order_datum(
              all_outputs,
              datum_dict,
              order_in_output,
            )
          let is_valid_receiver_datum_hash =
            when receiver_datum_hash_opt is {
              Some(datum_hash) -> {
                expect DatumHash(output_datum_hash) = order_output_datum
                output_datum_hash == datum_hash
              }
              None -> order_output_datum == NoDatum
            }
          expect
            receiver == output_address && batcher_fee > 0 && output_ada > 0 && is_valid_receiver_datum_hash && lp_asset == order_lp_asset
          let new_state =
            when order_step is {
              SwapExactIn(direction, minimum_receive) -> {
                expect minimum_receive > 0
                let a_to_b_direction =
                  when direction is {
                    AToB -> True
                    BToA -> False
                  }
                validate_swap_exact_in(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  a_to_b_direction: a_to_b_direction,
                  minimum_receive: minimum_receive,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  batcher_fee: batcher_fee,
                  output_ada: output_ada,
                  trading_fee_numerator: trading_fee_numerator,
                  trading_fee_denominator: trading_fee_denominator,
                  pool_state: pool_state,
                )
              }
              SwapExactOut(direction, expected_receive) -> {
                expect expected_receive > 0
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
                  pool_state: pool_state,
                )
              }
              Deposit(minimum_lp) -> {
                expect minimum_lp > 0
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
                validate_withdraw(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  minimum_amount_a: minimum_asset_a,
                  minimum_amount_b: minimum_asset_b,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  lp_asset: lp_asset,
                  output_ada: output_ada,
                  profit_sharing_opt: profit_sharing_opt,
                  pool_state: pool_state,
                )
              }
              ZapOut(direction, minimum_receive) -> {
                expect minimum_receive > 0
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
              SwapMultiRouting(_, _) -> fail
            }
          apply_orders(
            all_outputs: all_outputs,
            datum_dict: datum_dict,
            asset_a: asset_a,
            asset_b: asset_b,
            lp_asset: lp_asset,
            trading_fee_numerator: trading_fee_numerator,
            trading_fee_denominator: trading_fee_denominator,
            profit_sharing_opt: profit_sharing_opt,
            order_inputs: inputs,
            order_outputs: outputs,
            pool_state: new_state,
          )
        }
      }
  }
}
