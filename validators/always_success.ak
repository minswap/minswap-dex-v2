use cardano/transaction.{OutputReference, Transaction}

validator always_success {
  spend(_d: Option<Data>, _r: Data, _o: OutputReference, _self: Transaction) {
    True
  }

  else(_) {
    fail
  }
}
