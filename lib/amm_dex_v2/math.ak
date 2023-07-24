use aiken/list
use aiken/math

pub fn calculate_sqrt(x: Int) -> Int {
  if x < 0 {
    error
  } else if x == 0 {
    0
  } else if x == 1 {
    1
  } else if x == 2 {
    1
  } else {
    do_calculate_sqrt(x, x, x / 2 + 1)
  }
}

fn do_calculate_sqrt(x: Int, i1: Int, i2: Int) -> Int {
  if i2 < i1 {
    do_calculate_sqrt(x, i2, ( x / i2 + i2 ) / 2)
  } else {
    i1
  }
}

test test_calculate_sqrt() {
  let arr =
    [(0, 0), (1, 1), (2, 1), (3, 1), (4, 2), (9, 3), (16, 4), (17, 4)]
  list.all(
    arr,
    fn(item) {
      let (a, b) = item
      calculate_sqrt(a) == b
    },
  )
}

pub fn calculate_initial_liquidity(out_a: Int, out_b: Int) -> Int {
  let p = out_a * out_b
  let sqrt = calculate_sqrt(p)
  if sqrt * sqrt < p {
    sqrt + 1
  } else {
    sqrt
  }
}

pub fn calculate_amount_out(
  reserve_in: Int,
  reserve_out: Int,
  amount_in: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
) -> Int {
  let diff = trading_fee_denominator - trading_fee_numerator
  let in_with_fee = diff * amount_in
  let numerator = in_with_fee * reserve_out
  let denominator = trading_fee_denominator * reserve_in + in_with_fee
  numerator / denominator
}

pub fn calculate_amount_in(
  reserve_in: Int,
  reserve_out: Int,
  amount_out: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
) -> Option<Int> {
  if amount_out >= reserve_out {
    None
  } else {
    let diff = trading_fee_denominator - trading_fee_numerator
    let numerator = reserve_in * amount_out * trading_fee_denominator
    let denominator = ( reserve_out - amount_out ) * diff
    let amount_in = numerator / denominator + 1
    Some(amount_in)
  }
}

// Calculate liquidity amount which will be minted for profit sharing
// The protocol will collect a percentage of trading fee
// Refer: https://uniswap.org/whitepaper.pdf (2.4 Protocol fee)
pub fn calculate_profit_sharing(
  root_k_last: Int,
  reserve_product: Int,
  total_liquidity: Int,
  fee_sharing_numerator: Int,
  fee_sharing_denominator: Int,
) -> Int {
  if root_k_last <= 0 {
    0
  } else {
    let root_k = calculate_sqrt(reserve_product)
    if root_k > root_k_last {
      let numerator =
        fee_sharing_numerator * total_liquidity * ( root_k - root_k_last )
      let denominator =
        ( fee_sharing_denominator - fee_sharing_numerator ) * root_k + fee_sharing_numerator * root_k_last
      let fee_sharing = numerator / denominator
      if fee_sharing > 0 {
        fee_sharing
      } else {
        0
      }
    } else {
      0
    }
  }
}

pub fn calculate_deposit_amount(
  amount_a: Int,
  amount_b: Int,
  reserve_a: Int,
  reserve_b: Int,
  total_liquidity: Int,
) -> Option<(Int, Int, Int)> {
  let delta_lp_a = amount_a * total_liquidity / reserve_a
  let delta_lp_b = amount_b * total_liquidity / reserve_b
  let (necessary_a, necessary_b) =
    if delta_lp_a > delta_lp_b {
      (amount_b * reserve_a / reserve_b, amount_b)
    } else if delta_lp_a < delta_lp_b {
      (amount_a, amount_a * reserve_b / reserve_a)
    } else {
      (amount_a, amount_b)
    }
  let delta_liquidity = math.min(delta_lp_a, delta_lp_b)
  if necessary_a > 0 && necessary_b > 0 && delta_liquidity > 0 {
    Some((necessary_a, necessary_b, delta_liquidity))
  } else {
    None
  }
}

pub fn calculate_withdraw(
  reserve_a: Int,
  reserve_b: Int,
  withdrawal_lp_amount: Int,
  total_liquidity: Int,
) -> (Int, Int) {
  let amount_a = withdrawal_lp_amount * reserve_a / total_liquidity
  let amount_b = withdrawal_lp_amount * reserve_b / total_liquidity
  (amount_a, amount_b)
}

// Calculate which amount will be swapped to supply enough amount for depositing
// Refer: https://blog.alphafinance.io/onesideduniswap/
pub fn calculate_zap_swap_amount(
  reserve_in: Int,
  amount_in: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
) -> Int {
  let temp_reserve_in =
    ( 2 * trading_fee_denominator - trading_fee_numerator ) * reserve_in
  let diff = trading_fee_denominator - trading_fee_numerator
  let numerator =
    calculate_sqrt(
      temp_reserve_in * temp_reserve_in + 4 * trading_fee_denominator * diff * reserve_in * amount_in,
    ) - temp_reserve_in
  let denominator = 2 * diff
  numerator / denominator
}
// Calculate which LP amount will be received after deposit @amount_in 
// Refer: https://blog.alphafinance.io/onesideduniswap/
// pub fn calculate_zap_in(
//   reserve_in: Int,
//   reserve_out: Int,
//   total_liquidity: Int,
//   amount_in: Int,
//   trading_fee_numerator: Int,
//   trading_fee_denominator: Int,
// ) -> Int {
//   let swap_amount_in =
//     calculate_zap_swap_amount(
//       reserve_in,
//       amount_in,
//       trading_fee_numerator,
//       trading_fee_denominator,
//     )
//   let swap_to_asset_out_amount =
//     calculate_amount_out(
//       reserve_in,
//       reserve_out,
//       swap_amount_in,
//       trading_fee_numerator,
//       trading_fee_denominator,
//     )
//   swap_to_asset_out_amount * total_liquidity / (
//     reserve_out - swap_to_asset_out_amount
//   )
// }
// pub fn calculate_zap_out(
//   reserve_a: Int,
//   reserve_b: Int,
//   total_liquidity: Int,
//   withdrawal_lp_amount: Int,
//   trading_fee_numerator: Int,
//   trading_fee_denominator: Int,
//   a_to_b_direction: Bool,
// ) -> Int {
//   let reserve_out =
//     if a_to_b_direction {
//       reserve_b
//     } else {
//       reserve_a
//     }
//   let numerator =
//     reserve_out * withdrawal_lp_amount * (
//       trading_fee_denominator * ( 2 * total_liquidity - withdrawal_lp_amount ) - trading_fee_numerator * total_liquidity
//     )
//   let denominator =
//     total_liquidity * (
//       trading_fee_denominator * total_liquidity - trading_fee_numerator * withdrawal_lp_amount
//     )
//   numerator / denominator
// }
// pub fn calculate_zap_out_1(
//   reserve_a: Int,
//   reserve_b: Int,
//   total_liquidity: Int,
//   withdrawal_lp_amount: Int,
//   trading_fee_numerator: Int,
//   trading_fee_denominator: Int,
//   a_to_b_direction: Bool,
// ) -> Int {
//   let (amount_a_out, amount_b_out) =
//     calculate_withdraw(
//       reserve_a: reserve_a,
//       reserve_b: reserve_b,
//       withdrawal_lp_amount: withdrawal_lp_amount,
//       total_liquidity: total_liquidity,
//     )
//   let new_reserve_a = reserve_a - amount_a_out
//   let new_reserve_b = reserve_b - amount_b_out

//   if a_to_b_direction {
//     let extra_out =
//       calculate_amount_out(
//         reserve_in: new_reserve_a,
//         reserve_out: new_reserve_b,
//         amount_in: amount_a_out,
//         trading_fee_numerator: trading_fee_numerator,
//         trading_fee_denominator: trading_fee_denominator,
//       )
//     amount_b_out + extra_out
//   } else {
//     let extra_out =
//       calculate_amount_out(
//         reserve_in: new_reserve_b,
//         reserve_out: new_reserve_a,
//         amount_in: amount_b_out,
//         trading_fee_numerator: trading_fee_numerator,
//         trading_fee_denominator: trading_fee_denominator,
//       )
//     amount_a_out + extra_out
//   }
// }
