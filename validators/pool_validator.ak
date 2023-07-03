use aiken/transaction.{ScriptContext}
use aiken/transaction/value.{AssetName, PolicyId}
use amm_dex_v2/types.{PoolDatum, PoolRedeemer}

validator(
  _authen_policy_id: PolicyId,
  _license_policy_id: PolicyId,
  _admin_asset_name: AssetName,
  _maximum_deadline_range: Int,
) {
  fn validate_pool(
    _datum: PoolDatum,
    _redeemer: PoolRedeemer,
    _context: ScriptContext,
  ) {
    True
  }
}
