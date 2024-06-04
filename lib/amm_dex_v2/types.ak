use aiken/dict.{Dict}
use aiken/hash.{Blake2b_224, Blake2b_256, Hash}
use aiken/transaction/credential.{
  Address, Script, StakeCredential, VerificationKey,
}
use aiken/transaction/value.{AssetName, PolicyId}

pub type CustomDatumHash =
  Hash<Blake2b_256, Data>

pub type ValidatorHash =
  Hash<Blake2b_224, Script>

pub type PubKeyHash =
  Hash<Blake2b_224, VerificationKey>

pub type SortedValueList =
  List<(ByteArray, List<(ByteArray, Int)>)>

pub type Asset {
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type DatumMap =
  Dict<Hash<Blake2b_256, Data>, Data>

pub type PoolDatum {
  // Stake Credential of `Pool Batching` validator
  pool_batching_stake_credential: StakeCredential,
  // The Pool's Asset A
  asset_a: Asset,
  // The Pool's Asset B
  asset_b: Asset,
  // Total Share of Liquidity Providers
  total_liquidity: Int,
  // Asset A's balance of Liquidity Providers
  reserve_a: Int,
  // Asset B's balance of Liquidity Providers
  reserve_b: Int,
  // Numerator of Trading Fee on Asset A side
  base_fee_a_numerator: Int,
  // Numerator of Trading Fee on Asset B side
  base_fee_b_numerator: Int,
  // (Optional) Numerator of Fee Sharing percentage.
  // This is the percentage of Trading Fee. (eg, Trading Fee is 3%, Profit Sharing is 1/6 -> Profit Sharing = 1/6 * 3%)
  fee_sharing_numerator_opt: Option<Int>,
  // Allow Batcher can decide volatility fee for each batch transaction
  allow_dynamic_fee: Bool,
}

pub type UpdatePoolParametersAction {
  UpdatePoolFee
  UpdateDynamicFee
  UpdatePoolStakeCredential
}

pub type PoolRedeemer {
  Batching
  UpdatePoolParameters { action: UpdatePoolParametersAction }
  WithdrawFeeSharing
}

pub type PoolBatchingRedeemer {
  // Index of the the batcher in authorized batchers list
  batcher_index: Int,
  // Batcher fee will be deducted from orders' fund. Batcher can decide the amount of fee for each order. The Batcher Fee can not exceed the maximum batcher fee.
  orders_fee: List<Int>,
  // The Indexes of Orders are processing
  input_indexes: ByteArray,
  // The Indexes of Pools are processing
  pool_input_indexes_opt: Option<ByteArray>,
  // The Volatility Fee for each Pool. Batcher can charge more fee to each batch through off-chain calculation and it's only affected if Pool enables `allow_dynamic_fee`
  vol_fees: List<Option<Int>>,
}

pub type SwapRouting {
  lp_asset: Asset,
  a_to_b_direction: Bool,
}

// Option when someone want to swap a token
pub type SwapAmountOption {
  // Swap a specific amount of token
  SAOSpecificAmount { swap_amount: Int }
  // Swap a all amount of the token that is available on the order's value
  // @deducted_amount will be subtract from the amount
  // This option is useful for integration where the creator doesn't know the exact amount that will be swapped
  SAOAll { deducted_amount: Int }
}

// Option when someone want to deposit tokens
pub type DepositAmountOption {
  // Deposit specific amount of tokens
  DAOSpecificAmount { deposit_amount_a: Int, deposit_amount_b: Int }
  // Deposit all amount of the tokens that are available on the order's value
  // @deducted_amount_a and @deducted_amount_b will be subtract from the amount
  // This option is useful for integration where the creator doesn't know the exact amount that will be deposited
  DAOAll { deducted_amount_a: Int, deducted_amount_b: Int }
}

// Option when someone want to withdraw tokens
pub type WithdrawAmountOption {
  // Withdraw specific amount of LP Token
  WAOSpecificAmount { withdrawal_lp_amount: Int }
  // Withdrawl all amount of the LP token that is available on the order's value
  // @deducted_amount_lp will be subtract from the amount
  // This option is useful for integration where the creator doesn't know the exact amount that will be withdrawn
  WAOAll { deducted_amount_lp: Int }
}

pub type OrderStep {
  // SwapExactIn is used for exchanging specific amount of single asset in the liquidity pool. 
  // The order will be executed if the received amount is greater than or equal to `minimum_receive`.
  SwapExactIn {
    // The AToB direction of swap request. True for A -> B and False for B -> A
    a_to_b_direction: Bool,
    // Amount of Asset In which users want to exchange
    swap_amount_option: SwapAmountOption,
    // Minimum amount of Asset Out which users want to receive after exchanging
    minimum_receive: Int,
    // Decide the Order behavior in case Order is not meet the slippage tolerance
    killable: Bool,
  }
  // StopLoss is used for exchanging specific amount of single asset in the liquidity pool.
  // The order will be executed if the received amount is less than or equal to `stop_loss_receive`
  StopLoss {
    // The AToB direction of swap request. True for A -> B and False for B -> A
    a_to_b_direction: Bool,
    // Amount of Asset In which users want to exchange
    swap_amount_option: SwapAmountOption,
    // Maximum amount of Asset Out which users want to receive after exchanging
    stop_loss_receive: Int,
  }
  // OCO is used for exchanging specific amount of single asset in the liquidity pool.
  // The order will be executed if the received amount is less than or equal to `stop_loss_receive` 
  //    and greater than or equal to `minimum_receive`
  OCO {
    // The AToB direction of swap request. True for A -> B and False for B -> A
    a_to_b_direction: Bool,
    // Amount of Asset In which users want to exchange
    swap_amount_option: SwapAmountOption,
    // Minimum amount of Asset Out which users want to receive after exchanging
    minimum_receive: Int,
    // Maximum amount of Asset Out which users want to receive after exchanging
    stop_loss_receive: Int,
  }
  // SwapExactOut is used for exchanging single asset in the liquidity pool and receiving the exact amout of other asset.
  // The order will be executed if the received amount is equal to `expected_receive`
  SwapExactOut {
    // The AToB direction of swap request. True for A -> B and False for B -> A 
    a_to_b_direction: Bool,
    // Maximum amount of Asset In which users want to exchange
    maximum_swap_amount_option: SwapAmountOption,
    // The exact amount of Asset Out which users want to receive after exchanging
    expected_receive: Int,
    // Decide the Order behavior in case Order is not meet the slippage tolerance
    killable: Bool,
  }
  // Deposit is used for depositing pool's assets and receiving LP Token
  Deposit {
    // Amount of Asset A and B which users want to deposit
    deposit_amount_option: DepositAmountOption,
    // The minimum amount of LP Token which users want to receive after depositing
    minimum_lp: Int,
    // Decide the Order behavior in case Order is not meet the slippage tolerance
    killable: Bool,
  }
  // Withdraw is used for withdrawing pool's asset with the exact assets ratio of the liquidity pool at that time
  Withdraw {
    // Amount of LP Asset which users want to withdraw
    withdrawal_amount_option: WithdrawAmountOption,
    // minimum received amounts of Asset A
    minimum_asset_a: Int,
    // minimum received amounts of Asset B
    minimum_asset_b: Int,
    // Decide the Order behavior in case Order is not meet the slippage tolerance
    killable: Bool,
  }
  // ZapOut is used for withdrawing a single pool asset out of Liquidity Pool
  ZapOut {
    // The AToB direction of ZapOut request. `True` in case Asset Out is B and vice versa
    a_to_b_direction: Bool,
    // Amount of LP Asset which users want to withdraw
    withdrawal_amount_option: WithdrawAmountOption,
    // Minimum amount of Asset Out which users want to receive after withdrawing
    minimum_receive: Int,
    // Decide the Order behavior in case Order is not meet the slippage tolerance
    killable: Bool,
  }
  // PartialSwap is used for exchange partial amount of single Asset. 
  // The Partial Swap can be executed multiple time if the price ratio is matched with user's expectation, 
  //   and the time is defined in `hops`
  PartialSwap {
    // The AToB direction of swap request. True for A -> B and False for B -> A
    a_to_b_direction: Bool,
    // Total amount of Asset In which users want to exchange 
    total_swap_amount: Int,
    // the price ratio which users want to exchange
    io_ratio_numerator: Int,
    io_ratio_denominator: Int,
    // The time PartialSwap can be executed
    hops: Int,
    // The minimum amount which is required to swap per each execution time
    minimum_swap_amount_required: Int,
    // Maximum fee that batcher can take to execute each time 
    max_batcher_fee_each_time: Int,
  }
  // WithdrawImbalance is used for withdrawing custom amount of assets.
  WithdrawImbalance {
    // Amount of LP Asset which users want to withdraw
    withdrawal_amount_option: WithdrawAmountOption,
    //  The ratio of Asset A and Asset B users want to receive after withdrawing
    ratio_asset_a: Int,
    ratio_asset_b: Int,
    // The minimum amount of asset A which users want to receive.
    // The amount of Asset will be followed by the ratio:
    //    (_received_asset_b_ = _minimum_asset_a_ * _ratio_asset_b_ / _ratio_asset_a_)
    minimum_asset_a: Int,
    // Decide the Order behavior in case Order is not meet the slippage tolerance
    killable: Bool,
  }
  // SwapMultiRouting is used for exchanging specific amount of single asset across multiple Liquidity Pools.
  SwapMultiRouting {
    // The routings (including a list of _direction_ and _lp_asset_), 
    // which is defined Liquidity Pools the swap is routing through
    routings: List<SwapRouting>,
    // Amount of Asset In which users want to exchange
    swap_amount_option: SwapAmountOption,
    // Minimum amount of Asset Out which users want to receive after exchanging
    minimum_receive: Int,
  }
  Donation
}

pub type ExtraOrderDatum {
  EODNoDatum
  EODDatumHash { hash: CustomDatumHash }
  EODInlineDatum { hash: CustomDatumHash }
}

// Authorization methods for an Order owner to unlock funds from the Order's Utxo
pub type OrderAuthorizationMethod {
  // Requires a signature from a PubKey wallet.
  OAMSignature { pub_key_hash: PubKeyHash }
  // For a Script-based wallet with a Spend method, the associated Utxo must be present in the transaction inputs.
  OAMSpendScript { script_hash: ValidatorHash }
  // For a Script-based wallet with a Withdrawal method, a corresponding withdrawal must be present in the transaction.
  OAMWithdrawScript { script_hash: ValidatorHash }
  // For a Script-based wallet with a Minting method, it must mint tokens with a defined policy ID, included in the transaction minting, with a non-zero quantity.
  OAMMintScript { script_hash: ValidatorHash }
}

pub type OrderDatum {
  // The address's payment credential that can cancel the order, can by PubKey or Script
  canceller: OrderAuthorizationMethod,
  // The address of the output after being killed by Batcher or cancelled by bots (order is expired)
  refund_receiver: Address,
  // The datum hash of the output after being killed by Batcher or cancelled by bots (order is expired)
  refund_receiver_datum: ExtraOrderDatum,
  // The address which receives the funds after order is processed
  success_receiver: Address,
  // The datum hash of the output after order is processed.
  success_receiver_datum: ExtraOrderDatum,
  // The Liquidity Pool's LP Asset that the order will be applied to
  lp_asset: Asset,
  // The information about Order Type
  step: OrderStep,
  // The maximum fee users have to pay to Batcher to execute batching transaction
  // The actual fee Batcher will take might be less than the maximum fee
  max_batcher_fee: Int,
  // expiry setting option contain
  // - Order Expired time: If the order is not executed after Expired Time, anyone can help the owner cancel it
  // - Max tip for cancelling expired order
  expiry_setting_opt: Option<(Int, Int)>,
}

pub type OrderRedeemer {
  ApplyOrder
  CancelOrderByOwner
  CancelExpiredOrderByAnyone
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
  DexInitialization
  CreatePool
}

// Defines authorization methods for interacting with Liquidity Pool settings and operations.
pub type PoolAuthorizationMethod {
  // Requires a signature from a PubKey wallet.
  PAMSignature { pub_key_hash: PubKeyHash }
  // For a Script-based wallet with a Spend method, the associated Utxo must be present in the transaction inputs.
  PAMSpendScript { script_hash: ValidatorHash }
  // For a Script-based wallet with a Withdrawal method, a corresponding withdrawal must be present in the transaction.
  PAMWithdrawScript { script_hash: ValidatorHash }
}

pub type BatchingPool {
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  trading_fee_a_numerator: Int,
  trading_fee_b_numerator: Int,
  fee_sharing_numerator_opt: Option<Int>,
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

// This setting grants permissions to authorized actors who can interact with Liquidity Pool features.
pub type GlobalSetting {
  // List of authorized batchers who can process orders.
  batchers: List<PoolAuthorizationMethod>,
  // The actor who can update the Pool's base fee and fee sharing.
  pool_fee_updater: PoolAuthorizationMethod,
  // The actor who can withdraw the Pool's fee sharing.
  fee_sharing_taker: PoolAuthorizationMethod,
  // The actor who can change the Pool's stake key.
  pool_stake_key_updater: PoolAuthorizationMethod,
  // The actor who can update the Pool's dynamic fee.
  pool_dynamic_fee_updater: PoolAuthorizationMethod,
  // The actor who can update the addresses mentioned above.
  // This admin can be transferred to another wallet and should be stored in the most secure location.
  admin: PoolAuthorizationMethod,
}
