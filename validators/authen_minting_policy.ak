use aiken/transaction.{ScriptContext}
use amm_dex_v2/types.{AuthenRedeemer}

validator {
  fn validate_authen(_redeemer: AuthenRedeemer, _context: ScriptContext) {
    True
  }
}
