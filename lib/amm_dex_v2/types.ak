use aiken/dict.{Dict}
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

pub type DatumMap =
  Dict<Hash<Blake2b_256, Data>, Data>

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
  reserve_a: Int,
  reserve_b: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  order_hash: ValidatorHash,
  profit_sharing_opt: Option<ProfitSharing>,
}

pub type PoolRedeemer {
  Batching {
    batcher_address: Address,
    input_indexes: List<Int>,
    license_index: Int,
  }
  MultiRouting {
    batcher_address: Address,
    license_index: Int,
    routing_in_indexes: List<Int>,
    routing_out_indexes: List<Int>,
  }
  UpdateFeeTo { admin_index: Int }
  WithdrawLiquidityShare { admin_index: Int, fee_to_index: Int }
}

pub type OrderDirection {
  AToB
  BToA
}

pub type SwapRouting {
  lp_asset: Asset,
  direction: OrderDirection,
}

// TODO: handle MultiRouting Order
pub type OrderStep {
  // TODO: Combine SwapExactIn, SwapExactInStopLoss & SwapExactInOCO to single one
  SwapExactIn { direction: OrderDirection, minimum_receive: Int }
  // TODO: SwapExactInStopLoss & SwapExactInOCO: Find another way that's easier to understand for users
  StopLoss { direction: OrderDirection, stop_loss_receive: Int }
  OCO {
    direction: OrderDirection,
    minimum_receive: Int,
    stop_loss_receive: Int,
  }
  SwapExactOut { direction: OrderDirection, expected_receive: Int }
  Deposit { minimum_lp: Int }
  Withdraw { minimum_asset_a: Int, minimum_asset_b: Int }
  ZapOut { direction: OrderDirection, minimum_receive: Int }
  PartialSwap {
    direction: OrderDirection,
    io_ratio_numerator: Int,
    io_ratio_denominator: Int,
    hops: Int,
    minimum_swap_amount_required: Int,
  }
  WithdrawImbalance {
    ratio_asset_a: Int,
    ratio_asset_b: Int,
    minimum_asset_a: Int,
  }
  SwapMultiRouting { routings: List<SwapRouting>, minimum_receive: Int }
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

pub type BatchingPool {
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  profit_sharing: Option<(Int, Int)>,
  order_hash: ValidatorHash,
  address: Address,
  pool_state_in: PoolState,
  pool_state_out: PoolState,
}

// Datum Reserve A 
// Datum Reserve B
// Value Reserve A
// Value Reserve B
// Total Liquidity
pub type PoolState =
  (Int, Int, Int, Int, Int)
