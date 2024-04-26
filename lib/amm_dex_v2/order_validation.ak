use aiken/builtin
use aiken/hash
use aiken/list
use aiken/transaction.{Datum, DatumHash, InlineDatum, Input, NoDatum, Output}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{
  AssetName, PolicyId, Value, ada_asset_name, ada_policy_id,
}
use amm_dex_v2/math
use amm_dex_v2/types.{
  Asset, BatchingPool, DAOAll, DAOSpecificAmount, DatumMap, Deposit,
  DepositAmountOption, Donation, EODDatumHash, EODInlineDatum, EODNoDatum,
  ExtraOrderDatum, OCO, OrderDatum, PartialSwap, PoolState, SAOAll,
  SAOSpecificAmount, SortedValueList, StopLoss, SwapAmountOption, SwapExactIn,
  SwapExactOut, SwapMultiRouting, SwapRouting, WAOAll, WAOSpecificAmount,
  Withdraw, WithdrawAmountOption, WithdrawImbalance, ZapOut,
}
use amm_dex_v2/utils

// Construct the value when order is cancelled by the batcher
// Only batcher fee is deducted from the order value
fn get_returnable_value(order_in_value: Value, used_batcher_fee: Int) -> Value {
  value.add(
    order_in_value,
    ada_policy_id,
    ada_asset_name,
    used_batcher_fee * -1,
  )
}

// Ad hoc solution for predicting order output value.
// This function only handles ADA pairs and has strict asset requirements in the value.
fn get_optimized_swap_output_value(
  order_in_value: Value,
  used_batcher_fee: Int,
  asset_a_policy_id: PolicyId,
  asset_a_asset_name: AssetName,
  asset_b_policy_id: PolicyId,
  asset_b_asset_name: AssetName,
  amount_in: Int,
  amount_out: Int,
  a_to_b: Bool,
) -> Option<SortedValueList> {
  // Ensure that asset A is ADA
  if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
    let order_in_value_list = order_in_value |> utils.value_to_list
    let ada_entry = builtin.head_list(order_in_value_list)
    let rest_0 = builtin.tail_list(order_in_value_list)
    let asset_a_amount =
      builtin.snd_pair(builtin.head_list(builtin.snd_pair(ada_entry)))
    when rest_0 is {
      // If the input value contains only ADA and the swap direction is A To B, 
      // subtract the batcher fee and swap amount of ADA, then add asset B to the output value.
      [] ->
        if a_to_b {
          Some(
            [
              (
                ada_policy_id,
                [
                  (
                    ada_asset_name,
                    asset_a_amount - ( used_batcher_fee + amount_in ),
                  ),
                ],
              ),
              (asset_b_policy_id, [(asset_b_asset_name, amount_out)]),
            ],
          )
        } else {
          fail
        }
      // If the input value contains ADA and one additional asset, with Asset B being swapped for Asset A,
      // subtract the batcher fee and add the output amount to the ADA portion, then subtract the swap amount of Asset B.
      [(asset_pid, [(asset_tn, asset_amount)])] ->
        if
        !a_to_b && asset_pid == asset_b_policy_id && asset_tn == asset_b_asset_name{
        
          // Asset B have change
          if asset_amount > amount_in {
            Some(
              [
                (
                  ada_policy_id,
                  [
                    (
                      ada_asset_name,
                      asset_a_amount - used_batcher_fee + amount_out,
                    ),
                  ],
                ),
                (asset_pid, [(asset_tn, asset_amount - amount_in)]),
              ],
            )
          } else if asset_amount == amount_in {
            // Asset B have no change
            Some(
              [
                (
                  ada_policy_id,
                  [
                    (
                      ada_asset_name,
                      asset_a_amount - used_batcher_fee + amount_out,
                    ),
                  ],
                ),
              ],
            )
          } else {
            fail
          }
        } else {
          None
        }
      _ -> None
    }
  } else {
    None
  }
}

fn get_swap_output_value(
  order_in_value: Value,
  used_batcher_fee: Int,
  asset_in_policy_id: PolicyId,
  asset_in_asset_name: AssetName,
  asset_out_policy_id: PolicyId,
  asset_out_asset_name: AssetName,
  amount_in: Int,
  amount_out: Int,
) -> Value {
  if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
    order_in_value
      |> value.add(ada_policy_id, ada_asset_name, -(used_batcher_fee + amount_in))
      |> value.add(asset_out_policy_id, asset_out_asset_name, amount_out)
  } else if utils.is_ada_asset(asset_out_policy_id, asset_out_asset_name) {
    order_in_value
      |> value.add(ada_policy_id, ada_asset_name, amount_out - used_batcher_fee)
      |> value.add(asset_in_policy_id, asset_in_asset_name, -amount_in)
  } else {
    order_in_value
      |> value.add(ada_policy_id, ada_asset_name, -used_batcher_fee)
      |> value.add(asset_in_policy_id, asset_in_asset_name, -amount_in)
      |> value.add(asset_out_policy_id, asset_out_asset_name, amount_out)
  }
}

fn compare_swap_output_value(
  order_in_value: Value,
  order_out_value: Value,
  used_batcher_fee: Int,
  asset_a: Asset,
  asset_b: Asset,
  a_to_b_direction: Bool,
  amount_in: Int,
  amount_out: Int,
) -> Bool {
  when
    get_optimized_swap_output_value(
      order_in_value: order_in_value,
      used_batcher_fee: used_batcher_fee,
      asset_a_policy_id: asset_a.policy_id,
      asset_a_asset_name: asset_a.asset_name,
      asset_b_policy_id: asset_b.policy_id,
      asset_b_asset_name: asset_b.asset_name,
      amount_in: amount_in,
      amount_out: amount_out,
      a_to_b: a_to_b_direction,
    )
  is {
    Some(v) -> v == ( order_out_value |> utils.value_to_list )
    None -> {
      let (asset_in, asset_out) =
        if a_to_b_direction {
          (asset_a, asset_b)
        } else {
          (asset_b, asset_a)
        }
      let Asset {
        policy_id: asset_in_policy_id,
        asset_name: asset_in_asset_name,
      } = asset_in
      let Asset {
        policy_id: asset_out_policy_id,
        asset_name: asset_out_asset_name,
      } = asset_out
      order_out_value == get_swap_output_value(
        order_in_value: order_in_value,
        used_batcher_fee: used_batcher_fee,
        asset_in_policy_id: asset_in_policy_id,
        asset_in_asset_name: asset_in_asset_name,
        asset_out_policy_id: asset_out_policy_id,
        asset_out_asset_name: asset_out_asset_name,
        amount_in: amount_in,
        amount_out: amount_out,
      )
    }
  }
}

fn validate_swap_exact_in(
  order_in_value: Value,
  order_output: Output,
  refund_receiver: Address,
  refund_receiver_datum: ExtraOrderDatum,
  success_receiver: Address,
  success_receiver_datum: ExtraOrderDatum,
  a_to_b_direction: Bool,
  swap_amount_option: SwapAmountOption,
  asset_a: Asset,
  asset_b: Asset,
  used_batcher_fee: Int,
  trading_fee_a_numerator: Int,
  trading_fee_b_numerator: Int,
  fee_sharing_numerator_opt: Option<Int>,
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
  let (asset_in, reserve_in, reserve_out, trading_fee_numerator) =
    if a_to_b_direction {
      (asset_a, datum_reserve_a, datum_reserve_b, trading_fee_a_numerator)
    } else {
      (asset_b, datum_reserve_b, datum_reserve_a, trading_fee_b_numerator)
    }
  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in

  let swap_amount =
    when swap_amount_option is {
      SAOSpecificAmount(am) -> am
      SAOAll(deducted_amount) -> {
        // deducted amount must be non-negative
        expect deducted_amount >= 0
        value.quantity_of(
          order_in_value,
          asset_in_policy_id,
          asset_in_asset_name,
        ) - deducted_amount
      }
    }

  // swap amout must be positive
  expect swap_amount > 0
  let amount_out =
    math.calculate_amount_out(
      reserve_in: reserve_in,
      reserve_out: reserve_out,
      amount_in: swap_amount,
      trading_fee_numerator: trading_fee_numerator,
    )
  let earned_fee_in =
    math.calculate_earned_fee_in(
      amount_in: swap_amount,
      trading_fee_numerator: trading_fee_numerator,
      fee_sharing_numerator_opt: fee_sharing_numerator_opt,
    )
  let slippage_satisfied = is_slippage_satisfied(amount_out)
  if slippage_satisfied {
    expect and {
        validate_order_output_except_value(
          receiver: success_receiver,
          receiver_datum: success_receiver_datum,
          output: order_output,
        ),
        compare_swap_output_value(
          order_in_value: order_in_value,
          order_out_value: order_output.value,
          used_batcher_fee: used_batcher_fee,
          asset_a: asset_a,
          asset_b: asset_b,
          a_to_b_direction: a_to_b_direction,
          amount_in: swap_amount,
          amount_out: amount_out,
        ),
      }
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
          receiver: refund_receiver,
          receiver_datum: refund_receiver_datum,
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
  refund_receiver: Address,
  refund_receiver_datum: ExtraOrderDatum,
  success_receiver: Address,
  success_receiver_datum: ExtraOrderDatum,
  a_to_b_direction: Bool,
  maximum_swap_amount_option: SwapAmountOption,
  expected_receive: Int,
  asset_a: Asset,
  asset_b: Asset,
  used_batcher_fee: Int,
  trading_fee_a_numerator: Int,
  trading_fee_b_numerator: Int,
  fee_sharing_numerator_opt: Option<Int>,
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
  let (asset_in, asset_out, reserve_in, reserve_out, trading_fee_numerator) =
    if a_to_b_direction {
      (
        asset_a,
        asset_b,
        datum_reserve_a,
        datum_reserve_b,
        trading_fee_a_numerator,
      )
    } else {
      (
        asset_b,
        asset_a,
        datum_reserve_b,
        datum_reserve_a,
        trading_fee_b_numerator,
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
    )
  let earned_fee_in =
    math.calculate_earned_fee_in(
      amount_in: necessary_amount_in,
      trading_fee_numerator: trading_fee_numerator,
      fee_sharing_numerator_opt: fee_sharing_numerator_opt,
    )
  let maximum_swap_amount =
    when maximum_swap_amount_option is {
      SAOSpecificAmount(am) -> am
      SAOAll(deducted_amount) -> {
        // deducted amount must be non-negative
        expect deducted_amount >= 0
        value.quantity_of(
          order_in_value,
          asset_in_policy_id,
          asset_in_asset_name,
        ) - deducted_amount
      }
    }
  // maximum swap amount must be non-negative
  expect maximum_swap_amount > 0
  let slippage_satisfied = necessary_amount_in <= maximum_swap_amount
  if slippage_satisfied {
    let expect_order_value_out =
      get_swap_output_value(
        order_in_value: order_in_value,
        used_batcher_fee: used_batcher_fee,
        asset_in_policy_id: asset_in_policy_id,
        asset_in_asset_name: asset_in_asset_name,
        asset_out_policy_id: asset_out_policy_id,
        asset_out_asset_name: asset_out_asset_name,
        amount_in: necessary_amount_in,
        amount_out: expected_receive,
      )
    expect
      validate_order_output(
        receiver: success_receiver,
        receiver_datum: success_receiver_datum,
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
          receiver: refund_receiver,
          receiver_datum: refund_receiver_datum,
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
  refund_receiver: Address,
  refund_receiver_datum: ExtraOrderDatum,
  success_receiver: Address,
  success_receiver_datum: ExtraOrderDatum,
  deposit_amount_option: DepositAmountOption,
  minimum_lp: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  used_batcher_fee: Int,
  fee_sharing_numerator_opt: Option<Int>,
  trading_fee_a_numerator: Int,
  trading_fee_b_numerator: Int,
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
  let (deposit_amount_a, deposit_amount_b) =
    when deposit_amount_option is {
      DAOSpecificAmount(am_a, am_b) -> (am_a, am_b)
      DAOAll(deducted_amount_a, deducted_amount_b) -> {
        // deducted amount a & b must be non-negative
        expect and {
            deducted_amount_a >= 0,
            deducted_amount_b >= 0,
          }
        let am_a =
          value.quantity_of(
            order_in_value,
            asset_a_policy_id,
            asset_a_asset_name,
          ) - deducted_amount_a
        let am_b =
          value.quantity_of(
            order_in_value,
            asset_b_policy_id,
            asset_b_asset_name,
          ) - deducted_amount_b
        (am_a, am_b)
      }
    }

  // amount a and b must be non-negative and sum of them must be positive
  // if amount a or amount b is zero, it's one side deposit case
  expect and {
      deposit_amount_a >= 0,
      deposit_amount_b >= 0,
      deposit_amount_a + deposit_amount_b > 0,
    }

  let (earned_fee_a, earned_fee_b, lp_amount) =
    math.calculate_deposit_amount(
      amount_a: deposit_amount_a,
      amount_b: deposit_amount_b,
      reserve_a: datum_reserve_a,
      reserve_b: datum_reserve_b,
      total_liquidity: total_liquidity,
      trading_fee_a_numerator: trading_fee_a_numerator,
      trading_fee_b_numerator: trading_fee_b_numerator,
      fee_sharing_numerator_opt: fee_sharing_numerator_opt,
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
        receiver: success_receiver,
        receiver_datum: success_receiver_datum,
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
          receiver: refund_receiver,
          receiver_datum: refund_receiver_datum,
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
  refund_receiver: Address,
  refund_receiver_datum: ExtraOrderDatum,
  success_receiver: Address,
  success_receiver_datum: ExtraOrderDatum,
  withdrawal_amount_option: WithdrawAmountOption,
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
  let withdrawal_lp_amount =
    when withdrawal_amount_option is {
      WAOSpecificAmount(am) -> am
      WAOAll(deducted_amount) -> {
        // deducted amount must be non-negative
        expect deducted_amount >= 0
        value.quantity_of(order_in_value, lp_policy_id, lp_asset_name) - deducted_amount
      }
    }

  // withdrawal amount must be positive
  expect withdrawal_lp_amount > 0
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
        receiver: success_receiver,
        receiver_datum: success_receiver_datum,
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
          receiver: refund_receiver,
          receiver_datum: refund_receiver_datum,
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
  refund_receiver: Address,
  refund_receiver_datum: ExtraOrderDatum,
  success_receiver: Address,
  success_receiver_datum: ExtraOrderDatum,
  minimum_receive: Int,
  a_to_b_direction: Bool,
  withdrawal_amount_option: WithdrawAmountOption,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  used_batcher_fee: Int,
  fee_sharing_numerator_opt: Option<Int>,
  trading_fee_a_numerator: Int,
  trading_fee_b_numerator: Int,
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
    when withdrawal_amount_option is {
      WAOSpecificAmount(am) -> am
      WAOAll(deducted_amount) -> {
        // deducted amount must be non-negative
        expect deducted_amount >= 0
        value.quantity_of(order_in_value, lp_policy_id, lp_asset_name) - deducted_amount
      }
    }

  // withdrawal amount must be positive
  expect withdrawal_lp_amount > 0
  let (earned_fee_a, earned_fee_b, amount_out) =
    math.calculate_zap_out(
      withdrawal_lp_amount: withdrawal_lp_amount,
      reserve_a: datum_reserve_a,
      reserve_b: datum_reserve_b,
      total_liquidity: total_liquidity,
      a_to_b_direction: a_to_b_direction,
      trading_fee_a_numerator: trading_fee_a_numerator,
      trading_fee_b_numerator: trading_fee_b_numerator,
      fee_sharing_numerator_opt: fee_sharing_numerator_opt,
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
        receiver: success_receiver,
        receiver_datum: success_receiver_datum,
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
          receiver: refund_receiver,
          receiver_datum: refund_receiver_datum,
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
  trading_fee_b_numerator: Int,
  fee_sharing_numerator_opt: Option<Int>,
  pool_state: PoolState,
) -> (Int, Int, Int, Int, Int, Int, Bool) {
  let (
    datum_reserve_a,
    datum_reserve_b,
    value_reserve_a,
    value_reserve_b,
    total_liquidity,
  ) = pool_state
  let (asset_in, asset_out, reserve_in, reserve_out, trading_fee_numerator) =
    if a_to_b_direction {
      (
        asset_a,
        asset_b,
        datum_reserve_a,
        datum_reserve_b,
        trading_fee_a_numerator,
      )
    } else {
      (
        asset_b,
        asset_a,
        datum_reserve_b,
        datum_reserve_a,
        trading_fee_b_numerator,
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
    )
  let earned_fee_in =
    math.calculate_earned_fee_in(
      amount_in: swapable_amount_in,
      trading_fee_numerator: trading_fee_numerator,
      fee_sharing_numerator_opt: fee_sharing_numerator_opt,
    )
  let expect_order_value_out =
    get_swap_output_value(
      order_in_value: order_in_value,
      used_batcher_fee: used_batcher_fee,
      asset_in_policy_id: asset_in_policy_id,
      asset_in_asset_name: asset_in_asset_name,
      asset_out_policy_id: asset_out_policy_id,
      asset_out_asset_name: asset_out_asset_name,
      amount_in: swapable_amount_in,
      amount_out: amount_out,
    )
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
  refund_receiver: Address,
  refund_receiver_datum: ExtraOrderDatum,
  success_receiver: Address,
  success_receiver_datum: ExtraOrderDatum,
  withdrawal_amount_option: WithdrawAmountOption,
  ratio_asset_a: Int,
  ratio_asset_b: Int,
  minimum_amount_a: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  used_batcher_fee: Int,
  trading_fee_a_numerator: Int,
  trading_fee_b_numerator: Int,
  fee_sharing_numerator_opt: Option<Int>,
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
    when withdrawal_amount_option is {
      WAOSpecificAmount(am) -> am
      WAOAll(deducted_amount) -> {
        // deducted amount must be non-negative
        expect deducted_amount >= 0
        value.quantity_of(order_in_value, lp_policy_id, lp_asset_name) - deducted_amount
      }
    }
  // withdrawal amount must be positive
  expect withdrawal_lp_amount > 0
  let (earned_fee_a, earned_fee_b, amount_a_out, amount_b_out) =
    math.calculate_withdraw_imbalance(
      expect_ab_ratio_numerator: ratio_asset_a,
      expect_ab_ratio_denominator: ratio_asset_b,
      reserve_a: datum_reserve_a,
      reserve_b: datum_reserve_b,
      trading_fee_a_numerator: trading_fee_a_numerator,
      trading_fee_b_numerator: trading_fee_b_numerator,
      withdrawal_lp_amount: withdrawal_lp_amount,
      total_liquidity: total_liquidity,
      fee_sharing_numerator_opt: fee_sharing_numerator_opt,
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
        receiver: success_receiver,
        receiver_datum: success_receiver_datum,
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
          receiver: refund_receiver,
          receiver_datum: refund_receiver_datum,
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

fn validate_donation(
  order_in_value: Value,
  asset_a: Asset,
  asset_b: Asset,
  used_batcher_fee: Int,
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
  let temp_amount_a =
    order_in_value |> value.quantity_of(asset_a_policy_id, asset_a_asset_name)
  let amount_a =
    if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
      temp_amount_a - used_batcher_fee
    } else {
      let ada_amount =
        order_in_value |> value.quantity_of(ada_policy_id, ada_asset_name)
      expect ada_amount >= used_batcher_fee
      temp_amount_a
    }
  let amount_b =
    order_in_value |> value.quantity_of(asset_b_policy_id, asset_b_asset_name)

  expect and {
      amount_a >= 0,
      amount_b >= 0,
      amount_a + amount_b > 0,
    }
  (
    datum_reserve_a + amount_a,
    datum_reserve_b + amount_b,
    value_reserve_a + amount_a,
    value_reserve_b + amount_b,
    total_liquidity,
  )
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
    trading_fee_b_numerator,
    fee_sharing_numerator_opt,
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
  let (reserve_in, reserve_out, trading_fee_numerator) =
    if a_to_b_direction {
      (old_datum_reserve_a, old_datum_reserve_b, trading_fee_a_numerator)
    } else {
      (old_datum_reserve_b, old_datum_reserve_a, trading_fee_b_numerator)
    }

  expect amount_in > 0
  let amount_out =
    math.calculate_amount_out(
      reserve_in: reserve_in,
      reserve_out: reserve_out,
      amount_in: amount_in,
      trading_fee_numerator: trading_fee_numerator,
    )
  let earned_fee_in =
    math.calculate_earned_fee_in(
      amount_in: amount_in,
      trading_fee_numerator: trading_fee_numerator,
      fee_sharing_numerator_opt: fee_sharing_numerator_opt,
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
  swap_amount_option: SwapAmountOption,
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
  let swap_amount =
    when swap_amount_option is {
      SAOSpecificAmount(am) -> am
      SAOAll(deducted_amount) -> {
        // deducted amount must be non-negative
        expect deducted_amount >= 0
        value.quantity_of(
          order_in_value,
          asset_in_policy_id,
          asset_in_asset_name,
        ) - deducted_amount
      }
    }
  // swap amount must be positive
  expect swap_amount > 0
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

fn is_valid_datum(raw_datum: Datum, extra_order_datum: ExtraOrderDatum) -> Bool {
  let expect_extra_order_datum =
    when raw_datum is {
      NoDatum -> EODNoDatum
      DatumHash(dh) -> EODDatumHash(dh)
      InlineDatum(dat) ->
        EODInlineDatum(hash.blake2b_256(builtin.serialise_data(dat)))
    }
  extra_order_datum == expect_extra_order_datum
}

pub fn validate_order_receiver(
  receiver: Address,
  receiver_datum: ExtraOrderDatum,
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
          extra_order_datum: receiver_datum,
        ),
      }
  }
}

fn validate_order_output(
  receiver: Address,
  receiver_datum: ExtraOrderDatum,
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
          extra_order_datum: receiver_datum,
        ),
      }
  }
}

fn validate_order_output_except_value(
  receiver: Address,
  receiver_datum: ExtraOrderDatum,
  output: Output,
) -> Bool {
  let Output { address: output_address, datum: raw_order_output_datum, .. } =
    output

  let Address { payment_credential: receiver_payment_cred, .. } = receiver
  when receiver_payment_cred is {
    VerificationKeyCredential(_) -> receiver == output_address
    ScriptCredential(_) -> and {
        receiver == output_address,
        is_valid_datum(
          raw_datum: raw_order_output_datum,
          extra_order_datum: receiver_datum,
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
  trading_fee_b_numerator: Int,
  fee_sharing_numerator_opt: Option<Int>,
  current_time_approximation: Int,
  order_inputs: List<Input>,
  all_outputs: List<Output>,
  orders_fee: List<Int>,
  pool_state: PoolState,
) -> PoolState {
  expect [input, ..rest_inputs] = order_inputs
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
  expect order_in_datum: OrderDatum =
    utils.must_find_script_datum(datum_map, raw_order_in_datum)

  let OrderDatum {
    canceller,
    refund_receiver,
    refund_receiver_datum,
    success_receiver,
    success_receiver_datum,
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
        Some((expired_time, _)) -> current_time_approximation <= expired_time
      },
    }
  let (new_state, rest_outs) =
    when order_step is {
      SwapExactIn(
        a_to_b_direction,
        swap_amount_option,
        minimum_receive,
        order_killable,
      ) -> {
        expect [output, ..rest_outputs] = all_outputs
        expect minimum_receive > 0
        (
          validate_swap_exact_in(
            order_in_value: order_in_value,
            order_output: output,
            refund_receiver: refund_receiver,
            refund_receiver_datum: refund_receiver_datum,
            success_receiver: success_receiver,
            success_receiver_datum: success_receiver_datum,
            a_to_b_direction: a_to_b_direction,
            swap_amount_option: swap_amount_option,
            asset_a: asset_a,
            asset_b: asset_b,
            used_batcher_fee: used_batcher_fee,
            trading_fee_a_numerator: trading_fee_a_numerator,
            trading_fee_b_numerator: trading_fee_b_numerator,
            fee_sharing_numerator_opt: fee_sharing_numerator_opt,
            pool_state: pool_state,
            kill_on_failed: order_killable,
            is_slippage_satisfied: fn(amount_out) {
              amount_out >= minimum_receive
            },
          ),
          rest_outputs,
        )
      }
      StopLoss(a_to_b_direction, swap_amount_option, stop_loss_receive) -> {
        expect [output, ..rest_outputs] = all_outputs
        expect stop_loss_receive > 0
        (
          validate_swap_exact_in(
            order_in_value: order_in_value,
            order_output: output,
            refund_receiver: refund_receiver,
            refund_receiver_datum: refund_receiver_datum,
            success_receiver: success_receiver,
            success_receiver_datum: success_receiver_datum,
            a_to_b_direction: a_to_b_direction,
            swap_amount_option: swap_amount_option,
            asset_a: asset_a,
            asset_b: asset_b,
            used_batcher_fee: used_batcher_fee,
            trading_fee_a_numerator: trading_fee_a_numerator,
            trading_fee_b_numerator: trading_fee_b_numerator,
            fee_sharing_numerator_opt: fee_sharing_numerator_opt,
            pool_state: pool_state,
            kill_on_failed: False,
            is_slippage_satisfied: fn(amount_out) {
              amount_out <= stop_loss_receive
            },
          ),
          rest_outputs,
        )
      }
      OCO(
        a_to_b_direction,
        swap_amount_option,
        minimum_receive,
        stop_loss_receive,
      ) -> {
        expect [output, ..rest_outputs] = all_outputs
        expect and {
            minimum_receive > 0,
            stop_loss_receive > 0,
          }
        (
          validate_swap_exact_in(
            order_in_value: order_in_value,
            order_output: output,
            refund_receiver: refund_receiver,
            refund_receiver_datum: refund_receiver_datum,
            success_receiver: success_receiver,
            success_receiver_datum: success_receiver_datum,
            a_to_b_direction: a_to_b_direction,
            swap_amount_option: swap_amount_option,
            asset_a: asset_a,
            asset_b: asset_b,
            used_batcher_fee: used_batcher_fee,
            trading_fee_a_numerator: trading_fee_a_numerator,
            trading_fee_b_numerator: trading_fee_b_numerator,
            fee_sharing_numerator_opt: fee_sharing_numerator_opt,
            pool_state: pool_state,
            kill_on_failed: False,
            is_slippage_satisfied: fn(amount_out) {
              amount_out >= minimum_receive || amount_out <= stop_loss_receive
            },
          ),
          rest_outputs,
        )
      }
      SwapExactOut(
        a_to_b_direction,
        maximum_swap_amount_option,
        expected_receive,
        order_killable,
      ) -> {
        expect [output, ..rest_outputs] = all_outputs
        expect expected_receive > 0
        (
          validate_swap_exact_out(
            order_in_value: order_in_value,
            order_output: output,
            refund_receiver: refund_receiver,
            refund_receiver_datum: refund_receiver_datum,
            success_receiver: success_receiver,
            success_receiver_datum: success_receiver_datum,
            a_to_b_direction: a_to_b_direction,
            maximum_swap_amount_option: maximum_swap_amount_option,
            expected_receive: expected_receive,
            asset_a: asset_a,
            asset_b: asset_b,
            used_batcher_fee: used_batcher_fee,
            trading_fee_a_numerator: trading_fee_a_numerator,
            trading_fee_b_numerator: trading_fee_b_numerator,
            fee_sharing_numerator_opt: fee_sharing_numerator_opt,
            kill_on_failed: order_killable,
            pool_state: pool_state,
          ),
          rest_outputs,
        )
      }
      Deposit(deposit_amount_option, minimum_lp, order_killable) -> {
        expect [output, ..rest_outputs] = all_outputs
        expect minimum_lp > 0
        (
          validate_deposit(
            order_in_value: order_in_value,
            order_output: output,
            refund_receiver: refund_receiver,
            refund_receiver_datum: refund_receiver_datum,
            success_receiver: success_receiver,
            success_receiver_datum: success_receiver_datum,
            deposit_amount_option: deposit_amount_option,
            minimum_lp: minimum_lp,
            asset_a: asset_a,
            asset_b: asset_b,
            lp_asset: lp_asset,
            used_batcher_fee: used_batcher_fee,
            fee_sharing_numerator_opt: fee_sharing_numerator_opt,
            trading_fee_a_numerator: trading_fee_a_numerator,
            trading_fee_b_numerator: trading_fee_b_numerator,
            kill_on_failed: order_killable,
            pool_state: pool_state,
          ),
          rest_outputs,
        )
      }
      Withdraw(
        withdrawal_amount_option,
        minimum_asset_a,
        minimum_asset_b,
        order_killable,
      ) -> {
        expect [output, ..rest_outputs] = all_outputs
        expect and {
            minimum_asset_a > 0,
            minimum_asset_b > 0,
          }
        (
          validate_withdraw(
            order_in_value: order_in_value,
            order_output: output,
            refund_receiver: refund_receiver,
            refund_receiver_datum: refund_receiver_datum,
            success_receiver: success_receiver,
            success_receiver_datum: success_receiver_datum,
            withdrawal_amount_option: withdrawal_amount_option,
            minimum_amount_a: minimum_asset_a,
            minimum_amount_b: minimum_asset_b,
            asset_a: asset_a,
            asset_b: asset_b,
            lp_asset: lp_asset,
            used_batcher_fee: used_batcher_fee,
            kill_on_failed: order_killable,
            pool_state: pool_state,
          ),
          rest_outputs,
        )
      }
      ZapOut(
        a_to_b_direction,
        withdrawal_amount_option,
        minimum_receive,
        order_killable,
      ) -> {
        expect [output, ..rest_outputs] = all_outputs
        expect minimum_receive > 0
        (
          validate_zap_out(
            order_in_value: order_in_value,
            order_output: output,
            refund_receiver: refund_receiver,
            refund_receiver_datum: refund_receiver_datum,
            success_receiver: success_receiver,
            success_receiver_datum: success_receiver_datum,
            minimum_receive: minimum_receive,
            a_to_b_direction: a_to_b_direction,
            withdrawal_amount_option: withdrawal_amount_option,
            asset_a: asset_a,
            asset_b: asset_b,
            lp_asset: lp_asset,
            used_batcher_fee: used_batcher_fee,
            fee_sharing_numerator_opt: fee_sharing_numerator_opt,
            trading_fee_a_numerator: trading_fee_a_numerator,
            trading_fee_b_numerator: trading_fee_b_numerator,
            kill_on_failed: order_killable,
            pool_state: pool_state,
          ),
          rest_outputs,
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
        expect [output, ..rest_outputs] = all_outputs
        let Output { value: order_out_value, .. } = output
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
            trading_fee_b_numerator: trading_fee_b_numerator,
            fee_sharing_numerator_opt: fee_sharing_numerator_opt,
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
                canceller,
                refund_receiver,
                refund_receiver_datum,
                success_receiver,
                success_receiver_datum,
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
            // Order Output must be returned to receiver and might have receiver_datum
            validate_order_receiver(
              receiver: success_receiver,
              receiver_datum: success_receiver_datum,
              output: output,
            )
          }
        (
          (
            new_reserve_a,
            new_reserve_b,
            new_total_liquidity,
            new_liquidity_share,
            new_root_k_last,
          ),
          rest_outputs,
        )
      }
      WithdrawImbalance(
        withdrawal_amount_option,
        ratio_asset_a,
        ratio_asset_b,
        minimum_asset_a,
        order_killable,
      ) -> {
        expect [output, ..rest_outputs] = all_outputs
        expect and {
            ratio_asset_a > 0,
            ratio_asset_b > 0,
            minimum_asset_a > 0,
          }
        (
          validate_withdraw_imbalance(
            order_in_value: order_in_value,
            order_output: output,
            refund_receiver: refund_receiver,
            refund_receiver_datum: refund_receiver_datum,
            success_receiver: success_receiver,
            success_receiver_datum: success_receiver_datum,
            withdrawal_amount_option: withdrawal_amount_option,
            ratio_asset_a: ratio_asset_a,
            ratio_asset_b: ratio_asset_b,
            minimum_amount_a: minimum_asset_a,
            asset_a: asset_a,
            asset_b: asset_b,
            lp_asset: lp_asset,
            used_batcher_fee: used_batcher_fee,
            trading_fee_a_numerator: trading_fee_a_numerator,
            trading_fee_b_numerator: trading_fee_b_numerator,
            fee_sharing_numerator_opt: fee_sharing_numerator_opt,
            kill_on_failed: order_killable,
            pool_state: pool_state,
          ),
          rest_outputs,
        )
      }
      Donation ->
        (
          validate_donation(
            order_in_value: order_in_value,
            asset_a: asset_a,
            asset_b: asset_b,
            used_batcher_fee: used_batcher_fee,
            pool_state: pool_state,
          ),
          all_outputs,
        )
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
        trading_fee_b_numerator: trading_fee_b_numerator,
        fee_sharing_numerator_opt: fee_sharing_numerator_opt,
        current_time_approximation: current_time_approximation,
        order_inputs: rest_inputs,
        all_outputs: rest_outs,
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

  let OrderDatum {
    refund_receiver,
    refund_receiver_datum,
    expiry_setting_opt,
    ..
  } = order_in_datum

  expect Some((expired_time, max_tip)) = expiry_setting_opt
  expect and {
      // the transaction must be created after expired time
      expired_time < start_valid_time_range,
      // the output have to paid back to sender
      refund_receiver == order_out_address,
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
        extra_order_datum: refund_receiver_datum,
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
