use aiken/transaction.{ScriptContext}
use amm_dex_v2/types.{OrderDatum, OrderRedeemer, ValidatorHash}

validator(_pool_hash: ValidatorHash) {
  fn validate_order(
    _datum: OrderDatum,
    _redeemer: OrderRedeemer,
    _context: ScriptContext,
  ) {
    True
  }
}
