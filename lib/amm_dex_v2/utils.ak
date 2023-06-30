use aiken/builtin
use aiken/bytearray
use aiken/cbor
use aiken/list
use aiken/transaction/value.{AssetName, PolicyId, ada_asset_name, ada_policy_id}
use amm_dex_v2/types.{Asset}

const minus_ascii_code = 45

const zero_ascii_code = 48

pub fn int_to_bytearray(i: Int) -> ByteArray {
  if i < 0 {
    let negate_i = i * -1
    bytearray.push(int_to_bytearray(negate_i), minus_ascii_code)
  } else if builtin.quotient_integer(i, 10) == 0 {
    digit_to_bytearray(i)
  } else {
    bytearray.concat(
      int_to_bytearray(builtin.quotient_integer(i, 10)),
      digit_to_bytearray(builtin.remainder_integer(i, 10)),
    )
  }
}

test test_int_to_bytearray() {
  let arr =
    [-10, 0, 1, 10, 99]
  list.all(
    arr,
    fn(x) { int_to_bytearray(x) == bytearray.from_string(cbor.diagnostic(x)) },
  )
}

fn digit_to_bytearray(i: Int) -> ByteArray {
  let empty_byte_array = #""
  bytearray.push(empty_byte_array, i + zero_ascii_code)
}

test test_digit_to_bytearray() {
  let arr =
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  list.all(
    arr,
    fn(x) { digit_to_bytearray(x) == bytearray.from_string(cbor.diagnostic(x)) },
  )
}

pub fn sorted_asset(asset_a: Asset, asset_b: Asset) -> Bool {
  let Asset { policy_id: asset_a_policy_id, asset_name: asset_a_asset_name } =
    asset_a
  let Asset { policy_id: asset_b_policy_id, asset_name: asset_b_asset_name } =
    asset_b
  if asset_a_policy_id == asset_b_policy_id {
    builtin.less_than_bytearray(asset_a_asset_name, asset_b_asset_name)
  } else {
    builtin.less_than_bytearray(asset_a_policy_id, asset_b_policy_id)
  }
}

pub fn is_ada_asset(pid: PolicyId, name: AssetName) -> Bool {
  pid == ada_policy_id && name == ada_asset_name
}
