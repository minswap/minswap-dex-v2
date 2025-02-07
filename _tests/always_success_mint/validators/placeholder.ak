use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use cardano/script_context.{ScriptContext}

validator placeholder {
  mint(_redeemer: Data, _policy_id: PolicyId, _self: Transaction) {
    True
  }

  else(_ctx: ScriptContext) {
    fail
  }
}
