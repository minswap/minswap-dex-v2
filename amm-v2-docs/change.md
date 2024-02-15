# Different between V1 & V2
### Pool Creation & LP Token Minting

- V1: Pool Creation on V1 is permission.
  - only the wallet that has "Pool Owner" Token can create liquidity pool via `Factory Minting Contract`
  - LP Token will be minted based on demand via Batching Transaction and `LP Minting Contract` is triggered every transaction. However `LP Minting Contract` doesn't know about `Pool Contract` so it's relied on `NFT Token`, and if `NFT Token` is malicious then `LP Minting Contract` can be attacked
- V2: Pool Creation on V2 is permissionless.
  - Liquidity Pool can be created via `Factory Contract`. Each transaction requires an `Factory UTxO` in the input and separate it into 2 UTxOs. You can checkout Section 3.4.1 and 3.4.2 in the Specification document for more details of how and why we do it
  - LP Token will be minted with maximum amount (maximum of Int64) in this transaction and cannot be minted more after Pool is created.

### Batching

Batching mechanism is almost the same between 2 versions. We only apply some small updates to make the mechanism be composable with our further intention 
- V1: 
  - Batching transaction requires "Batcher" address that owns valid `License Token`
  - Batcher Fee is fixed in the Order
  - Order that is over slippage will be rejected
  - Profit Sharing is accumulated in LP token and follow the calculation of Uniswap
- V2: 
  - Batching transaction requires any address that owns valid `License Token`
  - Executed batcher Fee can be smaller than Batcher Fee in Order, batcher can choose any batcher fee for each order and must follow the rule 0 < Executed batcher Fee <= Order through `orders_fee`
  - Order that is over slippage can be refund to sender if Order allow `Killable`
  - Profit Sharing is accumulated in Token A and Token B. It is calculated in every transaction that changes the Pool price. It's a reason why we separate `Pool reserve` into 2 parts:
    - datum reserves: represent for user liquidity
    - value reserves: represent for user liquidity and earned Profit Sharing
  - New script `validate_order_spending` must be presented in batching transaction to reduce `Order script` cost. This is a trick of `Withdrawal Purpose` that allow triggering validation logic even transaction withdraws 0 ADA. 
  
### MultiRouting

This is new mechanism on V2, transaction only applies `SwapMultiRouting` order across multiple liquidity pools. 

### Transaction related to Admin

- UpdatePoolFeeOrStakeCredential
- WithdrawLiquidityShare

The mechanism is not much different with the V1, allow Admin adjusting some Pool parameters and withdrawing earned Profit Sharing. 

### Order Type

We introduce more Order types to increase users/traders experience. You can checkout Section 3.2.2 in the Specification document for more details about their use cases

Along with new order types, here are some extra options of creating an order:
- `sender_datum_hash_opt`: Datum hash of sender, to support Script Address interact with our system
- `lp_asset`: to specify Liquidity Pool that order is belonged to
- `max_batcher_fee`: Maximum batcher fee that can be deducted by Batcher
- `expiry_setting_opt`: allow users choosing expired time of the order.
  - 1st parameter is expired time in milliseconds
  - 2nd parameter is a maximum fee that a canceller can take if he helps user cancel the order
- We provide specific amount represents for the exact amount users want to interact with Liquidity Pool in the `OrderStep` such as `swap_amount`, `maximum_swap_amount`, ... Users can put more tokens into the orders and specify the amount, then batcher only interacts with these amount and returns the rest amount + result amount (result of swap, deposit, ...) to `receiver`
- `killable`: is an option that allow batcher returns funds to `sender` in case slippage is not met 