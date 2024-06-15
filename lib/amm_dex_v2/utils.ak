use aiken/builtin
use aiken/bytearray
use aiken/dict.{Dict}
use aiken/hash.{Blake2b_224, Hash}
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list
use aiken/transaction.{
  Datum, DatumHash, InlineDatum, Input, NoDatum, Output, ValidityRange,
}
use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, StakeCredential, VerificationKey,
}
use aiken/transaction/value.{
  AssetName, MintedValue, PolicyId, Value, ada_asset_name, ada_policy_id,
}
use amm_dex_v2/types.{
  Asset, DatumMap, OAMMintScript, OAMSignature, OAMSpendScript,
  OAMWithdrawScript, OrderAuthorizationMethod, PAMSignature, PAMSpendScript,
  PAMWithdrawScript, PoolAuthorizationMethod, SortedValueList,
}

// the legitimate Pool TokenName
pub const pool_auth_asset_name = #"4d5350"

// the legitimate Factory TokenName
pub const factory_auth_asset_name = #"4d5346"

// the legitimate Global Setting TokenName
pub const global_setting_asset_name = #"4d534753"

pub const default_burn_liquidity = 10

pub const default_fee_denominator = 10000

// Base Fee constraint
// Max 20%
pub const max_base_fee_numerator = 2000

// Min 0.05%
pub const min_base_fee_numerator = 5

// Vol Fee constraint
// Max 2%
pub const max_vol_fee_numerator = 200

// Min 0%
pub const min_vol_fee_numerator = 0

// Trading Fee constraint
// Max 20%
pub const max_trading_fee_numerator = 2000

// Min 0.05%
pub const min_trading_fee_numerator = 5

// Fee Sharing constraint
// Max 50%
pub const max_fee_sharing_numerator = 5000

// Min 16.66%
pub const min_fee_sharing_numerator = 1666

pub const min_pool_ada = 4500000

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

pub fn must_find_script_inline_datum(datum: Datum) -> Data {
  when datum is {
    InlineDatum(dat) -> dat
    _ -> fail
  }
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
  arr3: List<c>,
  predicate: fn(a, b, c) -> result,
) -> List<result> {
  expect [x, ..xs] = arr1
  expect [y, ..ys] = arr2
  expect [z, ..zs] = arr3
  if xs == [] {
    expect and {
        [] == ys,
        [] == zs,
      }
    [predicate(x, y, z)]
  } else {
    [predicate(x, y, z), ..zip_with(xs, ys, zs, predicate)]
  }
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

const empty_mark =
  #[0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ]

fn do_is_unique_bytearray_unsorted(
  self: ByteArray,
  acc: ByteArray,
  index: Int,
  length: Int,
) {
  if index >= length {
    True
  } else {
    let value_as_index = builtin.index_bytearray(self, index)
    let acc_value = builtin.index_bytearray(acc, value_as_index)
    if acc_value == 1 {
      False
    } else {
      let left_slice = builtin.slice_bytearray(0, value_as_index, acc)
      let righ_slice = builtin.slice_bytearray(value_as_index + 1, 64, acc)
      let new_acc =
        builtin.append_bytearray(
          left_slice,
          builtin.cons_bytearray(1, righ_slice),
        )
      do_is_unique_bytearray_unsorted(self, new_acc, index + 1, length)
    }
  }
}

pub fn is_unique_bytearray_unsorted(array: ByteArray) -> Bool {
  let length = builtin.length_of_bytearray(array)
  if length > 0 {
    do_is_unique_bytearray_unsorted(array, empty_mark, 0, length)
  } else {
    False
  }
}

test test_unique_bytearray_unsorted_1() {
  let array =
    #[1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      26,
      27,
      28,
      29,
      30,
      31,
      32,
      33,
      34,
      35,
      36,
      37,
      38,
      39,
      40,
    ]
  is_unique_bytearray_unsorted(array)
}

test test_unique_bytearray_unsorted_2() {
  let array = #[1, 2, 3, 4, 5, 6, 5]
  !is_unique_bytearray_unsorted(array)
}

test test_unique_bytearray_unsorted_3() {
  let array = #[0, 1, 2, 3, 4, 5, 6, 0]
  !is_unique_bytearray_unsorted(array)
}

test test_unique_bytearray_unsorted_4() fail {
  let array = #[0, 1, 2, 3, 4, 5, 64, 0]
  !is_unique_bytearray_unsorted(array)
}

test test_unique_bytearray_unsorted_5() {
  let array = #[]
  !is_unique_bytearray_unsorted(array)
}

// Approximate the current time by obtaining the upper and lower bounds of the validity range. 
// Ensure that the bounds do not exceed 10 minutes.
pub fn must_get_current_time_approximation(validity_range: ValidityRange) -> Int {
  let Interval {
    lower_bound: IntervalBound { bound_type: lower_bound_type, .. },
    upper_bound: IntervalBound { bound_type: upper_bound_type, .. },
  } = validity_range
  expect Finite(start_valid_time_range) = lower_bound_type
  expect Finite(end_valid_time_range) = upper_bound_type
  if end_valid_time_range - start_valid_time_range <= 10 * 60 * 1000 {
    ( end_valid_time_range - start_valid_time_range ) / 2 + start_valid_time_range
  } else {
    fail
  }
}

pub fn must_get_finite_start_validity(validity_range: ValidityRange) -> Int {
  let Interval {
    lower_bound: IntervalBound { bound_type: lower_bound_type, .. },
    ..
  } = validity_range
  expect Finite(start_valid_time_range) = lower_bound_type
  start_valid_time_range
}

pub fn value_to_list(val: Value) -> SortedValueList {
  val
    |> value.to_dict
    |> dict.to_list
    |> list.map(
         fn(e) {
           let (k, v) = e
           (k, dict.to_list(v))
         },
       )
}

// Pool Author can be one of 3 authorization methods
pub fn authorize_pool_license(
  author: PoolAuthorizationMethod,
  transaction_inputs: List<Input>,
  withdrawals: Dict<StakeCredential, Int>,
  extra_signatories: List<Hash<Blake2b_224, VerificationKey>>,
) -> Bool {
  when author is {
    // If the authorization method is PubKey, validate using the provided signature.
    PAMSignature(pub_key_hash) -> list.has(extra_signatories, pub_key_hash)
    // If the authorization method is SpendScript, ensure the Utxo is present in the transaction inputs.
    PAMSpendScript(script_hash) -> {
      let auth_cred = ScriptCredential(script_hash)
      list.any(
        transaction_inputs,
        fn(input) {
          let Input { output, .. } = input
          let Output { address: out_address, .. } = output
          let Address { payment_credential: out_payment_credential, .. } =
            out_address
          out_payment_credential == auth_cred
        },
      )
    }
    // If the authorization method is WithdrawScript, validate the presence of a withdrawal in the transaction.
    PAMWithdrawScript(script_hash) -> {
      let credential = Inline(ScriptCredential(script_hash))
      dict.has_key(withdrawals, credential)
    }
  }
}

// Validates an order based on the specified authorization method.
pub fn authorize_order_license(
  author: OrderAuthorizationMethod,
  transaction_inputs: List<Input>,
  withdrawals: Dict<StakeCredential, Int>,
  extra_signatories: List<Hash<Blake2b_224, VerificationKey>>,
  transaction_mint: MintedValue,
) -> Bool {
  when author is {
    // If the authorization method is PubKey, validate using the provided signature.
    OAMSignature(pub_key_hash) -> list.has(extra_signatories, pub_key_hash)
    // If the authorization method is SpendScript, ensure the Utxo is present in the transaction inputs.
    OAMSpendScript(script_hash) -> {
      let auth_cred = ScriptCredential(script_hash)
      list.any(
        transaction_inputs,
        fn(input) {
          let Input { output, .. } = input
          let Output { address: out_address, .. } = output
          let Address { payment_credential: out_payment_credential, .. } =
            out_address
          out_payment_credential == auth_cred
        },
      )
    }
    // If the authorization method is WithdrawScript, validate the presence of a withdrawal in the transaction.
    OAMWithdrawScript(script_hash) -> {
      let credential = Inline(ScriptCredential(script_hash))
      dict.has_key(withdrawals, credential)
    }
    // If the authorization method is MintScript, ensure the minted tokens meet the policy ID requirements and have a non-zero quantity.
    OAMMintScript(script_hash) -> {
      let fst_token_quantity =
        transaction_mint
          |> value.from_minted_value()
          |> value.tokens(script_hash)
          |> dict.to_list()
          |> builtin.head_list
          |> builtin.snd_pair
      fst_token_quantity != 0
    }
  }
}
