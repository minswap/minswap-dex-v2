use aiken/transaction.{ScriptContext}
use amm_dex_v2/types.{FactoryDatum, FactoryParams, FactoryRedeemer}

validator(_params: FactoryParams) {
  fn validate_factory(
    _datum: FactoryDatum,
    _redeemer: FactoryRedeemer,
    _context: ScriptContext,
  ) {
    True
  }
}
