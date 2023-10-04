use aiken/dict.{Dict}
use aiken/hash.{Blake2b_256, Hash}
use aiken/transaction.{DatumHash, Input, NoDatum, Output}
use aiken/transaction/value.{Value, ada_asset_name, ada_policy_id}
use amm_dex_v2/math
use amm_dex_v2/types.{
  AToB, Asset, BToA, Deposit, OrderDatum, OrderDirection, ProfitSharing,
  SwapExactIn, SwapExactOut, SwapMultiRouting, Withdraw, ZapOut,
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
  a_to_b_direction: Bool,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  pool_state: (Int, Int),
) -> (Int, Int, Int) {
  let (reserve_a, reserve_b) = pool_state
  let (reserve_in, reserve_out) =
    if a_to_b_direction {
      (reserve_a, reserve_b)
    } else {
      (reserve_b, reserve_a)
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
  if a_to_b_direction {
    (reserve_a + amount_in, reserve_b - amount_out, amount_out)
  } else {
    (reserve_a - amount_out, reserve_b + amount_in, amount_out)
  }
}

pub fn validate_swap_multi_routing_order(
  pool_one_in_state: (Int, Int),
  pool_one_out_state: (Int, Int),
  pool_two_in_state: (Int, Int),
  pool_two_out_state: (Int, Int),
  pool_one_trading_fee_numerator: Int,
  pool_one_trading_fee_denominator: Int,
  pool_two_trading_fee_numerator: Int,
  pool_two_trading_fee_denominator: Int,
  pool_one_asset_a: Asset,
  pool_one_asset_b: Asset,
  pool_two_asset_a: Asset,
  pool_two_asset_b: Asset,
  route_one_direction: OrderDirection,
  order_in_value: Value,
  order_out_value: Value,
  minimum_receive: Int,
  batcher_fee: Int,
  output_ada: Int,
) -> Bool {
  let (route_two_direction, asset_in, asset_out) =
    when route_one_direction is {
      AToB ->
        if pool_one_asset_b == pool_two_asset_a {
          (AToB, pool_one_asset_a, pool_two_asset_b)
        } else {
          (BToA, pool_one_asset_a, pool_two_asset_a)
        }
      BToA ->
        if pool_one_asset_a == pool_two_asset_a {
          (AToB, pool_one_asset_b, pool_two_asset_b)
        } else {
          (BToA, pool_one_asset_b, pool_two_asset_a)
        }
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
  let (pool_one_in_reserve_a, pool_one_in_reserve_b) = pool_one_in_state
  let (pool_one_out_reserve_a, pool_one_out_reserve_b) = pool_one_out_state
  let (pool_two_in_reserve_a, pool_two_in_reserve_b) = pool_two_in_state
  let (pool_two_out_reserve_a, pool_two_out_reserve_b) = pool_two_out_state
  let round_one_a_to_b_direction =
    when route_one_direction is {
      AToB -> True
      BToA -> False
    }
  let round_two_a_to_b_direction =
    when route_two_direction is {
      AToB -> True
      BToA -> False
    }
  let (new_pool_one_reserve_a, new_pool_one_reserve_b, round_one_amount_out) =
    validate_multi_routing_swap(
      amount_in: amount_in,
      a_to_b_direction: round_one_a_to_b_direction,
      trading_fee_numerator: pool_one_trading_fee_numerator,
      trading_fee_denominator: pool_one_trading_fee_denominator,
      pool_state: (pool_one_in_reserve_a, pool_one_in_reserve_b),
    )
  let (new_pool_two_reserve_a, new_pool_two_reserve_b, round_two_amount_out) =
    validate_multi_routing_swap(
      amount_in: round_one_amount_out,
      a_to_b_direction: round_two_a_to_b_direction,
      trading_fee_numerator: pool_two_trading_fee_numerator,
      trading_fee_denominator: pool_two_trading_fee_denominator,
      pool_state: (pool_two_in_reserve_a, pool_two_in_reserve_b),
    )
  expect round_two_amount_out >= minimum_receive
  let is_valid_pool_one =
    pool_one_out_reserve_a == new_pool_one_reserve_a && pool_one_out_reserve_b == new_pool_one_reserve_b
  let is_valid_pool_two =
    pool_two_out_reserve_a == new_pool_two_reserve_a && pool_two_out_reserve_b == new_pool_two_reserve_b
  let actual_amount_out =
    value.quantity_of(
      order_out_value,
      asset_out_policy_id,
      asset_out_asset_name,
    )
  let is_valid_amount_out =
    if utils.is_ada_asset(asset_out_policy_id, asset_out_asset_name) {
      round_two_amount_out + output_ada == actual_amount_out
    } else {
      let ada_amount =
        value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
      round_two_amount_out == actual_amount_out && ada_amount == output_ada
    }
  expect is_valid_pool_one && is_valid_pool_two && is_valid_amount_out
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
              SwapMultiRouting(_, _, _) -> fail
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
