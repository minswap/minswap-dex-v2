use aiken/list

pub fn calculate_sqrt(x: Int) -> Int {
  if x < 0 {
    fail
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

pub fn calculate_pow(x: Int) -> Int {
  x * x
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

pub fn calculate_amount_out_fraction(
  reserve_in: Int,
  reserve_out: Int,
  amount_in_numerator: Int,
  amount_in_denominator: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
) -> (Int, Int) {
  let diff = trading_fee_denominator - trading_fee_numerator
  let numerator = amount_in_numerator * diff * reserve_out
  let denominator =
    trading_fee_denominator * amount_in_denominator * reserve_in + amount_in_numerator * diff
  (numerator, denominator)
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

// Calculate which amount will be swapped to supply enough amount for depositing
// Refer: https://blog.alphafinance.io/onesideduniswap/
// Final formular:
//    swap_amount ^ 2 * ( 1 - f ) * ( amount_out + reserve_out )
//      + swap_amount * ( 2 - f ) * reserve_in * ( amount_out + reserve_out )
//      + ( reserve_in ^ 2 * amount_out + reserve_in * reserve_out * amount_out )
//    = 0
pub fn calculate_swap_amount(
  amount_in: Int,
  amount_out: Int,
  reserve_in: Int,
  reserve_out: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
) -> (Int, Int) {
  let x = ( amount_out + reserve_out ) * reserve_in
  let y =
    4 * ( amount_out + reserve_out ) * (
      amount_out * calculate_pow(reserve_in) - amount_in * reserve_in * reserve_out
    )
  let z = 2 * ( amount_out + reserve_out )
  let b = ( 2 * trading_fee_denominator - trading_fee_numerator ) * x
  let a =
    calculate_pow(b) - y * trading_fee_denominator * (
      trading_fee_denominator - trading_fee_numerator
    )
  let numerator = calculate_sqrt(a) - b
  let denominator = z * ( trading_fee_denominator - trading_fee_numerator )
  (numerator, denominator)
}

pub fn calculate_deposit_amount(
  amount_a: Int,
  amount_b: Int,
  reserve_a: Int,
  reserve_b: Int,
  total_liquidity: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
) -> (Int, Int) {
  let ratio_a = amount_a * total_liquidity / reserve_a
  let ratio_b = amount_b * total_liquidity / reserve_b
  if ratio_a > ratio_b {
    // swap a part of A to B
    let (swap_amount_a_numerator, swap_amount_a_denominator) =
      calculate_swap_amount(
        amount_in: amount_a,
        amount_out: amount_b,
        reserve_in: reserve_a,
        reserve_out: reserve_b,
        trading_fee_numerator: trading_fee_numerator,
        trading_fee_denominator: trading_fee_denominator,
      )
    let (receive_amount_b_numerator, receive_amount_b_denominator) =
      calculate_amount_out_fraction(
        reserve_in: reserve_a,
        reserve_out: reserve_b,
        amount_in_numerator: swap_amount_a_numerator,
        amount_in_denominator: swap_amount_a_denominator,
        trading_fee_numerator: trading_fee_numerator,
        trading_fee_denominator: trading_fee_denominator,
      )
    // TODO: should +1?
    let reserve_product_after_swap =
      ( reserve_a * swap_amount_a_denominator + swap_amount_a_numerator ) * (
        reserve_b * receive_amount_b_denominator - receive_amount_b_numerator
      ) / ( swap_amount_a_denominator * receive_amount_b_denominator ) + 1
    let lp_amount =
      ( amount_b * receive_amount_b_denominator + receive_amount_b_numerator ) * total_liquidity / (
        reserve_b * receive_amount_b_denominator - receive_amount_b_numerator
      )
    (reserve_product_after_swap, lp_amount)
  } else if ratio_a < ratio_b {
    // swap a part of B to A
    let (swap_amount_b_numerator, swap_amount_b_denominator) =
      calculate_swap_amount(
        amount_in: amount_b,
        amount_out: amount_a,
        reserve_in: reserve_b,
        reserve_out: reserve_a,
        trading_fee_numerator: trading_fee_numerator,
        trading_fee_denominator: trading_fee_denominator,
      )
    let (receive_amount_a_numerator, receive_amount_a_denominator) =
      calculate_amount_out_fraction(
        reserve_in: reserve_b,
        reserve_out: reserve_a,
        amount_in_numerator: swap_amount_b_numerator,
        amount_in_denominator: swap_amount_b_denominator,
        trading_fee_numerator: trading_fee_numerator,
        trading_fee_denominator: trading_fee_denominator,
      )
    let reserve_product_after_swap =
      ( reserve_b * swap_amount_b_denominator + swap_amount_b_numerator ) * (
        reserve_a * receive_amount_a_denominator - receive_amount_a_numerator
      ) / ( swap_amount_b_denominator * receive_amount_a_denominator ) + 1
    let lp_amount =
      ( amount_a * receive_amount_a_denominator + receive_amount_a_numerator ) * total_liquidity / (
        reserve_a * receive_amount_a_denominator - receive_amount_a_numerator
      )
    (reserve_product_after_swap, lp_amount)
  } else {
    (reserve_a * reserve_b, ratio_a)
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

pub fn calculate_zap_out(
  withdrawal_lp_amount: Int,
  reserve_a: Int,
  reserve_b: Int,
  total_liquidity: Int,
  a_to_b_direction: Bool,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
) -> (Int, Int) {
  let (withdrawal_asset_a_amount, withdrawal_asset_b_amount) =
    calculate_withdraw(
      reserve_a: reserve_a,
      reserve_b: reserve_b,
      withdrawal_lp_amount: withdrawal_lp_amount,
      total_liquidity: total_liquidity,
    )
  let reserve_a_after_withdraw = reserve_a - withdrawal_asset_a_amount
  let reserve_b_after_withdraw = reserve_b - withdrawal_asset_b_amount
  let amount_out =
    if a_to_b_direction {
      let extra_amount_out =
        calculate_amount_out(
          reserve_in: reserve_a_after_withdraw,
          reserve_out: reserve_b_after_withdraw,
          amount_in: withdrawal_asset_a_amount,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
        )
      withdrawal_asset_b_amount + extra_amount_out
    } else {
      let extra_amount_out =
        calculate_amount_out(
          reserve_in: reserve_b_after_withdraw,
          reserve_out: reserve_a_after_withdraw,
          amount_in: withdrawal_asset_b_amount,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
        )
      withdrawal_asset_a_amount + extra_amount_out
    }
  (reserve_a_after_withdraw * reserve_b_after_withdraw, amount_out)
}
