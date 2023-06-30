use aiken/hash.{Blake2b_224, Blake2b_256, Hash}
use aiken/transaction/credential.{Address, Script, VerificationKey}
use aiken/transaction/value.{AssetName, PolicyId}

pub type CustomDatumHash =
  Hash<Blake2b_256, Data>

pub type ValidatorHash =
  Hash<Blake2b_224, Script>

pub type PubKeyHash =
  Hash<Blake2b_224, VerificationKey>

pub type Asset {
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type ProfitSharing {
  fee_sharing_numerator: Int,
  fee_sharing_denominator: Int,
  fee_to: Address,
  fee_to_datum_hash_opt: Option<CustomDatumHash>,
}

pub type PoolDatum {
  asset_a: Asset,
  asset_b: Asset,
  total_liquidity: Int,
  root_k_last: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  order_hash: ValidatorHash,
  profit_sharing_opt: Option<ProfitSharing>,
}

pub type PoolRedeemer {
  ApplyPool {
    batcher_address: Address,
    input_indexes: List<Int>,
    license_index: Int,
  }
  MultiRouting { batcher_address: Address, license_index: Int }
  UpdateFeeTo { admin_index: Int }
  WithdrawLiquidityShare { admin_index: Int, fee_to_index: Int }
}

pub type PoolParams {
  authen_policy_id: PolicyId,
  license_policy_id: PolicyId,
  admin_asset_name: AssetName,
  maximum_deadline_range: Int,
}

pub type OrderStep {
  SwapExactIn { a_to_b_direction: Bool, minimum_receive: Int }
  SwapExactOut { a_to_b_direction: Bool, expected_receive: Int }
  Deposit { minimum_lp: Int }
  Withdraw { minimum_asset_a: Int, minimum_asset_b: Int }
  ZapIn { a_to_b_direction: Bool, minimum_lp: Int }
  ZapOut { a_to_b_direction: Bool, minimum_receive: Int }
}

pub type OrderDatum {
  sender: Address,
  receiver: Address,
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  lp_asset: Asset,
  step: OrderStep,
  batcher_fee: Int,
  output_ada: Int,
}

pub type OrderRedeemer {
  ApplyOrder
  CancelOrder
}

pub type FactoryDatum {
  head: ByteArray,
  tail: ByteArray,
}

pub type FactoryRedeemer {
  asset_a: Asset,
  asset_b: Asset,
}

pub type AuthenRedeemer {
  MintFactoryAuthen
  CreatePool
  MintLiquidity
}
