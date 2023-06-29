use aiken/builtin
use aiken/bytearray
use aiken/cbor
use aiken/list

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
