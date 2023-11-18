use aiken/cbor
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, TransactionId,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{Value}
use amm_dex_v2/utils

fn get_test_inputs() -> List<Input> {
  let order_input =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId {
          hash: #"e1ef772687064b1f3b503729de74aad12cc6c77f9742ae679501c6a1fa8f9f5a",
        },
        output_index: 0,
      },
      output: Output {
        address: credential.from_script(
          #"04d04543ed4fbed44df2e948989c91093812f16a1eced4781e352cba",
        ),
        value: value.zero()
          |> value.add(#"", #"", 4000000)
          |> value.add(
               #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
               #"4d494e",
               10000000000,
             ),
        datum: InlineDatum(
          #"d8799fd8799fd8799f581cf41b34917c979d6bf39eb4cce2893ac17c56f2644e71d740556c4caaffd8799fd8799fd8799f581ccf0bfbcdd21425d71c606126031307527da33b0a9f1ecb8dd186bbc1ffffffffd8799fd8799f581cf41b34917c979d6bf39eb4cce2893ac17c56f2644e71d740556c4caaffd8799fd8799fd8799f581ccf0bfbcdd21425d71c606126031307527da33b0a9f1ecb8dd186bbc1ffffffffd87a80d8799f581c4c93d156f973835939cd90696c041b521dc725c290c3eb0ead5ed61358206c3ea488e6ff940bb6fb1b18fd605b5931d9fefde6440117015ba484cf321200ffd8799fd8798001ff1a001e84801a001e8480ff",
        ),
        reference_script: None,
      },
    }
  let pool_input =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId {
          hash: #"e1ef772687064b1f3b503729de74aad12cc6c77f9742ae679501c6a1fa8f9f5a",
        },
        output_index: 1,
      },
      output: Output {
        address: credential.from_script(
          #"3ad0e55b256b19b851e73bf25cd1e33ee40b6879ba1e15c612f74f5c",
        ),
        value: value.zero()
          |> value.add(#"", #"", 4000000)
          |> value.add(
               #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
               #"4d494e",
               10000000000,
             ),
        datum: InlineDatum(
          #"d8799fd8799f4040ffd8799f581ce16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72434d494eff1b000060a052fbfdd01b0000195ad80577651b000179434f1ba23a031903e8581c04d04543ed4fbed44df2e948989c91093812f16a1eced4781e352cbad87a80ff",
        ),
        reference_script: None,
      },
    }
  [
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    pool_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
    order_input,
  ]
}

test test_hihi_14() {
  let input =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId {
          hash: #"e1ef772687064b1f3b503729de74aad12cc6c77f9742ae679501c6a1fa8f9f5a",
        },
        output_index: 0,
      },
      output: Output {
        address: credential.from_script(
          #"04d04543ed4fbed44df2e948989c91093812f16a1eced4781e352cba",
        ),
        value: value.zero()
          |> value.add(#"", #"", 4000000)
          |> value.add(
               #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
               #"4d494e",
               10000000000,
             ),
        datum: InlineDatum(
          #"d8799fd8799fd8799f581cf41b34917c979d6bf39eb4cce2893ac17c56f2644e71d740556c4caaffd8799fd8799fd8799f581ccf0bfbcdd21425d71c606126031307527da33b0a9f1ecb8dd186bbc1ffffffffd8799fd8799f581cf41b34917c979d6bf39eb4cce2893ac17c56f2644e71d740556c4caaffd8799fd8799fd8799f581ccf0bfbcdd21425d71c606126031307527da33b0a9f1ecb8dd186bbc1ffffffffd87a80d8799f581c4c93d156f973835939cd90696c041b521dc725c290c3eb0ead5ed61358206c3ea488e6ff940bb6fb1b18fd605b5931d9fefde6440117015ba484cf321200ffd8799fd8798001ff1a001e84801a001e8480ff",
        ),
        reference_script: None,
      },
    }
  let inputs =
    [
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
      input,
    ]
  let x =
    list.filter(
      inputs,
      fn(input) {
        let Input {
          output: Output {
            address: Address { payment_credential: cred, .. },
            ..
          },
          ..
        } = input
        expect ScriptCredential(h) = cred
        h == #"04d04543ed4fbed44df2e948989c91093812f16a1eced4781e352cba"
      },
    )
  x == inputs
}

// fn find_pool_and_orders(
//   pool_ref: OutputReference,
//   order_hash: ByteArray,
//   batcher_address: Address,
//   inputs: List<Input>,
//   outputs: List<Output>,
//   order_input_indexes: List<Int>,
// ) -> Bool {
//   let (p, ins) =
//     list.foldr(
//       inputs,
//       (None, []),
//       fn(input, acc) {
//         let (pool_in, order_ins) = acc
//         let Input { output_reference: out_ref, output: out } = input
//         when pool_in is {
//           None ->
//             if out_ref == pool_ref {
//               (Some(input), order_ins)
//             } else {
//               let Output {
//                 address: Address { payment_credential: payment_cred, .. },
//                 ..
//               } = out
//               when payment_cred is {
//                 ScriptCredential(h) ->
//                   if h == order_hash {
//                     (pool_in, [input, ..order_ins])
//                   } else {
//                     acc
//                   }
//                 _ -> acc
//               }
//             }
//           Some(_) -> {
//             let Output {
//               address: Address { payment_credential: payment_cred, .. },
//               ..
//             } = out
//             when payment_cred is {
//               ScriptCredential(h) ->
//                 if h == order_hash {
//                   (pool_in, [input, ..order_ins])
//                 } else {
//                   acc
//                 }
//               _ -> acc
//             }
//           }
//         }
//       },
//     )
//   expect Some(_) = p
//   expect _ = ins
//   True
// }

test test_richard_1() {
  let inputs = get_test_inputs()
  let order_hash = #"04d04543ed4fbed44df2e948989c91093812f16a1eced4781e352cba"
  let pool_ref =
    OutputReference {
      transaction_id: TransactionId {
        hash: #"e1ef772687064b1f3b503729de74aad12cc6c77f9742ae679501c6a1fa8f9f5a",
      },
      output_index: 1,
    }
  let (p, ins) =
    list.foldr(
      inputs,
      (None, []),
      fn(input, acc) {
        let (pool_in, order_ins) = acc
        let Input { output_reference: out_ref, output: out } = input
        when pool_in is {
          None ->
            if out_ref == pool_ref {
              (Some(input), order_ins)
            } else {
              let Output {
                address: Address { payment_credential: payment_cred, .. },
                ..
              } = out
              when payment_cred is {
                ScriptCredential(h) ->
                  if h == order_hash {
                    (pool_in, [input, ..order_ins])
                  } else {
                    acc
                  }
                _ -> acc
              }
            }
          Some(_) -> {
            let Output {
              address: Address { payment_credential: payment_cred, .. },
              ..
            } = out
            when payment_cred is {
              ScriptCredential(h) ->
                if h == order_hash {
                  (pool_in, [input, ..order_ins])
                } else {
                  acc
                }
              _ -> acc
            }
          }
        }
      },
    )
  expect Some(_) = p
  list.length(ins) > 0
}

test test_richard_2() {
  let inputs = get_test_inputs()
  let order_hash = #"04d04543ed4fbed44df2e948989c91093812f16a1eced4781e352cba"
  let pool_ref =
    OutputReference {
      transaction_id: TransactionId {
        hash: #"e1ef772687064b1f3b503729de74aad12cc6c77f9742ae679501c6a1fa8f9f5a",
      },
      output_index: 1,
    }
  expect Some(_) =
    list.find(
      inputs,
      fn(input) {
        let Input { output_reference: out_ref, .. } = input
        pool_ref == out_ref
      },
    )
  let user_inputs =
    list.filter(
      inputs,
      fn(input) {
        let Input { output: out, .. } = input
        let Output { address: addr, .. } = out
        let Address { payment_credential: payment_cred, .. } = addr
        when payment_cred is {
          ScriptCredential(hash) -> hash == order_hash
          _ -> False
        }
      },
    )
  list.length(user_inputs) > 0
}

test test_hihi_1() {
  let arr =
    [1, 2, 3, 4, 5]
  expect [a, b, c, d, e] = arr
  a == 1 && b == 2 && c == 3 && d == 4 && e == 5
}

test test_hihi_111() {
  let arr =
    [1, 2, 3, 4, 5]
  let x =
    list.foldl(
      arr,
      0,
      fn(a, acc) {
        trace cbor.diagnostic(a)
        acc + a
      },
    )
  x > 0
}

type A {
  a: Int,
  b: Int,
  c: Int,
  d: Int,
  e: Int,
}

test test_hihi_2() {
  let arr = (1, 2, 3, 4, 5)
  let (a, b, c, d, e) = arr
  a == 1 && b == 2 && c == 3 && d == 4 && e == 5
}

test test_hihi_3() {
  let arr = A { a: 1, b: 2, c: 3, d: 4, e: 5 }
  let A { a, b, c, d, e } = arr
  a == 1 && b == 2 && c == 3 && d == 4 && e == 5
}

test test_hihi_4() {
  let arr =
    [1, 2, 3, 4, 5]
  let result = list.filter(arr, fn(x) { x > 2 })
  expect [c, d, e] = result
  c == 3 && d == 4 && e == 5
}

test test_hihi_5() {
  let arr =
    [1, 2, 3, 4, 5]
  let c = utils.list_at_index(arr, 2)
  let d = utils.list_at_index(arr, 3)
  let e = utils.list_at_index(arr, 4)
  c == 3 && d == 4 && e == 5
}

test test_hihi_6() {
  let arr =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
  when list.unique(arr) is {
    [] -> False
    _ -> True
  }
}

test test_hihi_7() {
  let arr =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
  let uni = list.unique(arr)
  arr == uni
}

test test_hihi_8() {
  let arr1 =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
  let arr2 =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
  // let uni = list.unique(arr)
  arr1 == arr2
}

test test_hihi_9() {
  let val1 =
    value.zero()
      |> value.add(#"", #"", 20000000)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           3000000000,
         )
  let val2 =
    value.zero()
      |> value.add(#"", #"", 20000000)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           3000000000,
         )
  val1 == val2
}

test test_hihi_10() {
  let val1 =
    value.zero()
      |> value.add(#"", #"", 20000000)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           3000000000,
         )
  let val2 =
    value.zero()
      |> value.add(#"", #"", 20000000)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           3000000000,
         )
  val1 == val2
}

test test_hihi_11() {
  let val1 =
    value.zero()
      |> value.add(#"", #"", 20000000)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           3000000000,
         )
  let val2 =
    value.zero()
      |> value.add(#"", #"", 20000000)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           3000000000,
         )
  value.lovelace_of(val1) == value.lovelace_of(val2) && value.quantity_of(
    val1,
    #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
    #"4d494e",
  ) == value.quantity_of(
    val2,
    #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
    #"4d494e",
  )
}

test test_hihi_12() {
  let val1 =
    value.zero()
      |> value.add(#"", #"", 20000000)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           3000000000,
         )
  value.quantity_of(
    val1,
    #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
    #"4d494e",
  ) == 3000000000
}

fn hehe(val: Value) -> Int {
  value.quantity_of(
    val,
    #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
    #"4d494e",
  )
}

test test_hihi_13() {
  let val1 =
    value.zero()
      |> value.add(#"", #"", 20000000)
      |> value.add(
           #"e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72",
           #"4d494e",
           3000000000,
         )
  hehe(val1) == 3000000000
}

test test_hihi_15() {
  let arr =
    [1, 3, 4, 5, 6, 6, 7, 7]
  list.length(arr) > 2
}

test test_hihi_16() {
  let arr =
    [1, 3, 4, 5, 6, 6, 7, 7]
  list_length(arr) > 2
}

test test_hihi_17() {
  let arr =
    [1, 3, 4, 5, 6, 6, 7, 7]
  let x = utils.list_at_index(arr, 2)
  x > 0
}

fn list_length(arr: List<a>) -> Int {
  when arr is {
    [] -> 0
    [_] -> 1
    [_, _] -> 2
    [_, _, _] -> 3
    [_, _, _, _] -> 4
    [_, _, _, _, _] -> 5
    [_, _, _, _, _, _] -> 6
    [_, _, _, _, _, _, _] -> 7
    [_, _, _, _, _, _, _, _] -> 8
    [_, _, _, _, _, _, _, _, _] -> 9
    [_, _, _, _, _, _, _, _, _, _] -> 10
    _ -> list_length(utils.skip_10_items(arr))
  }
}

test test_hihi_18() {
  let arr =
    [1, 3, 4, 5, 6, 6, 7, 7]
  let x = list.foldr(arr, 0, fn(a, acc) { a + acc })
  x == 39
}

test test_hihi_19() {
  let arr =
    [1, 3, 4, 5, 6, 6, 7, 7]
  let x = list.foldl(arr, 0, fn(a, acc) { a + acc })
  x == 39
}
