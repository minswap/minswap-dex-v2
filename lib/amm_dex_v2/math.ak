use aiken/list

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
