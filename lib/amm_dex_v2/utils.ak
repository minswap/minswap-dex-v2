use aiken/builtin
use aiken/bytearray
use aiken/cbor
use aiken/dict
use aiken/hash
use aiken/list
use aiken/string
use aiken/transaction.{Datum, DatumHash, InlineDatum, NoDatum}
use aiken/transaction/value.{
  AssetName, PolicyId, Value, ada_asset_name, ada_policy_id,
}
use amm_dex_v2/types.{Asset, DatumMap, FactoryDatum, OrderDatum, PoolDatum}

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

pub fn verify_pool_datum_in_batch(
  datum1: PoolDatum,
  datum2: PoolDatum,
  require_total_liquidity_unchange: Bool,
) -> Bool {
  let PoolDatum {
    asset_a: datum_1_asset_a,
    asset_b: datum_1_asset_b,
    total_liquidity: datum_1_total_liquidity,
    trading_fee_numerator: datum_1_trading_fee_numerator,
    trading_fee_denominator: datum_1_trading_fee_denominator,
    order_hash: datum_1_order_hash,
    profit_sharing_opt: datum_1_profit_sharing_opt,
    ..
  } = datum1

  let PoolDatum {
    asset_a: datum_2_asset_a,
    asset_b: datum_2_asset_b,
    total_liquidity: datum_2_total_liquidity,
    trading_fee_numerator: datum_2_trading_fee_numerator,
    trading_fee_denominator: datum_2_trading_fee_denominator,
    order_hash: datum_2_order_hash,
    profit_sharing_opt: datum_2_profit_sharing_opt,
    ..
  } = datum2
  expect
    if require_total_liquidity_unchange {
      datum_1_total_liquidity == datum_2_total_liquidity
    } else {
      True
    }
  datum_1_asset_a == datum_2_asset_a && // hehe
  datum_1_asset_b == datum_2_asset_b && // hehe
  datum_1_trading_fee_numerator == datum_2_trading_fee_numerator && // hehe
  datum_1_trading_fee_denominator == datum_2_trading_fee_denominator && // hehe
  datum_1_order_hash == datum_2_order_hash && // hehe
  datum_1_profit_sharing_opt == datum_2_profit_sharing_opt
  // hehe
}

pub fn compute_lp_asset_name(
  asset_a_policy_id: PolicyId,
  asset_a_asset_name: AssetName,
  asset_b_policy_id: PolicyId,
  asset_b_asset_name: AssetName,
) -> AssetName {
  let asset_a_ident =
    hash.sha3_256(bytearray.concat(asset_a_policy_id, asset_a_asset_name))
  let asset_b_ident =
    hash.sha3_256(bytearray.concat(asset_b_policy_id, asset_b_asset_name))
  let pair_ident = bytearray.concat(asset_a_ident, asset_b_ident)
  hash.sha3_256(pair_ident)
}

test test_compute_lp_asset_name() {
  let asset_a_policy_id = #""
  let asset_a_asset_name = #""
  let asset_b_policy_id =
    #"29d222ce763455e3d7a09a665ce554f00ac89d2e99a1a83d267170c6"
  let asset_b_asset_name = #"4d494e"
  let lp_asset_name =
    compute_lp_asset_name(
      asset_a_policy_id,
      asset_a_asset_name,
      asset_b_policy_id,
      asset_b_asset_name,
    )
  lp_asset_name == #"82e2b1fd27a7712a1a9cf750dfbea1a5778611b20e06dd6a611df7a643f8cb75"
}

pub fn must_parse_option(op: Option<a>) -> a {
  expect Some(t) = op
  t
}

pub fn bytearray_to_int(byte_arr: ByteArray) -> Int {
  let byte_len = bytearray.length(byte_arr)
  do_bytearray_to_int(byte_arr, 0, 0, byte_len)
}

pub fn do_bytearray_to_int(
  byte_arr: ByteArray,
  idx: Int,
  acc: Int,
  byte_len: Int,
) -> Int {
  if idx == byte_len {
    acc
  } else {
    let byte = builtin.index_bytearray(byte_arr, idx)
    if idx == 0 && byte == minus_ascii_code {
      do_bytearray_to_int(byte_arr, idx + 1, acc, byte_len) * -1
    } else if byte < zero_ascii_code || byte < zero_ascii_code || byte > zero_ascii_code + 9 {
      fail
    } else {
      do_bytearray_to_int(
        byte_arr,
        idx + 1,
        acc * 10 + ( byte - zero_ascii_code ),
        byte_len,
      )
    }
  }
}

test test_bytearray_to_int() {
  let r1 = bytearray_to_int(string.to_bytearray(@"123"))
  let r2 = bytearray_to_int(string.to_bytearray(@"111"))
  r1 == 123 && r2 == 111
}

pub fn find_script_datum(datums: DatumMap, datum: Datum) -> Option<Data> {
  when datum is {
    NoDatum -> None
    DatumHash(dh) ->
      datums
        |> dict.get(dh)
    InlineDatum(dat) -> Some(dat)
  }
}

pub fn must_find_script_datum(datums: DatumMap, datum: Datum) -> Data {
  let datum_opt = find_script_datum(datums, datum)
  must_parse_option(datum_opt)
}

pub fn must_find_order_datum(datums: DatumMap, datum: Datum) -> OrderDatum {
  expect order_datum: OrderDatum = must_find_script_datum(datums, datum)
  order_datum
}

pub fn must_find_pool_datum(datums: DatumMap, datum: Datum) -> PoolDatum {
  expect pool_datum: PoolDatum = must_find_script_datum(datums, datum)
  pool_datum
}

pub fn must_find_factory_datum(datums: DatumMap, datum: Datum) -> FactoryDatum {
  expect factory_datum: FactoryDatum = must_find_script_datum(datums, datum)
  factory_datum
}

pub fn list_at_index(outputs: List<a>, payout_outputs_offset: Int) -> a {
  if payout_outputs_offset >= 10 {
    outputs
      |> skip_10_items
      |> list_at_index(payout_outputs_offset - 10)
  } else {
    list_at_index_step(outputs, payout_outputs_offset)
  }
}

fn list_at_index_step(outputs: List<a>, current_index: Int) -> a {
  if current_index <= 0 {
    expect [output, ..] = outputs
    output
  } else {
    outputs
      |> builtin.tail_list
      |> list_at_index_step(current_index - 1)
  }
}

/// Small utility to skip 10 items in a list.
/// Used by `list_at_index`.
pub fn skip_10_items(some_list: List<a>) -> List<a> {
  some_list
    |> builtin.tail_list
    |> builtin.tail_list
    |> builtin.tail_list
    |> builtin.tail_list
    |> builtin.tail_list
    |> builtin.tail_list
    |> builtin.tail_list
    |> builtin.tail_list
    |> builtin.tail_list
    |> builtin.tail_list
}

test test_list_at_index() {
  let arr =
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
  expect list_at_index(arr, 0) == 0
  expect list_at_index(arr, 1) == 1
  expect list_at_index(arr, 2) == 2
  expect list_at_index(arr, 3) == 3
  expect list_at_index(arr, 4) == 4
  expect list_at_index(arr, 5) == 5
  expect list_at_index(arr, 6) == 6
  expect list_at_index(arr, 7) == 7
  expect list_at_index(arr, 8) == 8
  expect list_at_index(arr, 9) == 9
  expect list_at_index(arr, 10) == 10
  expect list_at_index(arr, 11) == 11
  True
}

pub fn zip_with(
  arr1: List<a>,
  arr2: List<b>,
  predicate: fn(a, b) -> result,
) -> List<result> {
  when arr1 is {
    [] ->
      when arr2 is {
        [] ->
          []
        _ -> fail
      }
    [x, ..xs] ->
      when arr2 is {
        [] ->
          []
        [y, ..ys] ->
          [predicate(x, y), ..zip_with(xs, ys, predicate)]
      }
  }
}

test test_zip_with() {
  let arr1 =
    [1, 2, 3]
  let arr2 =
    [4, 5, 6]
  let z1 = zip_with(arr1, arr2, fn(a1, a2) { a1 + a2 })
  let z2 = zip_with(arr1, arr2, fn(a1, a2) { a1 * a2 })
  z1 == [5, 7, 9] && z2 == [4, 10, 18]
}

test test_zip_with_throw_err() fail {
  let arr1 =
    [1, 2, 3]
  let arr2 =
    [4, 5, 6, 6]
  zip_with(arr1, arr2, fn(a1, a2) { a1 + a2 }) == []
}

test test_validate_pool_value_1() {
  let authen_policy_id =
    #"fd7df11942fcd168a93620d88fc53a4336c48e0f799e73263b7d5660"
  let pool_auth_asset_name = #"4d5350"
  let lp_asset_name =
    #"31d0e583e0998ce44b2837f491edbf3d895973c136869a9e912d1d1a7a36568b"
  let asset_a_policy_id = #""
  let asset_a_asset_name = #""
  let asset_b_policy_id =
    #"782c158a98aed3aa676d9c85117525dcf3acc5506a30a8d87369fbcb"
  let asset_b_asset_name = #"4d6f6e6574"
  let pool_value =
    value.zero()
      |> value.add(authen_policy_id, pool_auth_asset_name, 1)
      |> value.add(authen_policy_id, lp_asset_name, 10000)
      |> value.add(asset_a_policy_id, asset_a_asset_name, 100000)
      |> value.add(asset_b_policy_id, asset_b_asset_name, 100000)
  validate_pool_value(
    val: pool_value,
    authen_policy_id: authen_policy_id,
    pool_auth_asset_name: pool_auth_asset_name,
    lp_asset_name: lp_asset_name,
    asset_a_policy_id: asset_a_policy_id,
    asset_a_asset_name: asset_a_asset_name,
    asset_b_policy_id: asset_b_policy_id,
    asset_b_asset_name: asset_b_asset_name,
  )
}

test test_validate_pool_value_2() {
  let authen_policy_id =
    #"fd7df11942fcd168a93620d88fc53a4336c48e0f799e73263b7d5660"
  let pool_auth_asset_name = #"4d5350"
  let lp_asset_name =
    #"31d0e583e0998ce44b2837f491edbf3d895973c136869a9e912d1d1a7a36568b"
  let asset_a_policy_id =
    #"782c158a98aed3aa676d9c85117525dcf3acc5506a30a8d87369fbcb"
  let asset_a_asset_name = #"4d6f6e6574"
  let asset_b_policy_id =
    #"8f52f6a88acf6127bc4758a16b6047afc4da7887feae121ec217b75a"
  let asset_b_asset_name = #"534e4f57"
  let pool_value =
    value.zero()
      |> value.add(authen_policy_id, pool_auth_asset_name, 1)
      |> value.add(authen_policy_id, lp_asset_name, 10000)
      |> value.add(ada_policy_id, ada_asset_name, 100000)
      |> value.add(asset_a_policy_id, asset_a_asset_name, 100000)
      |> value.add(asset_b_policy_id, asset_b_asset_name, 100000)
  validate_pool_value(
    val: pool_value,
    authen_policy_id: authen_policy_id,
    pool_auth_asset_name: pool_auth_asset_name,
    lp_asset_name: lp_asset_name,
    asset_a_policy_id: asset_a_policy_id,
    asset_a_asset_name: asset_a_asset_name,
    asset_b_policy_id: asset_b_policy_id,
    asset_b_asset_name: asset_b_asset_name,
  )
}

test test_validate_pool_value_3() {
  let authen_policy_id =
    #"fd7df11942fcd168a93620d88fc53a4336c48e0f799e73263b7d5660"
  let pool_auth_asset_name = #"4d5350"
  let lp_asset_name =
    #"31d0e583e0998ce44b2837f491edbf3d895973c136869a9e912d1d1a7a36568b"
  let asset_a_policy_id =
    #"782c158a98aed3aa676d9c85117525dcf3acc5506a30a8d87369fbcb"
  let asset_a_asset_name = #"4d6f6e6574"
  let asset_b_policy_id =
    #"8f52f6a88acf6127bc4758a16b6047afc4da7887feae121ec217b75a"
  let asset_b_asset_name = #"534e4f57"
  let pool_value =
    value.zero()
      |> value.add(authen_policy_id, pool_auth_asset_name, 1)
      |> value.add(authen_policy_id, lp_asset_name, 10000)
      |> value.add(ada_policy_id, ada_asset_name, 100000)
  validate_pool_value(
    val: pool_value,
    authen_policy_id: authen_policy_id,
    pool_auth_asset_name: pool_auth_asset_name,
    lp_asset_name: lp_asset_name,
    asset_a_policy_id: asset_a_policy_id,
    asset_a_asset_name: asset_a_asset_name,
    asset_b_policy_id: asset_b_policy_id,
    asset_b_asset_name: asset_b_asset_name,
  )
}

test test_validate_pool_value_4() fail {
  let authen_policy_id =
    #"fd7df11942fcd168a93620d88fc53a4336c48e0f799e73263b7d5660"
  let pool_auth_asset_name = #"4d5350"
  let lp_asset_name =
    #"31d0e583e0998ce44b2837f491edbf3d895973c136869a9e912d1d1a7a36568b"
  let asset_a_policy_id =
    #"782c158a98aed3aa676d9c85117525dcf3acc5506a30a8d87369fbcb"
  let asset_a_asset_name = #"4d6f6e6574"
  let asset_b_policy_id =
    #"8f52f6a88acf6127bc4758a16b6047afc4da7887feae121ec217b75a"
  let asset_b_asset_name = #"534e4f57"
  let pool_value =
    value.zero()
      |> value.add(authen_policy_id, lp_asset_name, 10000)
      |> value.add(asset_a_policy_id, asset_a_asset_name, 100000)
      |> value.add(asset_b_policy_id, asset_b_asset_name, 100000)
      |> value.add(ada_policy_id, ada_asset_name, 100000)
  validate_pool_value(
    val: pool_value,
    authen_policy_id: authen_policy_id,
    pool_auth_asset_name: pool_auth_asset_name,
    lp_asset_name: lp_asset_name,
    asset_a_policy_id: asset_a_policy_id,
    asset_a_asset_name: asset_a_asset_name,
    asset_b_policy_id: asset_b_policy_id,
    asset_b_asset_name: asset_b_asset_name,
  )
}

pub fn validate_pool_value(
  val: Value,
  authen_policy_id: PolicyId,
  pool_auth_asset_name: AssetName,
  lp_asset_name: AssetName,
  asset_a_policy_id: PolicyId,
  asset_a_asset_name: AssetName,
  asset_b_policy_id: PolicyId,
  asset_b_asset_name: AssetName,
) -> Bool {
  let flatten_value = value.flatten(val)
  let value_size = list.length(flatten_value)

  expect
    value.quantity_of(
      self: val,
      policy_id: authen_policy_id,
      asset_name: pool_auth_asset_name,
    ) == 1
  let lp_amount =
    value.quantity_of(
      self: val,
      policy_id: authen_policy_id,
      asset_name: lp_asset_name,
    )
  let reserve_a =
    value.quantity_of(
      self: val,
      policy_id: asset_a_policy_id,
      asset_name: asset_a_asset_name,
    )
  let reserve_b =
    value.quantity_of(
      self: val,
      policy_id: asset_b_policy_id,
      asset_name: asset_b_asset_name,
    )
  let c0 = 1
  let c1 =
    if lp_amount > 0 {
      c0 + 1
    } else {
      c0
    }
  let c2 =
    if reserve_a > 0 {
      c1 + 1
    } else {
      c1
    }
  let c3 =
    if reserve_b > 0 {
      c2 + 1
    } else {
      c2
    }
  let c4 =
    if is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
      c3
    } else {
      c3 + 1
    }
  // trace cbor.diagnostic(value_size)
  // trace cbor.diagnostic(c4)
  value_size == c4
  // let validate_num =
  //   list.foldr(
  //     flatten_value,
  //     0,
  //     fn(v, acc) {
  //       let (pid, an, am) = v
  //       expect am > 0
  //       if pid == authen_policy_id {
  //         if an == pool_auth_asset_name && am == 1 {
  //           acc + 1
  //         } else if an == lp_asset_name {
  //           acc + 1
  //         } else {
  //           fail
  //         }
  //       } else if pid == asset_a_policy_id && an == asset_a_asset_name {
  //         acc + 1
  //       } else if pid == asset_b_policy_id && an == asset_b_asset_name {
  //         acc + 1
  //       } else if pid == ada_policy_id && an == ada_asset_name {
  //         acc + 1
  //       } else {
  //         fail
  //       }
  //     },
  //   )
  // trace cbor.diagnostic(value_size)
  // trace cbor.diagnostic(validate_num)
  // validate_num == value_size
}

pub fn compare_list_length(arr1: List<a>, arr2: List<b>) -> Bool {
  when arr1 is {
    [] -> arr2 == []
    [_, ..xs] ->
      when arr2 is {
        [] -> False
        [_, ..ys] -> compare_list_length(xs, ys)
      }
  }
}

test test_compare_list_length() {
  let arr1 =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
  let arr2 =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
  compare_list_length(arr1, arr2)
}

test test_compare_list_length_1() {
  let arr1 =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
  let arr2 =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
  !compare_list_length(arr1, arr2)
}

test test_compare_list_length_2() {
  let arr1 =
    []
  let arr2 =
    []
  compare_list_length(arr1, arr2)
}

test test_compare_list_length_3() {
  let arr1 =
    [1]
  let arr2 =
    []
  !compare_list_length(arr1, arr2)
}
