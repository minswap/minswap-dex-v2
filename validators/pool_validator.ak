use aiken/transaction.{ScriptContext}
use amm_dex_v2/types.{PoolDatum, PoolParams, PoolRedeemer}

validator(_params: PoolParams) {
  fn validate_pool(
    _datum: PoolDatum,
    _redeemer: PoolRedeemer,
    _context: ScriptContext,
  ) {
    True
  }
}
