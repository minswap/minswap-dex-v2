use aiken/builtin
use aiken/hash
use aiken/list
use aiken/transaction.{DatumHash, InlineDatum, Input, NoDatum, Output}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{Value, ada_asset_name, ada_policy_id}
use amm_dex_v2/math
use amm_dex_v2/types.{
  AToB, Asset, BToA, BatchingPool, CustomDatumHash, DatumMap, Deposit,
  KillOnFailed, OCO, OrderDatum, PartialSwap, PendingOnFailed, PoolState,
  StopLoss, SwapExactIn, SwapExactOut, SwapMultiRouting, SwapRouting, Withdraw,
  WithdrawImbalance, ZapOut,
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
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  a_to_b_direction: Bool,
  asset_a: Asset,
  asset_b: Asset,
  max_batcher_fee: Int,
  used_batcher_fee: Int,
  output_ada: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  pool_state: PoolState,
  kill_on_failed: Bool,
  is_slippage_sastified: fn(Int) -> Bool,
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
      temp_amount_in - ( max_batcher_fee + output_ada )
    } else {
      temp_amount_in
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
  let slippage_sastified = is_slippage_sastified(amount_out)
  if slippage_sastified {
    let expect_order_value_out =
      value.zero()
        |> value.add(
             ada_policy_id,
             ada_asset_name,
             output_ada + ( max_batcher_fee - used_batcher_fee ),
           )
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
  } else {
    let Address { payment_credential: sender_payment_cred, .. } = sender
    expect VerificationKeyCredential(_) = sender_payment_cred
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: None,
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
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  a_to_b_direction: Bool,
  expected_receive: Int,
  asset_a: Asset,
  asset_b: Asset,
  max_batcher_fee: Int,
  used_batcher_fee: Int,
  output_ada: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
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
      temp_amount_in - ( max_batcher_fee + output_ada )
    } else {
      temp_amount_in
    }
  expect maximum_amount_in > 0
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
  let slippage_sastified = necessary_amount_in <= maximum_amount_in
  if slippage_sastified {
    let expect_order_value_out =
      value.zero()
        |> value.add(
             ada_policy_id,
             ada_asset_name,
             output_ada + ( max_batcher_fee - used_batcher_fee ),
           )
        |> value.add(asset_out_policy_id, asset_out_asset_name, expected_receive)
        |> value.add(
             asset_in_policy_id,
             asset_in_asset_name,
             maximum_amount_in - necessary_amount_in,
           )
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
    let Address { payment_credential: sender_payment_cred, .. } = sender
    expect VerificationKeyCredential(_) = sender_payment_cred
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: None,
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
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  minimum_lp: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  max_batcher_fee: Int,
  used_batcher_fee: Int,
  output_ada: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
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
  let temp_amount_a =
    value.quantity_of(order_in_value, asset_a_policy_id, asset_a_asset_name)
  let amount_b =
    value.quantity_of(order_in_value, asset_b_policy_id, asset_b_asset_name)
  let amount_a =
    if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
      temp_amount_a - ( max_batcher_fee + output_ada )
    } else {
      temp_amount_a
    }
  expect and {
      amount_a >= 0,
      amount_b >= 0,
      amount_a + amount_b > 0,
    }
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
  let slippage_sastified = lp_amount >= minimum_lp
  if slippage_sastified {
    let expect_order_value_out =
      value.zero()
        |> value.add(
             ada_policy_id,
             ada_asset_name,
             output_ada + ( max_batcher_fee - used_batcher_fee ),
           )
        |> value.add(lp_asset_policy_id, lp_asset_asset_name, lp_amount)
    expect
      validate_order_output(
        receiver: receiver,
        receiver_datum_hash_opt: receiver_datum_hash_opt,
        value: expect_order_value_out,
        output: order_output,
      )
    (
      datum_reserve_a + amount_a - earned_fee_a,
      datum_reserve_b + amount_b - earned_fee_b,
      value_reserve_a + amount_a,
      value_reserve_b + amount_b,
      total_liquidity + lp_amount,
    )
  } else {
    let Address { payment_credential: sender_payment_cred, .. } = sender
    expect VerificationKeyCredential(_) = sender_payment_cred
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: None,
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
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  minimum_amount_a: Int,
  minimum_amount_b: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  max_batcher_fee: Int,
  used_batcher_fee: Int,
  output_ada: Int,
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
  let withdrawal_lp_amount =
    value.quantity_of(order_in_value, lp_policy_id, lp_asset_name)
  expect withdrawal_lp_amount > 0
  let (amount_a_out, amount_b_out) =
    math.calculate_withdraw(
      datum_reserve_a,
      datum_reserve_b,
      withdrawal_lp_amount,
      total_liquidity,
    )
  let slippage_sastified = and {
      amount_a_out >= minimum_amount_a,
      amount_b_out >= minimum_amount_b,
    }
  if slippage_sastified {
    let expect_order_value_out =
      value.zero()
        |> value.add(
             ada_policy_id,
             ada_asset_name,
             output_ada + ( max_batcher_fee - used_batcher_fee ),
           )
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
    let Address { payment_credential: sender_payment_cred, .. } = sender
    expect VerificationKeyCredential(_) = sender_payment_cred
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: None,
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
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  minimum_receive: Int,
  a_to_b_direction: Bool,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  max_batcher_fee: Int,
  used_batcher_fee: Int,
  output_ada: Int,
  profit_sharing_opt: Option<(Int, Int)>,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
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
  let withdrawal_lp_amount =
    value.quantity_of(
      self: order_in_value,
      policy_id: lp_policy_id,
      asset_name: lp_asset_name,
    )
  expect withdrawal_lp_amount > 0
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
  let slippage_sastified = amount_out >= minimum_receive
  if slippage_sastified {
    let expect_order_value_out =
      value.zero()
        |> value.add(
             ada_policy_id,
             ada_asset_name,
             output_ada + ( max_batcher_fee - used_batcher_fee ),
           )
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
    let Address { payment_credential: sender_payment_cred, .. } = sender
    expect VerificationKeyCredential(_) = sender_payment_cred
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: None,
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
  io_ratio_numerator: Int,
  io_ratio_denominator: Int,
  hops: Int,
  minimum_swap_amount_required: Int,
  asset_a: Asset,
  asset_b: Asset,
  max_batcher_fee: Int,
  used_batcher_fee: Int,
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
  let ada_in_require = max_batcher_fee + output_ada
  let temp_amount_in =
    value.quantity_of(order_in_value, asset_in_policy_id, asset_in_asset_name)
  let amount_in =
    if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
      temp_amount_in - ada_in_require
    } else {
      temp_amount_in
    }
  let max_in_swap =
    math.calculate_max_in_swap(
      reserve_in: reserve_in,
      reserve_out: reserve_out,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
      io_ratio_numerator: io_ratio_numerator,
      io_ratio_denominator: io_ratio_denominator,
    )
  let swap_amount_in =
    if amount_in <= max_in_swap {
      amount_in
    } else {
      max_in_swap
    }
  let remaining_amount_in = amount_in - swap_amount_in
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
  let temp_old_amount_out =
    value.quantity_of(order_in_value, asset_out_policy_id, asset_out_asset_name)
  let old_amount_out =
    if utils.is_ada_asset(asset_out_policy_id, asset_out_asset_name) {
      temp_old_amount_out - ada_in_require
    } else {
      temp_old_amount_out
    }
  let ada_out_require = max_batcher_fee - used_batcher_fee + output_ada
  let expect_order_value_out =
    value.zero()
      |> value.add(ada_policy_id, ada_asset_name, ada_out_require)
      |> value.add(
           asset_out_policy_id,
           asset_out_asset_name,
           old_amount_out + amount_out,
         )
      |> value.add(asset_in_policy_id, asset_in_asset_name, remaining_amount_in)
  expect and {
      amount_in > 0,
      swap_amount_in > 0,
      swap_amount_in >= minimum_swap_amount_required,
      expect_order_value_out == order_out_value,
    }
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

fn validate_withdraw_imbalance(
  order_in_value: Value,
  order_output: Output,
  sender: Address,
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  ratio_asset_a: Int,
  ratio_asset_b: Int,
  minimum_amount_a: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  max_batcher_fee: Int,
  used_batcher_fee: Int,
  output_ada: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
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
  let withdrawal_lp_amount =
    value.quantity_of(order_in_value, lp_policy_id, lp_asset_name)
  expect withdrawal_lp_amount > 0
  let (earned_fee_a, earned_fee_b, amount_a_out, amount_b_out) =
    math.calculate_withdraw_imbalance(
      expect_ab_ratio_numerator: ratio_asset_a,
      expect_ab_ratio_denominator: ratio_asset_b,
      reserve_a: datum_reserve_a,
      reserve_b: datum_reserve_b,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
      withdrawal_lp_amount: withdrawal_lp_amount,
      total_liquidity: total_liquidity,
      profit_sharing_opt: profit_sharing_opt,
    )
  let slippage_sastified = amount_a_out >= minimum_amount_a
  if slippage_sastified {
    let expect_order_value_out =
      value.zero()
        |> value.add(
             ada_policy_id,
             ada_asset_name,
             output_ada + ( max_batcher_fee - used_batcher_fee ),
           )
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
    let Address { payment_credential: sender_payment_cred, .. } = sender
    expect VerificationKeyCredential(_) = sender_payment_cred
    expect and {
        kill_on_failed,
        validate_order_output(
          receiver: sender,
          receiver_datum_hash_opt: None,
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
      AToB -> and {
          old_datum_reserve_a + amount_in - earned_fee_in == new_datum_reserve_a,
          old_datum_reserve_b - amount_out == new_datum_reserve_b,
          old_value_reserve_a + amount_in == new_value_reserve_a,
          old_value_reserve_b - amount_out == new_value_reserve_b,
        }
      BToA -> and {
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
  max_batcher_fee: Int,
  used_batcher_fee: Int,
  output_ada: Int,
) -> Bool {
  let first_routing = routings |> builtin.head_list
  let last_routing = utils.list_at_index(routings, list.length(routings) - 1)
  let first_pool = pools |> builtin.head_list
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
      temp_amount_in - ( max_batcher_fee + output_ada )
    } else {
      temp_amount_in
    }
  expect amount_in > 0
  let amount_out =
    get_swap_multi_amount_out(
      amount_in: amount_in,
      current_amount_out: 0,
      all_pools: pools,
      all_routings: routings,
    )
  let expect_order_value_out =
    value.zero()
      |> value.add(
           ada_policy_id,
           ada_asset_name,
           output_ada + ( max_batcher_fee - used_batcher_fee ),
         )
      |> value.add(asset_out_policy_id, asset_out_asset_name, amount_out)
  and {
    amount_out >= minimum_receive,
    expect_order_value_out == order_out_value,
  }
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
  and {
    receiver == output_address,
    is_valid_receiver_datum,
  }
}

pub fn validate_order_output(
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
  and {
    receiver == output_address,
    is_valid_receiver_datum,
    value == output_value,
  }
}

pub fn apply_orders(
  datum_map: DatumMap,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  order_hash: ByteArray,
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
    output: Output { value: order_in_value, datum: raw_order_in_datum, .. },
    ..
  } = input
  let Output { value: order_out_value, .. } = output
  expect order_in_datum: OrderDatum =
    when raw_order_in_datum is {
      InlineDatum(d) -> d
      _ -> utils.must_find_script_datum(datum_map, raw_order_in_datum)
    }

  let OrderDatum {
    sender,
    receiver,
    receiver_datum_hash_opt,
    step: order_step,
    max_batcher_fee,
    output_ada,
    lp_asset: order_lp_asset,
    expired_time_opt,
  } = order_in_datum
  expect and {
      // max_batcher_fee and output_ada must be positive
      max_batcher_fee > 0,
      output_ada > 0,
      // Used Batcher Fee must be positive and less than or equal batcher fee
      used_batcher_fee > 0,
      used_batcher_fee <= max_batcher_fee,
      // lp_asset must be the same with processing Liquidity Pool
      lp_asset == order_lp_asset,
      when expired_time_opt is {
        None -> True
        Some(expired_time) -> end_valid_time_range <= expired_time
      },
    }
  let new_state =
    when order_step is {
      SwapExactIn(direction, minimum_receive, order_killable) -> {
        expect minimum_receive > 0
        let a_to_b_direction =
          when direction is {
            AToB -> True
            BToA -> False
          }
        let kill_on_failed =
          when order_killable is {
            KillOnFailed -> True
            PendingOnFailed -> False
          }
        validate_swap_exact_in(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          a_to_b_direction: a_to_b_direction,
          asset_a: asset_a,
          asset_b: asset_b,
          max_batcher_fee: max_batcher_fee,
          used_batcher_fee: used_batcher_fee,
          output_ada: output_ada,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
          profit_sharing_opt: profit_sharing_opt,
          pool_state: pool_state,
          kill_on_failed: kill_on_failed,
          is_slippage_sastified: fn(amount_out) {
            amount_out >= minimum_receive
          },
        )
      }
      StopLoss(direction, stop_loss_receive, order_killable) -> {
        expect stop_loss_receive > 0
        let a_to_b_direction =
          when direction is {
            AToB -> True
            BToA -> False
          }
        let kill_on_failed =
          when order_killable is {
            KillOnFailed -> True
            PendingOnFailed -> False
          }
        validate_swap_exact_in(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          a_to_b_direction: a_to_b_direction,
          asset_a: asset_a,
          asset_b: asset_b,
          max_batcher_fee: max_batcher_fee,
          used_batcher_fee: used_batcher_fee,
          output_ada: output_ada,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
          profit_sharing_opt: profit_sharing_opt,
          pool_state: pool_state,
          kill_on_failed: kill_on_failed,
          is_slippage_sastified: fn(amount_out) {
            amount_out <= stop_loss_receive
          },
        )
      }
      OCO(direction, minimum_receive, stop_loss_receive, order_killable) -> {
        expect and {
            minimum_receive > 0,
            stop_loss_receive > 0,
          }
        let a_to_b_direction =
          when direction is {
            AToB -> True
            BToA -> False
          }
        let kill_on_failed =
          when order_killable is {
            KillOnFailed -> True
            PendingOnFailed -> False
          }
        validate_swap_exact_in(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          a_to_b_direction: a_to_b_direction,
          asset_a: asset_a,
          asset_b: asset_b,
          max_batcher_fee: max_batcher_fee,
          used_batcher_fee: used_batcher_fee,
          output_ada: output_ada,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
          profit_sharing_opt: profit_sharing_opt,
          pool_state: pool_state,
          kill_on_failed: kill_on_failed,
          is_slippage_sastified: fn(amount_out) {
            amount_out >= minimum_receive || amount_out <= stop_loss_receive
          },
        )
      }
      SwapExactOut(direction, expected_receive, order_killable) -> {
        expect expected_receive > 0
        let a_to_b_direction =
          when direction is {
            AToB -> True
            BToA -> False
          }
        let kill_on_failed =
          when order_killable is {
            KillOnFailed -> True
            PendingOnFailed -> False
          }
        validate_swap_exact_out(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          a_to_b_direction: a_to_b_direction,
          expected_receive: expected_receive,
          asset_a: asset_a,
          asset_b: asset_b,
          max_batcher_fee: max_batcher_fee,
          used_batcher_fee: used_batcher_fee,
          output_ada: output_ada,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
          profit_sharing_opt: profit_sharing_opt,
          kill_on_failed: kill_on_failed,
          pool_state: pool_state,
        )
      }
      Deposit(minimum_lp, order_killable) -> {
        expect minimum_lp > 0
        let kill_on_failed =
          when order_killable is {
            KillOnFailed -> True
            PendingOnFailed -> False
          }
        validate_deposit(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          minimum_lp: minimum_lp,
          asset_a: asset_a,
          asset_b: asset_b,
          lp_asset: lp_asset,
          max_batcher_fee: max_batcher_fee,
          used_batcher_fee: used_batcher_fee,
          output_ada: output_ada,
          profit_sharing_opt: profit_sharing_opt,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
          kill_on_failed: kill_on_failed,
          pool_state: pool_state,
        )
      }
      Withdraw(minimum_asset_a, minimum_asset_b, order_killable) -> {
        expect and {
            minimum_asset_a > 0,
            minimum_asset_b > 0,
          }
        let kill_on_failed =
          when order_killable is {
            KillOnFailed -> True
            PendingOnFailed -> False
          }
        validate_withdraw(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          minimum_amount_a: minimum_asset_a,
          minimum_amount_b: minimum_asset_b,
          asset_a: asset_a,
          asset_b: asset_b,
          lp_asset: lp_asset,
          max_batcher_fee: max_batcher_fee,
          used_batcher_fee: used_batcher_fee,
          output_ada: output_ada,
          kill_on_failed: kill_on_failed,
          pool_state: pool_state,
        )
      }
      ZapOut(direction, minimum_receive, order_killable) -> {
        expect minimum_receive > 0
        let a_to_b_direction =
          when direction is {
            AToB -> True
            BToA -> False
          }
        let kill_on_failed =
          when order_killable is {
            KillOnFailed -> True
            PendingOnFailed -> False
          }
        validate_zap_out(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          minimum_receive: minimum_receive,
          a_to_b_direction: a_to_b_direction,
          asset_a: asset_a,
          asset_b: asset_b,
          lp_asset: lp_asset,
          max_batcher_fee: max_batcher_fee,
          used_batcher_fee: used_batcher_fee,
          output_ada: output_ada,
          profit_sharing_opt: profit_sharing_opt,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
          kill_on_failed: kill_on_failed,
          pool_state: pool_state,
        )
      }
      PartialSwap(
        direction,
        io_ratio_numerator,
        io_ratio_denominator,
        hops,
        minimum_swap_amount_required,
        max_batcher_fee_each_time,
      ) -> {
        expect and {
            io_ratio_numerator > 0,
            io_ratio_numerator > 0,
            hops > 0,
            used_batcher_fee <= max_batcher_fee_each_time,
          }
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
            max_batcher_fee: max_batcher_fee,
            used_batcher_fee: used_batcher_fee,
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
            expect order_out_datum: OrderDatum =
              when raw_order_out_datum is {
                InlineDatum(d) -> d
                _ ->
                  utils.must_find_script_datum(datum_map, raw_order_out_datum)
              }
            let expected_order_out_datum =
              OrderDatum {
                sender,
                receiver,
                receiver_datum_hash_opt,
                lp_asset: order_lp_asset,
                step: PartialSwap {
                  direction,
                  io_ratio_numerator,
                  io_ratio_denominator,
                  hops: hops - 1,
                  minimum_swap_amount_required,
                  max_batcher_fee_each_time,
                },
                max_batcher_fee: max_batcher_fee - used_batcher_fee,
                output_ada,
                expired_time_opt,
              }
            and {
              expected_order_out_datum == order_out_datum,
              order_out_script_hash == order_hash,
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
        ratio_asset_a,
        ratio_asset_b,
        minimum_asset_a,
        order_killable,
      ) -> {
        expect and {
            ratio_asset_a > 0,
            ratio_asset_b > 0,
            minimum_asset_a > 0,
          }
        let kill_on_failed =
          when order_killable is {
            KillOnFailed -> True
            PendingOnFailed -> False
          }
        validate_withdraw_imbalance(
          order_in_value: order_in_value,
          order_output: output,
          sender: sender,
          receiver: receiver,
          receiver_datum_hash_opt: receiver_datum_hash_opt,
          ratio_asset_a: ratio_asset_a,
          ratio_asset_b: ratio_asset_b,
          minimum_amount_a: minimum_asset_a,
          asset_a: asset_a,
          asset_b: asset_b,
          lp_asset: lp_asset,
          max_batcher_fee: max_batcher_fee,
          used_batcher_fee: used_batcher_fee,
          output_ada: output_ada,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
          profit_sharing_opt: profit_sharing_opt,
          kill_on_failed: kill_on_failed,
          pool_state: pool_state,
        )
      }
      SwapMultiRouting(_, _) -> fail
    }

  when rest_inputs is {
    [] -> new_state
    _ ->
      apply_orders(
        datum_map: datum_map,
        asset_a: asset_a,
        asset_b: asset_b,
        lp_asset: lp_asset,
        trading_fee_numerator: trading_fee_numerator,
        trading_fee_denominator: trading_fee_denominator,
        order_hash: order_hash,
        profit_sharing_opt: profit_sharing_opt,
        end_valid_time_range: end_valid_time_range,
        order_inputs: rest_inputs,
        order_outputs: rest_outputs,
        orders_fee: rest_batcher_fees,
        pool_state: new_state,
      )
  }
}

test test_validate_swap_exact_in_with_no_fee_sharing() {
  let asset_a = Asset { policy_id: ada_policy_id, asset_name: ada_asset_name }
  let asset_b =
    Asset {
      policy_id: #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
      asset_name: #"4d494e",
    }
  let sender =
    credential.from_verification_key(
      #"84b1e6990b172a07ca85d479b0708e750a98d32d13ad61887c010b78",
    )
  let receiver =
    credential.from_verification_key(
      #"830335f3c2fe6c96b61ee835face48ea0c658e877ac4c81a6a284fb0",
    )
  let max_batcher_fee = 2000000
  let output_ada = 2000000
  let amount_in = 1000000000
  let amount_out = 14834146387
  let order_in_value =
    value.zero()
      |> value.add(
           ada_policy_id,
           ada_asset_name,
           max_batcher_fee + output_ada + amount_in,
         )
  let order_out_value =
    value.zero()
      |> value.add(ada_policy_id, ada_asset_name, output_ada)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           amount_out,
         )
  let order_output =
    Output {
      address: receiver,
      value: order_out_value,
      datum: NoDatum,
      reference_script: None,
    }
  let new_pool_state =
    validate_swap_exact_in(
      order_in_value: order_in_value,
      order_output: order_output,
      sender: sender,
      receiver: receiver,
      receiver_datum_hash_opt: None,
      a_to_b_direction: True,
      asset_a: asset_a,
      asset_b: asset_b,
      max_batcher_fee: max_batcher_fee,
      used_batcher_fee: max_batcher_fee,
      output_ada: output_ada,
      trading_fee_numerator: 3,
      trading_fee_denominator: 1000,
      profit_sharing_opt: None,
      kill_on_failed: False,
      pool_state: (
        27877961987941,
        414804973691450,
        27877961987941,
        414804973691450,
        106241703280080,
      ),
      is_slippage_sastified: fn(o) { o > 1 },
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
  let sender =
    credential.from_verification_key(
      #"84b1e6990b172a07ca85d479b0708e750a98d32d13ad61887c010b78",
    )
  let receiver =
    credential.from_verification_key(
      #"830335f3c2fe6c96b61ee835face48ea0c658e877ac4c81a6a284fb0",
    )
  let max_batcher_fee = 2000000
  let output_ada = 2000000
  let amount_in = 1000000000
  let amount_out = 16200168971
  let order_in_value =
    value.zero()
      |> value.add(
           ada_policy_id,
           ada_asset_name,
           max_batcher_fee + output_ada + amount_in,
         )
  let order_out_value =
    value.zero()
      |> value.add(ada_policy_id, ada_asset_name, output_ada)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           amount_out,
         )
  let order_output =
    Output {
      address: receiver,
      value: order_out_value,
      datum: NoDatum,
      reference_script: None,
    }
  let new_pool_state =
    validate_swap_exact_in(
      order_in_value: order_in_value,
      order_output: order_output,
      sender: sender,
      receiver: receiver,
      receiver_datum_hash_opt: None,
      a_to_b_direction: True,
      asset_a: asset_a,
      asset_b: asset_b,
      max_batcher_fee: max_batcher_fee,
      used_batcher_fee: max_batcher_fee,
      output_ada: output_ada,
      trading_fee_numerator: 3,
      trading_fee_denominator: 1000,
      profit_sharing_opt: Some((1, 6)),
      kill_on_failed: False,
      pool_state: (
        25434557769208,
        413300185707175,
        25434557769208,
        413300185707175,
        101211362398220,
      ),
      is_slippage_sastified: fn(o) { o > 1 },
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
  let sender =
    credential.from_verification_key(
      #"84b1e6990b172a07ca85d479b0708e750a98d32d13ad61887c010b78",
    )
  let receiver =
    credential.from_verification_key(
      #"830335f3c2fe6c96b61ee835face48ea0c658e877ac4c81a6a284fb0",
    )
  let max_batcher_fee = 2000000
  let output_ada = 2000000
  let amount_a = 1000000
  let amount_b = 123112
  let amount_out = 867556
  let order_in_value =
    value.zero()
      |> value.add(
           ada_policy_id,
           ada_asset_name,
           max_batcher_fee + output_ada + amount_a,
         )
      |> value.add(asset_b.policy_id, asset_b.asset_name, amount_b)
  let order_out_value =
    value.zero()
      |> value.add(ada_policy_id, ada_asset_name, output_ada)
      |> value.add(lp_asset.policy_id, lp_asset.asset_name, amount_out)
  let order_output =
    Output {
      address: receiver,
      value: order_out_value,
      datum: NoDatum,
      reference_script: None,
    }
  let new_pool_state =
    validate_deposit(
      order_in_value: order_in_value,
      order_output: order_output,
      sender: sender,
      receiver: receiver,
      receiver_datum_hash_opt: None,
      minimum_lp: amount_out,
      asset_a: asset_a,
      asset_b: asset_b,
      lp_asset: lp_asset,
      max_batcher_fee: max_batcher_fee,
      used_batcher_fee: max_batcher_fee,
      output_ada: output_ada,
      trading_fee_numerator: 1,
      trading_fee_denominator: 100,
      profit_sharing_opt: None,
      kill_on_failed: False,
      pool_state: (1000000, 4000000, 1000000, 4000000, 2000000),
    )
  new_pool_state == (2000000, 4123112, 2000000, 4123112, 2867556)
}

pub fn validate_cancel_expired_orders(
  order_inputs: List<Input>,
  all_outputs: List<Output>,
  weighted_tx_fee: Value,
  datum_map: DatumMap,
  start_valid_time_range: Int,
) -> Bool {
  when order_inputs is {
    [] -> True
    [order_input, ..rest_order_inputs] ->
      when all_outputs is {
        [] -> False
        [order_output, ..rest_all_outputs] -> {
          let Input {
            output: Output {
              value: order_in_value,
              datum: order_in_datum_raw,
              ..
            },
            ..
          } = order_input
          let Output { address: order_out_address, value: order_out_value, .. } =
            order_output

          expect order_in_datum: OrderDatum =
            when order_in_datum_raw is {
              InlineDatum(d) -> d
              _ -> utils.must_find_script_datum(datum_map, order_in_datum_raw)
            }

          let OrderDatum { sender, expired_time_opt, .. } = order_in_datum

          let Address { payment_credential: sender_payment_cred, .. } = sender
          // Only support for Pub Key sender because we don't know the datum of Script sender
          expect VerificationKeyCredential(_) = sender_payment_cred
          expect Some(expired_time) = expired_time_opt
          expect and {
              expired_time < start_valid_time_range,
              sender == order_out_address,
              order_out_value == value.merge(order_in_value, weighted_tx_fee),
            }
          validate_cancel_expired_orders(
            order_inputs: rest_order_inputs,
            all_outputs: rest_all_outputs,
            weighted_tx_fee: weighted_tx_fee,
            datum_map: datum_map,
            start_valid_time_range: start_valid_time_range,
          )
        }
      }
  }
}
