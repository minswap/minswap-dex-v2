use aiken/builtin
use aiken/hash
use aiken/list
use aiken/transaction.{Datum, DatumHash, InlineDatum, Input, NoDatum, Output}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{Value, ada_asset_name, ada_policy_id}
use amm_dex_v2/math
use amm_dex_v2/types.{
  Asset, BatchingPool, CustomDatumHash, DatumMap, Deposit, OCO, OrderDatum,
  PartialSwap, PoolState, StopLoss, SwapExactIn, SwapExactOut, SwapMultiRouting,
  SwapRouting, Withdraw, WithdrawImbalance, ZapOut,
}
use amm_dex_v2/utils

fn get_returnable_value(order_in_value: Value, used_batcher_fee: Int) -> Value {
  value.add(
    order_in_value,
    ada_policy_id,
    ada_asset_name,
    used_batcher_fee * -1,
  )
}

fn validate_swap_exact_in(
  order_in_value: Value,
  order_output: Output,
  sender: Address,
  sender_datum_hash_opt: Option<CustomDatumHash>,
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  a_to_b_direction: Bool,
  swap_amount: Int,
  asset_a: Asset,
  asset_b: Asset,
  used_batcher_fee: Int,
  trading_fee_a_numerator: Int,
  trading_fee_a_denominator: Int,
  trading_fee_b_numerator: Int,
  trading_fee_b_denominator: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  pool_state: PoolState,
  kill_on_failed: Bool,
  is_slippage_satisfied: fn(Int) -> Bool,
) -> PoolState {
  let (
    datum_reserve_a,
    datum_reserve_b,
    value_reserve_a,
    value_reserve_b,
    total_liquidity,
  ) = pool_state
  let (
    asset_in,
    asset_out,
    reserve_in,
    reserve_out,
    trading_fee_numerator,
    trading_fee_denominator,
  ) =
    if a_to_b_direction {
      (
        asset_a,
        asset_b,
        datum_reserve_a,
        datum_reserve_b,
        trading_fee_a_numerator,
        trading_fee_a_denominator,
      )
    } else {
      (
        asset_b,
        asset_a,
        datum_reserve_b,
        datum_reserve_a,
        trading_fee_b_numerator,
        trading_fee_b_denominator,
      )
    }
  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out

  let amount_out =
    math.calculate_amount_out(
      reserve_in: reserve_in,
      reserve_out: reserve_out,
      amount_in: swap_amount,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
    )
  let earned_fee_in =
    math.calculate_earned_fee_in(
      amount_in: swap_amount,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
      fee_sharing_opt: profit_sharing_opt,
    )
  let slippage_satisfied = is_slippage_satisfied(amount_out)
  if slippage_satisfied {
    let expect_order_value_out =
      order_in_value
        |> value.add(ada_policy_id, ada_asset_name, -used_batcher_fee)
        |> value.add(asset_in_policy_id, asset_in_asset_name, -swap_amount)
        |> value.add(asset_out_policy_id, asset_out_asset_name, amount_out)
    expect
      validate_order_output(
        receiver: receiver,
        receiver_datum_hash_opt: receiver_datum_hash_opt,
        value: expect_order_value_out,
        output: order_output,
      )
    if a_to_b_direction {
      (
        datum_reserve_a + swap_amount - earned_fee_in,
        datum_reserve_b - amount_out,
        value_reserve_a + swap_amount,
        value_reserve_b - amount_out,
        total_liquidity,
      )
    } else {
      (
        datum_reserve_a - amount_out,
        datum_reserve_b + swap_amount - earned_fee_in,
        value_reserve_a - amount_out,
        value_reserve_b + swap_amount,
        total_liquidity,
      )
    }
  } else {
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: sender_datum_hash_opt,
          value: get_returnable_value(
            order_in_value: order_in_value,
            used_batcher_fee: used_batcher_fee,
          ),
          output: order_output,
        ),
      }
    pool_state
  }
}

fn validate_swap_exact_out(
  order_in_value: Value,
  order_output: Output,
  sender: Address,
  sender_datum_hash_opt: Option<CustomDatumHash>,
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  a_to_b_direction: Bool,
  maximum_swap_amount: Int,
  expected_receive: Int,
  asset_a: Asset,
  asset_b: Asset,
  used_batcher_fee: Int,
  trading_fee_a_numerator: Int,
  trading_fee_a_denominator: Int,
  trading_fee_b_numerator: Int,
  trading_fee_b_denominator: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  kill_on_failed: Bool,
  pool_state: PoolState,
) -> PoolState {
  let (
    datum_reserve_a,
    datum_reserve_b,
    value_reserve_a,
    value_reserve_b,
    total_liquidity,
  ) = pool_state
  let (
    asset_in,
    asset_out,
    reserve_in,
    reserve_out,
    trading_fee_numerator,
    trading_fee_denominator,
  ) =
    if a_to_b_direction {
      (
        asset_a,
        asset_b,
        datum_reserve_a,
        datum_reserve_b,
        trading_fee_a_numerator,
        trading_fee_a_denominator,
      )
    } else {
      (
        asset_b,
        asset_a,
        datum_reserve_b,
        datum_reserve_a,
        trading_fee_b_numerator,
        trading_fee_b_denominator,
      )
    }
  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let necessary_amount_in =
    math.calculate_amount_in(
      reserve_in,
      reserve_out,
      expected_receive,
      trading_fee_numerator,
      trading_fee_denominator,
    )
  let earned_fee_in =
    math.calculate_earned_fee_in(
      amount_in: necessary_amount_in,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
      fee_sharing_opt: profit_sharing_opt,
    )
  let slippage_satisfied = necessary_amount_in <= maximum_swap_amount
  if slippage_satisfied {
    let expect_order_value_out =
      order_in_value
        |> value.add(ada_policy_id, ada_asset_name, -used_batcher_fee)
        |> value.add(asset_in_policy_id, asset_in_asset_name, -necessary_amount_in)
        |> value.add(asset_out_policy_id, asset_out_asset_name, expected_receive)
    expect
      validate_order_output(
        receiver: receiver,
        receiver_datum_hash_opt: receiver_datum_hash_opt,
        value: expect_order_value_out,
        output: order_output,
      )
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
  } else {
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: sender_datum_hash_opt,
          value: get_returnable_value(
            order_in_value: order_in_value,
            used_batcher_fee: used_batcher_fee,
          ),
          output: order_output,
        ),
      }
    pool_state
  }
}

fn validate_deposit(
  order_in_value: Value,
  order_output: Output,
  sender: Address,
  sender_datum_hash_opt: Option<CustomDatumHash>,
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  deposit_amount_a: Int,
  deposit_amount_b: Int,
  minimum_lp: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  used_batcher_fee: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  trading_fee_a_numerator: Int,
  trading_fee_a_denominator: Int,
  trading_fee_b_numerator: Int,
  trading_fee_b_denominator: Int,
  kill_on_failed: Bool,
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

  let (earned_fee_a, earned_fee_b, lp_amount) =
    math.calculate_deposit_amount(
      amount_a: deposit_amount_a,
      amount_b: deposit_amount_b,
      reserve_a: datum_reserve_a,
      reserve_b: datum_reserve_b,
      total_liquidity: total_liquidity,
      trading_fee_a_numerator: trading_fee_a_numerator,
      trading_fee_a_denominator: trading_fee_a_denominator,
      trading_fee_b_numerator: trading_fee_b_numerator,
      trading_fee_b_denominator: trading_fee_b_denominator,
      profit_sharing_opt: profit_sharing_opt,
    )
  let slippage_satisfied = lp_amount >= minimum_lp
  if slippage_satisfied {
    let expect_order_value_out =
      order_in_value
        |> value.add(ada_policy_id, ada_asset_name, -used_batcher_fee)
        |> value.add(asset_a_policy_id, asset_a_asset_name, -deposit_amount_a)
        |> value.add(asset_b_policy_id, asset_b_asset_name, -deposit_amount_b)
        |> value.add(lp_asset_policy_id, lp_asset_asset_name, lp_amount)
    expect
      validate_order_output(
        receiver: receiver,
        receiver_datum_hash_opt: receiver_datum_hash_opt,
        value: expect_order_value_out,
        output: order_output,
      )
    (
      datum_reserve_a + deposit_amount_a - earned_fee_a,
      datum_reserve_b + deposit_amount_b - earned_fee_b,
      value_reserve_a + deposit_amount_a,
      value_reserve_b + deposit_amount_b,
      total_liquidity + lp_amount,
    )
  } else {
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: sender_datum_hash_opt,
          value: get_returnable_value(
            order_in_value: order_in_value,
            used_batcher_fee: used_batcher_fee,
          ),
          output: order_output,
        ),
      }
    pool_state
  }
}

fn validate_withdraw(
  order_in_value: Value,
  order_output: Output,
  sender: Address,
  sender_datum_hash_opt: Option<CustomDatumHash>,
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  withdrawal_lp_amount: Int,
  minimum_amount_a: Int,
  minimum_amount_b: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  used_batcher_fee: Int,
  kill_on_failed: Bool,
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
  let (amount_a_out, amount_b_out) =
    math.calculate_withdraw(
      datum_reserve_a,
      datum_reserve_b,
      withdrawal_lp_amount,
      total_liquidity,
    )
  let slippage_satisfied = and {
      amount_a_out >= minimum_amount_a,
      amount_b_out >= minimum_amount_b,
    }
  if slippage_satisfied {
    let expect_order_value_out =
      order_in_value
        |> value.add(ada_policy_id, ada_asset_name, -used_batcher_fee)
        |> value.add(lp_policy_id, lp_asset_name, -withdrawal_lp_amount)
        |> value.add(asset_a_policy_id, asset_a_asset_name, amount_a_out)
        |> value.add(asset_b_policy_id, asset_b_asset_name, amount_b_out)
    expect
      validate_order_output(
        receiver: receiver,
        receiver_datum_hash_opt: receiver_datum_hash_opt,
        value: expect_order_value_out,
        output: order_output,
      )
    (
      datum_reserve_a - amount_a_out,
      datum_reserve_b - amount_b_out,
      value_reserve_a - amount_a_out,
      value_reserve_b - amount_b_out,
      total_liquidity - withdrawal_lp_amount,
    )
  } else {
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: sender_datum_hash_opt,
          value: get_returnable_value(
            order_in_value: order_in_value,
            used_batcher_fee: used_batcher_fee,
          ),
          output: order_output,
        ),
      }
    pool_state
  }
}

fn validate_zap_out(
  order_in_value: Value,
  order_output: Output,
  sender: Address,
  sender_datum_hash_opt: Option<CustomDatumHash>,
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  minimum_receive: Int,
  a_to_b_direction: Bool,
  withdrawal_lp_amount: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  used_batcher_fee: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  trading_fee_a_numerator: Int,
  trading_fee_a_denominator: Int,
  trading_fee_b_numerator: Int,
  trading_fee_b_denominator: Int,
  kill_on_failed: Bool,
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

  let (earned_fee_a, earned_fee_b, amount_out) =
    math.calculate_zap_out(
      withdrawal_lp_amount: withdrawal_lp_amount,
      reserve_a: datum_reserve_a,
      reserve_b: datum_reserve_b,
      total_liquidity: total_liquidity,
      a_to_b_direction: a_to_b_direction,
      trading_fee_a_numerator: trading_fee_a_numerator,
      trading_fee_a_denominator: trading_fee_a_denominator,
      trading_fee_b_numerator: trading_fee_b_numerator,
      trading_fee_b_denominator: trading_fee_b_denominator,
      profit_sharing_opt: profit_sharing_opt,
    )
  let slippage_satisfied = amount_out >= minimum_receive
  if slippage_satisfied {
    let expect_order_value_out =
      order_in_value
        |> value.add(ada_policy_id, ada_asset_name, -used_batcher_fee)
        |> value.add(lp_policy_id, lp_asset_name, -withdrawal_lp_amount)
        |> value.add(asset_out_policy_id, asset_out_asset_name, amount_out)
    expect
      validate_order_output(
        receiver: receiver,
        receiver_datum_hash_opt: receiver_datum_hash_opt,
        value: expect_order_value_out,
        output: order_output,
      )
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
  } else {
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: sender_datum_hash_opt,
          value: get_returnable_value(
            order_in_value: order_in_value,
            used_batcher_fee: used_batcher_fee,
          ),
          output: order_output,
        ),
      }
    pool_state
  }
}

fn validate_partial_swap(
  order_in_value: Value,
  order_out_value: Value,
  a_to_b_direction: Bool,
  total_swap_amount: Int,
  io_ratio_numerator: Int,
  io_ratio_denominator: Int,
  hops: Int,
  minimum_swap_amount_required: Int,
  asset_a: Asset,
  asset_b: Asset,
  used_batcher_fee: Int,
  trading_fee_a_numerator: Int,
  trading_fee_a_denominator: Int,
  trading_fee_b_numerator: Int,
  trading_fee_b_denominator: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  pool_state: PoolState,
) -> (Int, Int, Int, Int, Int, Int, Bool) {
  let (
    datum_reserve_a,
    datum_reserve_b,
    value_reserve_a,
    value_reserve_b,
    total_liquidity,
  ) = pool_state
  let (
    asset_in,
    asset_out,
    reserve_in,
    reserve_out,
    trading_fee_numerator,
    trading_fee_denominator,
  ) =
    if a_to_b_direction {
      (
        asset_a,
        asset_b,
        datum_reserve_a,
        datum_reserve_b,
        trading_fee_a_numerator,
        trading_fee_a_denominator,
      )
    } else {
      (
        asset_b,
        asset_a,
        datum_reserve_b,
        datum_reserve_a,
        trading_fee_b_numerator,
        trading_fee_b_denominator,
      )
    }
  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let max_in_swap =
    math.calculate_max_in_swap(
      reserve_in: reserve_in,
      reserve_out: reserve_out,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
      io_ratio_numerator: io_ratio_numerator,
      io_ratio_denominator: io_ratio_denominator,
    )
  let swapable_amount_in =
    if total_swap_amount <= max_in_swap {
      total_swap_amount
    } else {
      max_in_swap
    }
  let remaining_swap_amount = total_swap_amount - swapable_amount_in
  let amount_out =
    math.calculate_amount_out(
      reserve_in: reserve_in,
      reserve_out: reserve_out,
      amount_in: swapable_amount_in,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
    )
  let earned_fee_in =
    math.calculate_earned_fee_in(
      amount_in: swapable_amount_in,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
      fee_sharing_opt: profit_sharing_opt,
    )
  let expect_order_value_out =
    order_in_value
      |> value.add(ada_policy_id, ada_asset_name, -used_batcher_fee)
      |> value.add(asset_in_policy_id, asset_in_asset_name, -swapable_amount_in)
      |> value.add(asset_out_policy_id, asset_out_asset_name, amount_out)
  expect and {
      swapable_amount_in > 0,
      swapable_amount_in >= minimum_swap_amount_required,
      expect_order_value_out == order_out_value,
    }
  let has_next_swap =
    hops > 1 && remaining_swap_amount >= minimum_swap_amount_required
  if a_to_b_direction {
    (
      datum_reserve_a + swapable_amount_in - earned_fee_in,
      datum_reserve_b - amount_out,
      value_reserve_a + swapable_amount_in,
      value_reserve_b - amount_out,
      total_liquidity,
      remaining_swap_amount,
      has_next_swap,
    )
  } else {
    (
      datum_reserve_a - amount_out,
      datum_reserve_b + swapable_amount_in - earned_fee_in,
      value_reserve_a - amount_out,
      value_reserve_b + swapable_amount_in,
      total_liquidity,
      remaining_swap_amount,
      has_next_swap,
    )
  }
}

fn validate_withdraw_imbalance(
  order_in_value: Value,
  order_output: Output,
  sender: Address,
  sender_datum_hash_opt: Option<CustomDatumHash>,
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  withdrawal_lp_amount: Int,
  ratio_asset_a: Int,
  ratio_asset_b: Int,
  minimum_amount_a: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  used_batcher_fee: Int,
  trading_fee_a_numerator: Int,
  trading_fee_a_denominator: Int,
  trading_fee_b_numerator: Int,
  trading_fee_b_denominator: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  kill_on_failed: Bool,
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
  let (earned_fee_a, earned_fee_b, amount_a_out, amount_b_out) =
    math.calculate_withdraw_imbalance(
      expect_ab_ratio_numerator: ratio_asset_a,
      expect_ab_ratio_denominator: ratio_asset_b,
      reserve_a: datum_reserve_a,
      reserve_b: datum_reserve_b,
      trading_fee_a_numerator: trading_fee_a_numerator,
      trading_fee_a_denominator: trading_fee_a_denominator,
      trading_fee_b_numerator: trading_fee_b_numerator,
      trading_fee_b_denominator: trading_fee_b_denominator,
      withdrawal_lp_amount: withdrawal_lp_amount,
      total_liquidity: total_liquidity,
      profit_sharing_opt: profit_sharing_opt,
    )
  let slippage_satisfied = amount_a_out >= minimum_amount_a
  if slippage_satisfied {
    let expect_order_value_out =
      order_in_value
        |> value.add(ada_policy_id, ada_asset_name, -used_batcher_fee)
        |> value.add(lp_policy_id, lp_asset_name, -withdrawal_lp_amount)
        |> value.add(asset_a_policy_id, asset_a_asset_name, amount_a_out)
        |> value.add(asset_b_policy_id, asset_b_asset_name, amount_b_out)
    expect
      validate_order_output(
        receiver: receiver,
        receiver_datum_hash_opt: receiver_datum_hash_opt,
        value: expect_order_value_out,
        output: order_output,
      )
    (
      datum_reserve_a - amount_a_out - earned_fee_a,
      datum_reserve_b - amount_b_out - earned_fee_b,
      value_reserve_a - amount_a_out,
      value_reserve_b - amount_b_out,
      total_liquidity - withdrawal_lp_amount,
    )
  } else {
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: sender_datum_hash_opt,
          value: get_returnable_value(
            order_in_value: order_in_value,
            used_batcher_fee: used_batcher_fee,
          ),
          output: order_output,
        ),
      }
    pool_state
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
    trading_fee_a_numerator,
    trading_fee_a_denominator,
    trading_fee_b_numerator,
    trading_fee_b_denominator,
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
  let SwapRouting { lp_asset: routing_lp_asset, a_to_b_direction } = routing
  expect pool_lp_asset == routing_lp_asset
  let (reserve_in, reserve_out, trading_fee_numerator, trading_fee_denominator) =
    if a_to_b_direction {
      (
        old_datum_reserve_a,
        old_datum_reserve_b,
        trading_fee_a_numerator,
        trading_fee_a_denominator,
      )
    } else {
      (
        old_datum_reserve_b,
        old_datum_reserve_a,
        trading_fee_b_numerator,
        trading_fee_b_denominator,
      )
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
    math.calculate_earned_fee_in(
      amount_in: amount_in,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
      fee_sharing_opt: profit_sharing,
    )
  expect amount_out > 0
  expect
    if a_to_b_direction {
      and {
        old_datum_reserve_a + amount_in - earned_fee_in == new_datum_reserve_a,
        old_datum_reserve_b - amount_out == new_datum_reserve_b,
        old_value_reserve_a + amount_in == new_value_reserve_a,
        old_value_reserve_b - amount_out == new_value_reserve_b,
      }
    } else {
      and {
        old_datum_reserve_a - amount_out == new_datum_reserve_a,
        old_datum_reserve_b + amount_in - earned_fee_in == new_datum_reserve_b,
        old_value_reserve_a - amount_out == new_value_reserve_a,
        old_value_reserve_b + amount_in == new_value_reserve_b,
      }
    }
  amount_out
}

pub fn get_swap_multi_amount_out(
  amount_in: Int,
  all_pools: List<BatchingPool>,
  all_routings: List<SwapRouting>,
) -> Int {
  expect [pool, ..rest_pools] = all_pools
  expect [routing, ..rest_routings] = all_routings
  let amount_out = get_multi_routing_swap_amount_out(amount_in, pool, routing)
  when rest_pools is {
    [] -> amount_out
    _ ->
      get_swap_multi_amount_out(
        amount_in: amount_out,
        all_pools: rest_pools,
        all_routings: rest_routings,
      )
  }
}

pub fn validate_swap_multi_routing_order(
  pools: List<BatchingPool>,
  routings: List<SwapRouting>,
  order_in_value: Value,
  order_out_value: Value,
  swap_amount: Int,
  minimum_receive: Int,
  used_batcher_fee: Int,
) -> Bool {
  let first_routing = routings |> builtin.head_list
  let last_routing = utils.list_at_index(routings, list.length(routings) - 1)
  let first_pool = pools |> builtin.head_list
  let last_pool = utils.list_at_index(pools, list.length(pools) - 1)
  let SwapRouting { a_to_b_direction: first_routing_a_to_b_direction, .. } =
    first_routing
  let SwapRouting { a_to_b_direction: last_routing_a_to_b_direction, .. } =
    last_routing
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
    if first_routing_a_to_b_direction {
      first_pool_asset_a
    } else {
      first_pool_asset_b
    }
  let asset_out =
    if last_routing_a_to_b_direction {
      last_pool_asset_b
    } else {
      last_pool_asset_a
    }

  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let amount_out =
    get_swap_multi_amount_out(
      amount_in: swap_amount,
      all_pools: pools,
      all_routings: routings,
    )
  let expect_order_value_out =
    order_in_value
      |> value.add(ada_policy_id, ada_asset_name, -used_batcher_fee)
      |> value.add(asset_in_policy_id, asset_in_asset_name, -swap_amount)
      |> value.add(asset_out_policy_id, asset_out_asset_name, amount_out)
  and {
    amount_out >= minimum_receive,
    expect_order_value_out == order_out_value,
  }
}

fn is_valid_datum(
  raw_datum: Datum,
  datum_hash_opt: Option<CustomDatumHash>,
) -> Bool {
  when raw_datum is {
    NoDatum -> None
    DatumHash(dh) -> Some(dh)
    InlineDatum(dat) -> Some(hash.blake2b_256(builtin.serialise_data(dat)))
  } == datum_hash_opt
}

pub fn validate_order_receiver(
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  output: Output,
) -> Bool {
  let Output { address: output_address, datum: raw_order_output_datum, .. } =
    output
  let Address { payment_credential: receiver_payment_cred, .. } = receiver
  let is_correct_address = receiver == output_address
  when receiver_payment_cred is {
    VerificationKeyCredential(_) -> is_correct_address
    ScriptCredential(_) -> and {
        is_correct_address,
        is_valid_datum(
          raw_datum: raw_order_output_datum,
          datum_hash_opt: receiver_datum_hash_opt,
        ),
      }
  }
}

fn validate_order_output(
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  value: Value,
  output: Output,
) -> Bool {
  let Output {
    address: output_address,
    datum: raw_order_output_datum,
    value: output_value,
    ..
  } = output

  let is_correct_address_and_value = and {
      receiver == output_address,
      value == output_value,
    }
  let Address { payment_credential: receiver_payment_cred, .. } = receiver
  when receiver_payment_cred is {
    VerificationKeyCredential(_) -> is_correct_address_and_value
    ScriptCredential(_) -> and {
        is_correct_address_and_value,
        is_valid_datum(
          raw_datum: raw_order_output_datum,
          datum_hash_opt: receiver_datum_hash_opt,
        ),
      }
  }
}

pub fn apply_orders(
  datum_map: DatumMap,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  trading_fee_a_numerator: Int,
  trading_fee_a_denominator: Int,
  trading_fee_b_numerator: Int,
  trading_fee_b_denominator: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  end_valid_time_range: Int,
  order_inputs: List<Input>,
  order_outputs: List<Output>,
  orders_fee: List<Int>,
  pool_state: PoolState,
) -> PoolState {
  expect [input, ..rest_inputs] = order_inputs
  expect [output, ..rest_outputs] = order_outputs
  expect [used_batcher_fee, ..rest_batcher_fees] = orders_fee

  let Input {
    output: Output {
      address: order_in_address,
      value: order_in_value,
      datum: raw_order_in_datum,
      ..
    },
    ..
  } = input
  let Output { value: order_out_value, .. } = output
  expect order_in_datum: OrderDatum =
    utils.must_find_script_datum(datum_map, raw_order_in_datum)

  let OrderDatum {
    sender,
    sender_datum_hash_opt,
    receiver,
    receiver_datum_hash_opt,
    step: order_step,
    max_batcher_fee,
    lp_asset: order_lp_asset,
    expiry_setting_opt,
  } = order_in_datum
  expect and {
      // max_batcher_fee must be positive
      max_batcher_fee > 0,
      // Used Batcher Fee must be positive and less than or equal batcher fee
      used_batcher_fee > 0,
      used_batcher_fee <= max_batcher_fee,
      // lp_asset must be the same with processing Liquidity Pool
      lp_asset == order_lp_asset,
      // In case expired setting is turned on, the execution time must not exceed the expired_time
      when expiry_setting_opt is {
        None -> True
        Some((expired_time, _)) -> end_valid_time_range <= expired_time
      },
    }
  let new_state =
    when order_step is {
      SwapExactIn(
        a_to_b_direction,
        swap_amount,
        minimum_receive,
        order_killable,
      ) -> {
        expect and {
            swap_amount > 0,
            minimum_receive > 0,
          }
        validate_swap_exact_in(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          sender_datum_hash_opt: sender_datum_hash_opt,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          a_to_b_direction: a_to_b_direction,
          swap_amount: swap_amount,
          asset_a: asset_a,
          asset_b: asset_b,
          used_batcher_fee: used_batcher_fee,
          trading_fee_a_numerator: trading_fee_a_numerator,
          trading_fee_a_denominator: trading_fee_a_denominator,
          trading_fee_b_numerator: trading_fee_b_numerator,
          trading_fee_b_denominator: trading_fee_b_denominator,
          profit_sharing_opt: profit_sharing_opt,
          pool_state: pool_state,
          kill_on_failed: order_killable,
          is_slippage_satisfied: fn(amount_out) {
            amount_out >= minimum_receive
          },
        )
      }
      StopLoss(a_to_b_direction, swap_amount, stop_loss_receive) -> {
        expect and {
            swap_amount > 0,
            stop_loss_receive > 0,
          }
        validate_swap_exact_in(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          sender_datum_hash_opt: sender_datum_hash_opt,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          a_to_b_direction: a_to_b_direction,
          swap_amount: swap_amount,
          asset_a: asset_a,
          asset_b: asset_b,
          used_batcher_fee: used_batcher_fee,
          trading_fee_a_numerator: trading_fee_a_numerator,
          trading_fee_a_denominator: trading_fee_a_denominator,
          trading_fee_b_numerator: trading_fee_b_numerator,
          trading_fee_b_denominator: trading_fee_b_denominator,
          profit_sharing_opt: profit_sharing_opt,
          pool_state: pool_state,
          kill_on_failed: False,
          is_slippage_satisfied: fn(amount_out) {
            amount_out <= stop_loss_receive
          },
        )
      }
      OCO(a_to_b_direction, swap_amount, minimum_receive, stop_loss_receive) -> {
        expect and {
            swap_amount > 0,
            minimum_receive > 0,
            stop_loss_receive > 0,
          }
        validate_swap_exact_in(
          order_in_value: order_in_value,
          order_output: output,
          sender_datum_hash_opt: sender_datum_hash_opt,
          sender: sender,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          a_to_b_direction: a_to_b_direction,
          swap_amount: swap_amount,
          asset_a: asset_a,
          asset_b: asset_b,
          used_batcher_fee: used_batcher_fee,
          trading_fee_a_numerator: trading_fee_a_numerator,
          trading_fee_a_denominator: trading_fee_a_denominator,
          trading_fee_b_numerator: trading_fee_b_numerator,
          trading_fee_b_denominator: trading_fee_b_denominator,
          profit_sharing_opt: profit_sharing_opt,
          pool_state: pool_state,
          kill_on_failed: False,
          is_slippage_satisfied: fn(amount_out) {
            amount_out >= minimum_receive || amount_out <= stop_loss_receive
          },
        )
      }
      SwapExactOut(
        a_to_b_direction,
        maximum_swap_amount,
        expected_receive,
        order_killable,
      ) -> {
        expect and {
            maximum_swap_amount > 0,
            expected_receive > 0,
          }
        validate_swap_exact_out(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          sender_datum_hash_opt: sender_datum_hash_opt,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          a_to_b_direction: a_to_b_direction,
          maximum_swap_amount: maximum_swap_amount,
          expected_receive: expected_receive,
          asset_a: asset_a,
          asset_b: asset_b,
          used_batcher_fee: used_batcher_fee,
          trading_fee_a_numerator: trading_fee_a_numerator,
          trading_fee_a_denominator: trading_fee_a_denominator,
          trading_fee_b_numerator: trading_fee_b_numerator,
          trading_fee_b_denominator: trading_fee_b_denominator,
          profit_sharing_opt: profit_sharing_opt,
          kill_on_failed: order_killable,
          pool_state: pool_state,
        )
      }
      Deposit(deposit_amount_a, deposit_amount_b, minimum_lp, order_killable) -> {
        expect and {
            deposit_amount_a >= 0,
            deposit_amount_b >= 0,
            deposit_amount_a + deposit_amount_b > 0,
            minimum_lp > 0,
          }
        validate_deposit(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          sender_datum_hash_opt: sender_datum_hash_opt,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          deposit_amount_a: deposit_amount_a,
          deposit_amount_b: deposit_amount_b,
          minimum_lp: minimum_lp,
          asset_a: asset_a,
          asset_b: asset_b,
          lp_asset: lp_asset,
          used_batcher_fee: used_batcher_fee,
          profit_sharing_opt: profit_sharing_opt,
          trading_fee_a_numerator: trading_fee_a_numerator,
          trading_fee_a_denominator: trading_fee_a_denominator,
          trading_fee_b_numerator: trading_fee_b_numerator,
          trading_fee_b_denominator: trading_fee_b_denominator,
          kill_on_failed: order_killable,
          pool_state: pool_state,
        )
      }
      Withdraw(
        withdrawal_lp_amount,
        minimum_asset_a,
        minimum_asset_b,
        order_killable,
      ) -> {
        expect and {
            withdrawal_lp_amount > 0,
            minimum_asset_a > 0,
            minimum_asset_b > 0,
          }
        validate_withdraw(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          sender_datum_hash_opt: sender_datum_hash_opt,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          withdrawal_lp_amount: withdrawal_lp_amount,
          minimum_amount_a: minimum_asset_a,
          minimum_amount_b: minimum_asset_b,
          asset_a: asset_a,
          asset_b: asset_b,
          lp_asset: lp_asset,
          used_batcher_fee: used_batcher_fee,
          kill_on_failed: order_killable,
          pool_state: pool_state,
        )
      }
      ZapOut(
        a_to_b_direction,
        withdrawal_lp_amount,
        minimum_receive,
        order_killable,
      ) -> {
        expect and {
            withdrawal_lp_amount > 0,
            minimum_receive > 0,
          }
        validate_zap_out(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          sender_datum_hash_opt: sender_datum_hash_opt,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          minimum_receive: minimum_receive,
          a_to_b_direction: a_to_b_direction,
          withdrawal_lp_amount: withdrawal_lp_amount,
          asset_a: asset_a,
          asset_b: asset_b,
          lp_asset: lp_asset,
          used_batcher_fee: used_batcher_fee,
          profit_sharing_opt: profit_sharing_opt,
          trading_fee_a_numerator: trading_fee_a_numerator,
          trading_fee_a_denominator: trading_fee_a_denominator,
          trading_fee_b_numerator: trading_fee_b_numerator,
          trading_fee_b_denominator: trading_fee_b_denominator,
          kill_on_failed: order_killable,
          pool_state: pool_state,
        )
      }
      PartialSwap(
        a_to_b_direction,
        total_swap_amount,
        io_ratio_numerator,
        io_ratio_denominator,
        hops,
        minimum_swap_amount_required,
        max_batcher_fee_each_time,
      ) -> {
        expect and {
            io_ratio_numerator > 0,
            io_ratio_denominator > 0,
            hops > 0,
            minimum_swap_amount_required > 0,
            total_swap_amount >= minimum_swap_amount_required,
            used_batcher_fee <= max_batcher_fee_each_time,
          }
        let (
          new_reserve_a,
          new_reserve_b,
          new_total_liquidity,
          new_liquidity_share,
          new_root_k_last,
          remaining_swap_amount,
          has_next_swap,
        ) =
          validate_partial_swap(
            order_in_value: order_in_value,
            order_out_value: order_out_value,
            a_to_b_direction: a_to_b_direction,
            total_swap_amount: total_swap_amount,
            io_ratio_numerator: io_ratio_numerator,
            io_ratio_denominator: io_ratio_denominator,
            hops: hops,
            minimum_swap_amount_required: minimum_swap_amount_required,
            asset_a: asset_a,
            asset_b: asset_b,
            used_batcher_fee: used_batcher_fee,
            trading_fee_a_numerator: trading_fee_a_numerator,
            trading_fee_a_denominator: trading_fee_a_denominator,
            trading_fee_b_numerator: trading_fee_b_numerator,
            trading_fee_b_denominator: trading_fee_b_denominator,
            profit_sharing_opt: profit_sharing_opt,
            pool_state: pool_state,
          )
        expect
          if has_next_swap {
            let Output {
              address: order_out_address,
              datum: raw_order_out_datum,
              ..
            } = output
            expect order_out_datum: OrderDatum =
              utils.must_find_script_datum(datum_map, raw_order_out_datum)
            let expected_order_out_datum =
              OrderDatum {
                sender,
                sender_datum_hash_opt,
                receiver,
                receiver_datum_hash_opt,
                lp_asset: order_lp_asset,
                step: PartialSwap {
                  a_to_b_direction,
                  total_swap_amount: remaining_swap_amount,
                  io_ratio_numerator,
                  io_ratio_denominator,
                  hops: hops - 1,
                  minimum_swap_amount_required,
                  max_batcher_fee_each_time,
                },
                max_batcher_fee: max_batcher_fee - used_batcher_fee,
                expiry_setting_opt,
              }
            and {
              expected_order_out_datum == order_out_datum,
              order_in_address == order_out_address,
            }
          } else {
            // Order Output must be returned to receiver and might have receiver_datum_hash_opt
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
      WithdrawImbalance(
        withdrawal_lp_amount,
        ratio_asset_a,
        ratio_asset_b,
        minimum_asset_a,
        order_killable,
      ) -> {
        expect and {
            withdrawal_lp_amount > 0,
            ratio_asset_a > 0,
            ratio_asset_b > 0,
            minimum_asset_a > 0,
          }
        validate_withdraw_imbalance(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          sender_datum_hash_opt: sender_datum_hash_opt,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          withdrawal_lp_amount: withdrawal_lp_amount,
          ratio_asset_a: ratio_asset_a,
          ratio_asset_b: ratio_asset_b,
          minimum_amount_a: minimum_asset_a,
          asset_a: asset_a,
          asset_b: asset_b,
          lp_asset: lp_asset,
          used_batcher_fee: used_batcher_fee,
          trading_fee_a_numerator: trading_fee_a_numerator,
          trading_fee_a_denominator: trading_fee_a_denominator,
          trading_fee_b_numerator: trading_fee_b_numerator,
          trading_fee_b_denominator: trading_fee_b_denominator,
          profit_sharing_opt: profit_sharing_opt,
          kill_on_failed: order_killable,
          pool_state: pool_state,
        )
      }
      SwapMultiRouting(_, _, _) -> fail
    }

  when rest_inputs is {
    [] -> new_state
    _ ->
      apply_orders(
        datum_map: datum_map,
        asset_a: asset_a,
        asset_b: asset_b,
        lp_asset: lp_asset,
        trading_fee_a_numerator: trading_fee_a_numerator,
        trading_fee_a_denominator: trading_fee_a_denominator,
        trading_fee_b_numerator: trading_fee_b_numerator,
        trading_fee_b_denominator: trading_fee_b_denominator,
        profit_sharing_opt: profit_sharing_opt,
        end_valid_time_range: end_valid_time_range,
        order_inputs: rest_inputs,
        order_outputs: rest_outputs,
        orders_fee: rest_batcher_fees,
        pool_state: new_state,
      )
  }
}

pub fn validate_cancel_expired_orders(
  order_inputs: List<Input>,
  all_outputs: List<Output>,
  datum_map: DatumMap,
  start_valid_time_range: Int,
) -> Bool {
  expect [order_input, ..rest_order_inputs] = order_inputs
  expect [order_output, ..rest_all_outputs] = all_outputs
  let Input {
    output: Output { value: order_in_value, datum: order_in_datum_raw, .. },
    ..
  } = order_input
  let Output {
    address: order_out_address,
    value: order_out_value,
    datum: raw_order_output_datum,
    ..
  } = order_output

  expect order_in_datum: OrderDatum =
    utils.must_find_script_datum(datum_map, order_in_datum_raw)

  let OrderDatum { sender, sender_datum_hash_opt, expiry_setting_opt, .. } =
    order_in_datum

  expect Some((expired_time, max_tip)) = expiry_setting_opt
  expect and {
      // the transaction must be created after expired time
      expired_time < start_valid_time_range,
      // the output have to paid back to sender
      sender == order_out_address,
      // ADA in the order might be deducted for tipping a canceller
      // The tip must not exceed the maximum tip
      // Other tokens must be returned to sender
      value.lovelace_of(order_out_value) >= value.lovelace_of(order_in_value) - max_tip,
      value.without_lovelace(order_out_value) == value.without_lovelace(
        order_in_value,
      ),
      // If sender is script address, the output have to attach the defined datum
      is_valid_datum(
        raw_datum: raw_order_output_datum,
        datum_hash_opt: sender_datum_hash_opt,
      ),
    }
  if rest_order_inputs == [] {
    True
  } else {
    validate_cancel_expired_orders(
      order_inputs: rest_order_inputs,
      all_outputs: rest_all_outputs,
      datum_map: datum_map,
      start_valid_time_range: start_valid_time_range,
    )
  }
}
