use aiken/transaction.{ScriptContext, Spend}

validator {
  fn spend(_d: Data, _r: Data, ctx: ScriptContext) {
    expect ScriptContext { purpose: Spend(_), .. } = ctx
    True
  }
}
