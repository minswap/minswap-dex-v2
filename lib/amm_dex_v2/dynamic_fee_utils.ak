use amm_dex_v2/math

pub fn taylor_exponent(scalar: Int, numerator: Int, denominator: Int) -> Int {
  math.max_int(
    0,
    scalar + scalar * numerator / denominator + scalar * numerator * numerator / (
      2 * denominator * denominator
    ) + scalar * numerator * numerator * numerator / (
      6 * denominator * denominator * denominator
    ),
  )
}

pub fn ewm_integer(
  current_val: Int,
  previous_avg: Int,
  delta: Int,
  lam: Int,
) -> Int {
  let scalar = 1000000
  let w = taylor_exponent(scalar, -delta, lam)
  ( previous_avg * w + current_val * ( scalar - w ) ) / scalar
}

pub fn calculate_valatility(
  pre_price_avg: Int,
  pre_price_sqr_avg: Int,
  pre_block_time: Int,
  numerator: Int,
  denominator: Int,
  block_time: Int,
  decay: Int,
) -> (Int, Int) {
  let price = 1000000 * numerator / denominator
  let delta = block_time - pre_block_time
  let price_avg =
    ewm_integer(
      current_val: price,
      previous_avg: pre_price_avg,
      delta: delta,
      lam: decay,
    )
  let price_sqr_avg =
    ewm_integer(
      current_val: price * price,
      previous_avg: pre_price_sqr_avg,
      delta: delta,
      lam: decay,
    )
  (price_avg, price_sqr_avg)
}
