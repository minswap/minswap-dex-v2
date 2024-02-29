use aiken/builtin
use aiken/bytearray
use aiken/dict
use aiken/hash
use aiken/string
use aiken/transaction.{Datum, DatumHash, InlineDatum, NoDatum}
use aiken/transaction/value.{AssetName, PolicyId, ada_asset_name, ada_policy_id}
use amm_dex_v2/types.{Asset, DatumMap}

const zero_ascii_code = 48

const nine_ascii_code = 57

// Policy ID managed by the Minswap team, used for minting Batcher License
pub const batcher_license_policy_id =
  #"229013ad3a22d2d051a28e7f9214a32444ecf19998f7bdf0c2849862"

// the legitimate Pool TokenName
pub const pool_auth_asset_name = #"4d5350"

// the legitimate Factory TokenName
pub const factory_auth_asset_name = #"4d53"

// Policy ID managed by the Minswap team, used for minting Admin License assets
pub const admin_policy_id =
  #"f8c20eb8b2e773e21cf41ab6354cf09bd255ebed0bd8847c655e67b4"

// Maximum expiration time of Batcher license from now (to prevent minting infinity license)
pub const maximum_deadline_range = 77760000000

pub const default_burn_liquidity = 10

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

test test_sorted_asset() {
  let asset_a = Asset { policy_id: ada_policy_id, asset_name: ada_asset_name }
  let asset_b =
    Asset {
      policy_id: #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
      asset_name: #"4d494e",
    }
  and {
    sorted_asset(asset_a, asset_b),
    !sorted_asset(asset_a, asset_a),
    !sorted_asset(asset_b, asset_a),
  }
}

pub fn is_ada_asset(pid: PolicyId, name: AssetName) -> Bool {
  pid == ada_policy_id && name == ada_asset_name
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

pub fn bytearray_to_positive_int(byte_arr: ByteArray) -> Int {
  let byte_len = builtin.length_of_bytearray(byte_arr)
  do_bytearray_positive_int(byte_arr, byte_len - 1)
}

pub fn do_bytearray_positive_int(byte_arr: ByteArray, idx: Int) -> Int {
  let byte = builtin.index_bytearray(byte_arr, idx)
  if zero_ascii_code <= byte && byte <= nine_ascii_code {
    if idx == 0 {
      byte - zero_ascii_code
    } else {
      do_bytearray_positive_int(byte_arr, idx - 1) * 10 + (
        byte - zero_ascii_code
      )
    }
  } else {
    fail
  }
}

test test_bytearray_to_positive_int() {
  let r1 = bytearray_to_positive_int(string.to_bytearray(@"123"))
  let r2 = bytearray_to_positive_int(string.to_bytearray(@"111"))
  let r3 = bytearray_to_positive_int(string.to_bytearray(@"9013"))
  r1 == 123 && r2 == 111 && r3 == 9013
}

pub fn must_find_script_datum(datums: DatumMap, datum: Datum) -> Data {
  when datum is {
    InlineDatum(dat) -> dat
    DatumHash(dh) ->
      datums
        |> dict_must_get(dh)
    NoDatum -> fail
  }
}

/// rewrite dict.get
/// convert `Option<value>` to `value`
/// `None` -> `fail`
fn dict_must_get(self: dict.Dict<key, value>, key: key) -> value {
  dict_do_must_get(dict.to_list(self), key)
}

fn dict_do_must_get(self: List<(key, value)>, key k: key) -> value {
  when self is {
    [(k2, v), ..rest] ->
      if k == k2 {
        v
      } else {
        dict_do_must_get(rest, k)
      }
    [] -> fail
  }
}

const foo = #"666f6f"

const bar = #"626172"

const baz = #"62617a"

test dict_must_get_1() fail {
  dict_must_get(dict.new(), foo) == ""
}

test dict_must_get_2() {
  let m =
    dict.new()
      |> dict.insert(foo, "Aiken", bytearray.compare)
      |> dict.insert(bar, "awesome", bytearray.compare)
  and {
    Some(dict_must_get(m, key: foo)) == dict.get(m, key: foo),
    Some(dict_must_get(m, key: bar)) == dict.get(m, key: bar),
  }
}

test dict_must_get_3() fail {
  let m =
    dict.new()
      |> dict.insert(foo, "Aiken", bytearray.compare)
      |> dict.insert(bar, "awesome", bytearray.compare)
  dict_must_get(m, key: baz) == ""
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
  expect [x, ..xs] = arr1
  expect [y, ..ys] = arr2
  if xs == [] {
    expect [] = ys
    [predicate(x, y)]
  } else {
    [predicate(x, y), ..zip_with(xs, ys, predicate)]
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

pub fn compare_list_length(arr1: List<a>, arr2: List<b>) -> Bool {
  when arr1 is {
    [] -> arr2 == []
    _ ->
      when arr2 is {
        [] -> False
        _ ->
          compare_list_length(
            arr1 |> builtin.tail_list,
            arr2 |> builtin.tail_list,
          )
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

fn contains_element(list: List<a>, elem: a) -> Bool {
  when list is {
    [] -> False
    [x, ..xs] -> elem == x || contains_element(xs, elem)
  }
}

pub fn is_list_unique(list: List<a>) -> Bool {
  when list is {
    [] -> True
    [_] -> True
    [x, ..xs] -> !contains_element(xs, x) && is_list_unique(xs)
  }
}
