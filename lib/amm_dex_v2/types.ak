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

// Profit Sharing Numerator & Denominator
pub type ProfitSharing =
  (Int, Int)

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

pub type UpdatePoolFeeOrStakeCredentialAction {
  UpdatePoolFee
  UpdatePoolStakeCredential
}

pub type PoolRedeemer {
  Batching { input_indexes: List<Int>, license_index: Int }
  MultiRouting {
    license_index: Int,
    routing_in_indexes: List<Int>,
    routing_out_indexes: List<Int>,
  }
  UpdatePoolFeeOrStakeCredential {
    action: UpdatePoolFeeOrStakeCredentialAction,
    admin_index: Int,
  }
  WithdrawLiquidityShare { admin_index: Int }
}

pub type OrderDirection {
  AToB
  BToA
}

pub type SwapRouting {
  lp_asset: Asset,
  direction: OrderDirection,
}

pub type OrderStep {
  // SwapExactIn is used for exchanging specific amount of single asset in the liquidity pool. 
  // The order will be executed if the received amount is greater than or equal to `minimum_receive`.
  SwapExactIn {
    // The direction (AToB or BToA) of swap request. 
    direction: OrderDirection,
    // Minimum amount of Asset Out which users want to receive after exchanging
    minimum_receive: Int,
  }
  // StopLoss is used for exchanging specific amount of single asset in the liquidity pool.
  // The order will be executed if the received amount is less than or equal to `stop_loss_receive`
  StopLoss {
    // The direction (AToB or BToA) of swap request.  
    direction: OrderDirection,
    // Maximum amount of Asset Out which users want to receive after exchanging
    stop_loss_receive: Int,
  }
  // OCO is used for exchanging specific amount of single asset in the liquidity pool.
  // The order will be executed if the received amount is less than or equal to `stop_loss_receive` 
  //    and greater than or equal to `minimum_receive`
  OCO {
    // The direction (AToB or BToA) of swap request.  
    direction: OrderDirection,
    // Minimum amount of Asset Out which users want to receive after exchanging
    minimum_receive: Int,
    // Maximum amount of Asset Out which users want to receive after exchanging
    stop_loss_receive: Int,
  }
  // SwapExactOut is used for exchanging single asset in the liquidity pool and receiving the exact amout of other asset.
  // The order will be executed if the received amount is equal to `expected_receive`
  SwapExactOut {
    // The direction (AToB or BToA) of swap request.  
    direction: OrderDirection,
    // The exact amount of Asset Out which users want to receive after exchanging
    expected_receive: Int,
  }
  // Deposit is used for depositing pool's assets and receiving LP Token
  Deposit {
    // The minimum amount of LP Token which users want to receive after depositing
    minimum_lp: Int,
  }
  // Withdraw is used for withdrawing pool's asset with the exact assets ratio of the liquidity pool at that time
  Withdraw {
    // minimum received amounts of Asset A
    minimum_asset_a: Int,
    // minimum received amounts of Asset B
    minimum_asset_b: Int,
  }
  // ZapOut is used for withdrawing a single pool asset out of Liquidity Pool
  ZapOut {
    // The direction (AToB or BToA) of ZapOut request. `AToB` in case Asset Out is B and vice versa
    direction: OrderDirection,
    // Minimum amount of Asset Out which users want to receive after withdrawing
    minimum_receive: Int,
  }
  // PartialSwap is used for exchange partial amount of single Asset. 
  // The Partial Swap can be executed multiple time if the price ratio is matched with user's expectation, 
  //   and the time is defined in `hops`
  PartialSwap {
    // The direction (AToB or BToA) of swap request.
    direction: OrderDirection,
    // the price ratio which users want to exchange
    io_ratio_numerator: Int,
    io_ratio_denominator: Int,
    // The time PartialSwap can be executed
    hops: Int,
    // The minimum amount which is required to swap per each execution time
    minimum_swap_amount_required: Int,
  }
  // WithdrawImbalance is used for withdrawing custom amount of assets.
  WithdrawImbalance {
    //  The ratio of Asset A and Asset B users want to receive after withdrawing
    ratio_asset_a: Int,
    ratio_asset_b: Int,
    // The minimum amount of asset A which users want to receive.
    // The amount of Asset will be followed by the ratio:
    //    (_received_asset_b_ = _minimum_asset_a_ * _ratio_asset_b_ / _ratio_asset_a_)
    minimum_asset_a: Int,
  }
  // SwapMultiRouting is used for exchanging specific amount of single asset across multiple Liquidity Pools.
  SwapMultiRouting {
    // The routings (including a list of _direction_ and _lp_asset_), 
    // which is defined Liquidity Pools the swap is routing through
    routings: List<SwapRouting>,
    // Minimum amount of Asset Out which users want to receive after exchanging
    minimum_receive: Int,
  }
}

pub type OrderDatum {
  // The address of order's creator, only sender can cancel the order
  sender: Address,
  // The address which receives the funds after order is processed
  receiver: Address,
  // The datum hash of the output after order is processed.
  receiver_datum_hash_opt: Option<CustomDatumHash>,
  // The Liquidity Pool's LP Asset that the order will be applied to
  lp_asset: Asset,
  // The information about Order Type
  step: OrderStep,
  // The fee users have to pay to Batcher to execute batching transaction
  batcher_fee: Int,
  // As known as Minimum ADA which users need to put to the Order, and these amounts will be returned with _receiver_ Output
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

pub type OrderBatchingRedeemer {
  // it's used for finding Pool Input faster
  pool_input_index: Int,
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
