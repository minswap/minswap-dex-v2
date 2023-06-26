use aiken/transaction.{ScriptContext}
use amm_dex_v2/types

validator {
  fn spend(datum: types.Datum, _redeemer: Data, _ctx: ScriptContext) -> Bool {
    datum.message == "Hello World!"
  }
}
