use aiken/collection/list
use amm_dex_v2/utils

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
  let arr = [(0, 0), (1, 1), (2, 1), (3, 1), (4, 2), (9, 3), (16, 4), (17, 4)]
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

test test_calculate_initial_liquidity() {
  let data = [(1_000_000, 1_000_000, 1_000_000), (1_000, 1_000_000, 31_623)]
  list.all(
    data,
    fn(item) {
      let (a, b, lp) = item
      calculate_initial_liquidity(a, b) == lp
    },
  )
}

// Minswap Fee Sharing takes a proportion of the Trading Fee as Protocol Revenue. 
// This proportion is defined by the @fee_sharing_numerator_opt variable.
pub fn calculate_earned_fee_in_fraction(
  amount_in_numerator: Int,
  amount_in_denominator: Int,
  trading_fee_numerator: Int,
  fee_sharing_numerator_opt: Option<Int>,
) -> Int {
  when fee_sharing_numerator_opt is {
    None -> 0
    Some(fee_sharing_numerator) ->
      amount_in_numerator * trading_fee_numerator * fee_sharing_numerator / (
        amount_in_denominator * utils.default_fee_denominator * utils.default_fee_denominator
      )
  }
}

// Minswap Fee Sharing takes a proportion of the Trading Fee as Protocol Revenue. 
// This proportion is defined by the @fee_sharing_numerator_opt variable.
pub fn calculate_earned_fee_in(
  amount_in: Int,
  trading_fee_numerator: Int,
  fee_sharing_numerator_opt: Option<Int>,
) -> Int {
  when fee_sharing_numerator_opt is {
    None -> 0
    Some(fee_sharing_numerator) ->
      amount_in * trading_fee_numerator * fee_sharing_numerator / (
        utils.default_fee_denominator * utils.default_fee_denominator
      )
  }
}

test test_calculate_earned_fee_in() {
  let x =
    calculate_earned_fee_in(
      amount_in: 100000000,
      trading_fee_numerator: 30,
      fee_sharing_numerator_opt: Some(1666),
    ) == 49980
  let y =
    calculate_earned_fee_in_fraction(
      amount_in_numerator: 100000000,
      amount_in_denominator: 1,
      trading_fee_numerator: 30,
      fee_sharing_numerator_opt: Some(1666),
    ) == 49980
  x && y
}

// Calculate the amount that traders receive after swapping @amount_in. 
// Each swap incurs a Trading Fee based on the input amount.
// Refer to "formula.md", section "1. Swap Exact In" for the detailed formula.
pub fn calculate_amount_out(
  reserve_in: Int,
  reserve_out: Int,
  amount_in: Int,
  trading_fee_numerator: Int,
) -> Int {
  let diff = utils.default_fee_denominator - trading_fee_numerator
  let in_with_fee = diff * amount_in
  let numerator = in_with_fee * reserve_out
  let denominator = utils.default_fee_denominator * reserve_in + in_with_fee
  numerator / denominator
}

test test_calculate_amount_out() {
  let out =
    calculate_amount_out(
      reserve_in: 25434557769208,
      reserve_out: 413300185707175,
      amount_in: 1000000000,
      trading_fee_numerator: 30,
    )
  out == 16200168971
}

// Calculate the maximum amount that traders can swap to meet the expected rate between input and output. 
// Each swap incurs a Trading Fee based on the input amount. 
// Refer to "formula.md", section "7. Partial Swap" for the detailed formula.
pub fn calculate_max_in_swap(
  reserve_in: Int,
  reserve_out: Int,
  trading_fee_numerator: Int,
  io_ratio_numerator: Int,
  io_ratio_denominator: Int,
) -> Int {
  let diff = utils.default_fee_denominator - trading_fee_numerator
  let numerator =
    io_ratio_numerator * diff * reserve_out - io_ratio_denominator * utils.default_fee_denominator * reserve_in
  let denominator = io_ratio_denominator * diff
  let max_in_swap = numerator / denominator
  expect max_in_swap > 0
  max_in_swap
}

test test_calculate_max_in_swap() {
  let max_swap_amount =
    calculate_max_in_swap(
      reserve_in: 1_000_000_000,
      reserve_out: 1_000_000_000,
      trading_fee_numerator: 30,
      io_ratio_numerator: 10,
      io_ratio_denominator: 9,
    )
  max_swap_amount == 108102084
}

// Calculate the amount that traders need to swap to receive the exact @amount_out. 
// Each swap incurs a Trading Fee based on the input amount. 
// Refer to "formula.md", section "2. Swap Exact Out" for the detailed formula.
pub fn calculate_amount_in(
  reserve_in: Int,
  reserve_out: Int,
  amount_out: Int,
  trading_fee_numerator: Int,
) -> Int {
  expect amount_out < reserve_out
  let diff = utils.default_fee_denominator - trading_fee_numerator
  let numerator = reserve_in * amount_out * utils.default_fee_denominator
  let denominator = ( reserve_out - amount_out ) * diff
  numerator / denominator + 1
}

test test_calculate_amount_in() {
  let amount_in = calculate_amount_in(1_000_000_000, 1_000_000_000, 1_000, 30)
  amount_in == 1004
}

// According to the constant product formula, depositing to the Liquidity Pool requires that the supplied amount of two tokens be equal to the ratio of the Pool's reserves. 
// To accommodate both the Zap (depositing with a ratio of 1:0) and depositing with a custom ratio of two tokens, a portion of token A needs to be swapped for token B, and vice versa. 
// Here is the final formula to calculate the necessary swap amount during the deposit:
//    swap_amount ^ 2 * ( 1 - f ) * ( amount_out + reserve_out )
//      + swap_amount * ( 2 - f ) * reserve_in * ( amount_out + reserve_out )
//      + ( reserve_in ^ 2 * amount_out - reserve_in * reserve_out * amount_in )
//    = 0
// Refer to "formula.md", section "3. Deposit" for the detailed formula.
// The formula is inspired by Alpha Finance: https://blog.alphaventuredao.io/onesideduniswap/
pub fn calculate_deposit_swap_amount(
  amount_in: Int,
  amount_out: Int,
  reserve_in: Int,
  reserve_out: Int,
  trading_fee_numerator: Int,
) -> (Int, Int) {
  let x = ( amount_out + reserve_out ) * reserve_in
  let y =
    4 * ( amount_out + reserve_out ) * (
      amount_out * calculate_pow(reserve_in) - amount_in * reserve_in * reserve_out
    )
  let z = 2 * ( amount_out + reserve_out )
  let b = ( 2 * utils.default_fee_denominator - trading_fee_numerator ) * x
  let a =
    calculate_pow(b) - y * utils.default_fee_denominator * (
      utils.default_fee_denominator - trading_fee_numerator
    )
  let numerator = calculate_sqrt(a) - b
  let denominator =
    z * ( utils.default_fee_denominator - trading_fee_numerator )
  (numerator, denominator)
}

test test_calculate_deposit_swap_amount() {
  let result =
    calculate_deposit_swap_amount(
      amount_in: 5000,
      amount_out: 2000,
      reserve_in: 1_000_000,
      reserve_out: 1_000_000,
      trading_fee_numerator: 30,
    )
  result == (29932544594688, 19979880000)
}

// Calculate LP Token that Liquidity Providers receives after supplying @amount_a and @amount_b
pub fn calculate_deposit_amount(
  amount_a: Int,
  amount_b: Int,
  reserve_a: Int,
  reserve_b: Int,
  total_liquidity: Int,
  trading_fee_a_numerator: Int,
  trading_fee_b_numerator: Int,
  fee_sharing_numerator_opt: Option<Int>,
) -> (Int, Int, Int) {
  let ratio_a = amount_a * total_liquidity / reserve_a
  let ratio_b = amount_b * total_liquidity / reserve_b
  if ratio_a > ratio_b {
    // swap a part of A to B
    let (swap_amount_a_numerator, swap_amount_a_denominator) =
      calculate_deposit_swap_amount(
        amount_in: amount_a,
        amount_out: amount_b,
        reserve_in: reserve_a,
        reserve_out: reserve_b,
        trading_fee_numerator: trading_fee_a_numerator,
      )
    let earned_fee_a =
      calculate_earned_fee_in_fraction(
        amount_in_numerator: swap_amount_a_numerator,
        amount_in_denominator: swap_amount_a_denominator,
        trading_fee_numerator: trading_fee_a_numerator,
        fee_sharing_numerator_opt: fee_sharing_numerator_opt,
      )
    let lp_amount =
      ( amount_a * swap_amount_a_denominator - swap_amount_a_numerator ) * total_liquidity / (
        reserve_a * swap_amount_a_denominator + swap_amount_a_numerator
      )
    (earned_fee_a, 0, lp_amount)
  } else if ratio_a < ratio_b {
    // swap a part of B to A
    let (swap_amount_b_numerator, swap_amount_b_denominator) =
      calculate_deposit_swap_amount(
        amount_in: amount_b,
        amount_out: amount_a,
        reserve_in: reserve_b,
        reserve_out: reserve_a,
        trading_fee_numerator: trading_fee_b_numerator,
      )
    let earned_fee_b =
      calculate_earned_fee_in_fraction(
        amount_in_numerator: swap_amount_b_numerator,
        amount_in_denominator: swap_amount_b_denominator,
        trading_fee_numerator: trading_fee_b_numerator,
        fee_sharing_numerator_opt: fee_sharing_numerator_opt,
      )
    let lp_amount =
      ( amount_b * swap_amount_b_denominator - swap_amount_b_numerator ) * total_liquidity / (
        reserve_b * swap_amount_b_denominator + swap_amount_b_numerator
      )
    (0, earned_fee_b, lp_amount)
  } else {
    (0, 0, ratio_a)
  }
}

test test_calculate_deposit_amount() {
  //swap amount is(29932544594688 / 19979880000) ~ 1498
  let result1 =
    calculate_deposit_amount(
      amount_a: 5000,
      amount_b: 2000,
      reserve_a: 1_000_000,
      reserve_b: 1_000_000,
      total_liquidity: 1_000_000,
      trading_fee_a_numerator: 30,
      trading_fee_b_numerator: 100,
      fee_sharing_numerator_opt: Some(5000),
    )
  // swap amount is 29826937927508 / 19839600000 ~ 1503
  let result2 =
    calculate_deposit_amount(
      amount_a: 2000,
      amount_b: 5000,
      reserve_a: 1_000_000,
      reserve_b: 1_000_000,
      total_liquidity: 1_000_000,
      trading_fee_a_numerator: 30,
      trading_fee_b_numerator: 100,
      fee_sharing_numerator_opt: Some(5000),
    )
  result1 == (2, 0, 3496) && result2 == (0, 7, 3491)
}

// Calculate amount of Token A and Token B after Liquidity Providers withdraw @withdrawal_lp_amount of LP Token
// Refer to "formula.md", section "4. Withdraw" for the detailed formula.
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

test test_calculate_withdraw() {
  let result =
    calculate_withdraw(
      reserve_a: 1_000_000,
      reserve_b: 213_231_211,
      withdrawal_lp_amount: 123_456,
      total_liquidity: 12_345_678,
    )
  result == (9999, 2132298)
}

// Determine the quantity of Token A or Token B remaining after Liquidity Providers withdraw @withdrawal_lp_amount of LP Tokens. 
// Following the withdrawal, one of the Tokens is exchanged for the other. 
// For detailed calculation, please refer to "formula.md", section "4. Zap Out".
pub fn calculate_zap_out(
  withdrawal_lp_amount: Int,
  reserve_a: Int,
  reserve_b: Int,
  total_liquidity: Int,
  a_to_b_direction: Bool,
  trading_fee_a_numerator: Int,
  trading_fee_b_numerator: Int,
  fee_sharing_numerator_opt: Option<Int>,
) -> (Int, Int, Int) {
  let (withdrawal_asset_a_amount, withdrawal_asset_b_amount) =
    calculate_withdraw(
      reserve_a: reserve_a,
      reserve_b: reserve_b,
      withdrawal_lp_amount: withdrawal_lp_amount,
      total_liquidity: total_liquidity,
    )
  let reserve_a_after_withdraw = reserve_a - withdrawal_asset_a_amount
  let reserve_b_after_withdraw = reserve_b - withdrawal_asset_b_amount
  if a_to_b_direction {
    let extra_amount_out =
      calculate_amount_out(
        reserve_in: reserve_a_after_withdraw,
        reserve_out: reserve_b_after_withdraw,
        amount_in: withdrawal_asset_a_amount,
        trading_fee_numerator: trading_fee_a_numerator,
      )
    let earned_fee_a =
      calculate_earned_fee_in(
        amount_in: withdrawal_asset_a_amount,
        trading_fee_numerator: trading_fee_a_numerator,
        fee_sharing_numerator_opt: fee_sharing_numerator_opt,
      )
    (earned_fee_a, 0, withdrawal_asset_b_amount + extra_amount_out)
  } else {
    let extra_amount_out =
      calculate_amount_out(
        reserve_in: reserve_b_after_withdraw,
        reserve_out: reserve_a_after_withdraw,
        amount_in: withdrawal_asset_b_amount,
        trading_fee_numerator: trading_fee_b_numerator,
      )
    let earned_fee_b =
      calculate_earned_fee_in(
        amount_in: withdrawal_asset_b_amount,
        trading_fee_numerator: trading_fee_b_numerator,
        fee_sharing_numerator_opt: fee_sharing_numerator_opt,
      )
    (0, earned_fee_b, withdrawal_asset_a_amount + extra_amount_out)
  }
}

test test_calculate_zap_out() {
  // amount out (9999, 2132298)
  // 9999 A -> 2104508 B
  let result1 =
    calculate_zap_out(
      reserve_a: 1_000_000,
      reserve_b: 213_231_211,
      withdrawal_lp_amount: 123_456,
      total_liquidity: 12_345_678,
      a_to_b_direction: True,
      trading_fee_a_numerator: 30,
      trading_fee_b_numerator: 100,
      fee_sharing_numerator_opt: Some(5000),
    )
  // amount out (9999, 2132298)
  // 2132298 B ->9801 A
  let result2 =
    calculate_zap_out(
      reserve_a: 1_000_000,
      reserve_b: 213_231_211,
      withdrawal_lp_amount: 123_456,
      total_liquidity: 12_345_678,
      a_to_b_direction: False,
      trading_fee_a_numerator: 30,
      trading_fee_b_numerator: 100,
      fee_sharing_numerator_opt: Some(5000),
    )
  result1 == (14, 0, 4236806) && result2 == (0, 10661, 19800)
}

// According to the constant product formula, withdrawing from the Liquidity Pool requires that the withdrawal amount of two tokens be equal to the ratio of the Pool's reserves. 
// To satisfy the expected ratio between Token A and Token B after withdrawal, a portion of token A needs to be swapped for token B, and vice versa. 
// Here is the final formula to calculate the necessary swap amount during the withdrawal:
//    ( amount_in - swap_amount_in) / (amount_out + receive_amount_out) = expect_io_ratio_numerator / expect_io_ratio_denominator (1)
//    receive_amount_out = fee_diff * swap_amount_in * reserve_out / (fee_denominator * reserve_in + fee_diff * swap_amount_in) (2)
//    (1) & (2) =>>>>>
//    a * swap_amount_in ^ 2 + b * swap_amount_in + c = 0
//    Where:
//    - a = fee_diff * expect_io_ratio_denominator
//    - b = expect_io_ratio_numerator * fee_diff ( reserve_out + amount_out ) + expect_io_ratio_denominator * (fee_denominator * reserve_in - fee_diff * amount_in)
//    - c = fee_denominator * reserve_in * (expect_io_ratio_numerator * amount_out - expect_io_ratio_denominator * amount_in) 
// Refer to "formula.md", section "6. Withdraw Imbalance" for the detailed formula.
fn calculate_withdraw_swap_amount(
  amount_in: Int,
  amount_out: Int,
  reserve_in: Int,
  reserve_out: Int,
  expect_io_ratio_numerator: Int,
  expect_io_ratio_denominator: Int,
  trading_fee_numerator: Int,
) -> Int {
  let diff = utils.default_fee_denominator - trading_fee_numerator
  let a = expect_io_ratio_denominator * diff
  let b =
    expect_io_ratio_numerator * diff * ( reserve_out + amount_out ) + expect_io_ratio_denominator * (
      reserve_in * utils.default_fee_denominator - diff * amount_in
    )
  let c =
    utils.default_fee_denominator * reserve_in * (
      expect_io_ratio_numerator * amount_out - expect_io_ratio_denominator * amount_in
    )
  // a*x^2+b*x+c=0
  // delta = b^2 - 4ac
  // x = (-b +sqrt(delta))/(2*a) or (-b - sqrt(delta))/(2*a)
  let delta = b * b - 4 * a * c
  ( calculate_sqrt(delta) - b ) / ( 2 * a )
}

test test_calculate_withdraw_swap_amount() {
  let swap_amount =
    calculate_withdraw_swap_amount(
      amount_in: 1_000,
      amount_out: 1_000,
      reserve_in: 1_000_000,
      reserve_out: 1_000_000,
      expect_io_ratio_numerator: 2,
      expect_io_ratio_denominator: 3,
      trading_fee_numerator: 30,
    )
  swap_amount == 200
}

// return earning fee(a,b)+ amount out(a,b)
pub fn calculate_withdraw_imbalance(
  expect_ab_ratio_numerator: Int,
  expect_ab_ratio_denominator: Int,
  reserve_a: Int,
  reserve_b: Int,
  trading_fee_a_numerator: Int,
  trading_fee_b_numerator: Int,
  withdrawal_lp_amount: Int,
  total_liquidity: Int,
  fee_sharing_numerator_opt: Option<Int>,
) -> (Int, Int, Int, Int) {
  let (withdrawal_asset_a_amount, withdrawal_asset_b_amount) =
    calculate_withdraw(
      reserve_a: reserve_a,
      reserve_b: reserve_b,
      withdrawal_lp_amount: withdrawal_lp_amount,
      total_liquidity: total_liquidity,
    )
  let reserve_a_after_withdraw = reserve_a - withdrawal_asset_a_amount
  let reserve_b_after_withdraw = reserve_b - withdrawal_asset_b_amount
  let ratio_a = withdrawal_asset_a_amount * expect_ab_ratio_denominator
  let ratio_b = withdrawal_asset_b_amount * expect_ab_ratio_numerator
  if ratio_a > ratio_b {
    // swap a-> b
    let swap_amount_a =
      calculate_withdraw_swap_amount(
        amount_in: withdrawal_asset_a_amount,
        amount_out: withdrawal_asset_b_amount,
        reserve_in: reserve_a_after_withdraw,
        reserve_out: reserve_b_after_withdraw,
        expect_io_ratio_numerator: expect_ab_ratio_numerator,
        expect_io_ratio_denominator: expect_ab_ratio_denominator,
        trading_fee_numerator: trading_fee_a_numerator,
      )

    let receive_amount_b =
      calculate_amount_out(
        reserve_in: reserve_a_after_withdraw,
        reserve_out: reserve_b_after_withdraw,
        amount_in: swap_amount_a,
        trading_fee_numerator: trading_fee_a_numerator,
      )
    let earned_fee_a =
      calculate_earned_fee_in(
        amount_in: swap_amount_a,
        trading_fee_numerator: trading_fee_a_numerator,
        fee_sharing_numerator_opt: fee_sharing_numerator_opt,
      )
    (
      earned_fee_a,
      0,
      withdrawal_asset_a_amount - swap_amount_a,
      withdrawal_asset_b_amount + receive_amount_b,
    )
  } else if ratio_a < ratio_b {
    // swap b-> a
    let swap_amount_b =
      calculate_withdraw_swap_amount(
        amount_in: withdrawal_asset_b_amount,
        amount_out: withdrawal_asset_a_amount,
        reserve_in: reserve_b_after_withdraw,
        reserve_out: reserve_a_after_withdraw,
        expect_io_ratio_numerator: expect_ab_ratio_denominator,
        expect_io_ratio_denominator: expect_ab_ratio_numerator,
        trading_fee_numerator: trading_fee_b_numerator,
      )

    let receive_amount_a =
      calculate_amount_out(
        reserve_in: reserve_b_after_withdraw,
        reserve_out: reserve_a_after_withdraw,
        amount_in: swap_amount_b,
        trading_fee_numerator: trading_fee_b_numerator,
      )
    let earned_fee_b =
      calculate_earned_fee_in(
        amount_in: swap_amount_b,
        trading_fee_numerator: trading_fee_b_numerator,
        fee_sharing_numerator_opt: fee_sharing_numerator_opt,
      )
    (
      0,
      earned_fee_b,
      withdrawal_asset_a_amount + receive_amount_a,
      withdrawal_asset_b_amount - swap_amount_b,
    )
  } else {
    (0, 0, withdrawal_asset_a_amount, withdrawal_asset_b_amount)
  }
}

test test_calculate_withdraw_imbalance() {
  // swap amount is 2004
  let result1 =
    calculate_withdraw_imbalance(
      expect_ab_ratio_numerator: 2,
      expect_ab_ratio_denominator: 3,
      reserve_a: 1_000_000,
      reserve_b: 1_000_000,
      trading_fee_a_numerator: 30,
      trading_fee_b_numerator: 100,
      withdrawal_lp_amount: 10_000,
      total_liquidity: 1_000_000,
      fee_sharing_numerator_opt: Some(5000),
    )
  let result2 =
    calculate_withdraw_imbalance(
      expect_ab_ratio_numerator: 2,
      expect_ab_ratio_denominator: 3,
      reserve_a: 1_000_000,
      reserve_b: 1_000_000,
      trading_fee_a_numerator: 100,
      trading_fee_b_numerator: 30,
      withdrawal_lp_amount: 10_000,
      total_liquidity: 1_000_000,
      fee_sharing_numerator_opt: Some(5000),
    )
  result1 == (3, 0, 7996, 11993) && result2 == (10, 0, 7991, 11984)
}
