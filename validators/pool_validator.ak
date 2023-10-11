use aiken/dict.{Dict}
use aiken/list
use aiken/transaction.{
  DatumHash, Input, NoDatum, Output, OutputReference, ScriptContext, Spend,
  Transaction,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{AssetName, PolicyId}
use amm_dex_v2/order_validation
use amm_dex_v2/pool_validation
use amm_dex_v2/types.{
  Asset, Batching, BatchingPool, CustomDatumHash, MultiRouting, OrderDatum,
  PoolDatum, PoolRedeemer, PoolState, SwapMultiRouting, UpdateFeeTo,
  WithdrawLiquidityShare,
}
use amm_dex_v2/utils

validator(
  authen_policy_id: PolicyId,
  license_policy_id: PolicyId,
  pool_auth_asset_name: AssetName,
  _admin_asset_name: AssetName,
  maximum_deadline_range: Int,
) {
  fn validate_pool(
    datum: PoolDatum,
    redeemer: PoolRedeemer,
    context: ScriptContext,
  ) {
    let ScriptContext { transaction, purpose } = context
    expect Spend(pool_input_ref) = purpose
    when redeemer is {
      Batching(batcher_address, input_indexes, license_index) -> {
        let Transaction {
          inputs,
          outputs,
          datums,
          extra_signatories,
          validity_range,
          mint,
          ..
        } = transaction
        expect
          pool_validation.validate_common_batching(
            inputs: inputs,
            validity_range: validity_range,
            extra_signatories: extra_signatories,
            batcher_address: batcher_address,
            license_policy_id: license_policy_id,
            license_index: license_index,
            maximum_deadline_range: maximum_deadline_range,
            mint: mint,
          )
        validate_batching(
          authen_policy_id: authen_policy_id,
          pool_auth_asset_name: pool_auth_asset_name,
          all_inputs: inputs,
          all_outputs: outputs,
          all_datums: datums,
          pool_input_ref: pool_input_ref,
          pool_in_datum: datum,
          batcher_address: batcher_address,
          input_indexes: input_indexes,
        )
      }
      MultiRouting(
        batcher_address,
        license_index,
        routing_in_indexes,
        routing_out_indexes,
      ) -> {
        let routing_in_indexes_len = list.length(routing_in_indexes)
        let routing_out_indexes_len = list.length(routing_out_indexes)
        // TODO: Validate distinct indexes
        expect
          routing_in_indexes_len == routing_out_indexes_len && routing_out_indexes_len >= 2
        let Transaction {
          inputs,
          outputs,
          datums,
          extra_signatories,
          validity_range,
          mint,
          ..
        } = transaction
        expect
          pool_validation.validate_common_batching(
            inputs: inputs,
            validity_range: validity_range,
            extra_signatories: extra_signatories,
            batcher_address: batcher_address,
            license_policy_id: license_policy_id,
            license_index: license_index,
            maximum_deadline_range: maximum_deadline_range,
            mint: mint,
          )
        validate_swap_multi_routing(
          authen_policy_id: authen_policy_id,
          pool_auth_asset_name: pool_auth_asset_name,
          all_inputs: inputs,
          all_outputs: outputs,
          all_datums: datums,
          pool_input_ref: pool_input_ref,
          batcher_address: batcher_address,
          routing_in_indexes: routing_in_indexes,
          routing_out_indexes: routing_out_indexes,
        )
      }
      UpdateFeeTo(_admin_index) -> True
      WithdrawLiquidityShare(_admin_index, _fee_to_index) -> True
    }
  }
}

fn find_pool_input_and_output_in_batching(
  pool_input_ref: OutputReference,
  inputs: List<Input>,
  outputs: List<Output>,
) -> (Input, Output) {
  let pool_inputs =
    list.filter(
      inputs,
      fn(input) {
        let Input { output_reference: out_ref, .. } = input
        pool_input_ref == out_ref
      },
    )
  expect [pool_input] = pool_inputs
  let Input { output: Output { address: pool_in_address, .. }, .. } = pool_input
  let Address { payment_credential: pool_payment_credential, .. } =
    pool_in_address
  let pool_outputs =
    list.filter(
      outputs,
      fn(output) {
        let Output { address: addr, .. } = output
        pool_in_address == addr
      },
    )

  // Batching transaction requires single Pool UTxO in both Inputs and Outputs
  expect [pool_output] = pool_outputs

  // Due to combination with Minswap Stake Address, Pool Contract can have multiple Base Addresses
  // This logic will verify that the transaction is processing in single Pool
  // Verify that having only one Pool Input and Pool Output in the transaction
  expect [_] =
    list.filter(
      inputs,
      fn(input) {
        let Input { output: o, .. } = input
        let Output { address: addr, .. } = o
        let Address { payment_credential: payment_cred, .. } = addr
        payment_cred == pool_payment_credential
      },
    )
  expect [_] =
    list.filter(
      outputs,
      fn(output) {
        let Output { address: addr, .. } = output
        let Address { payment_credential: payment_cred, .. } = addr
        payment_cred == pool_payment_credential
      },
    )
  (pool_input, pool_output)
}

fn get_batching_pool(
  pool_input: Input,
  pool_output: Output,
  authen_policy_id: PolicyId,
  pool_auth_asset_name: AssetName,
  pool_in_datum: PoolDatum,
) -> BatchingPool {
  let Input {
    output: Output { address: pool_in_address, value: pool_in_value, .. },
    ..
  } = pool_input
  let Output { value: pool_out_value, datum: pool_out_datum_raw, .. } =
    pool_output

  let PoolDatum {
    asset_a: pool_in_asset_a,
    asset_b: pool_in_asset_b,
    total_liquidity: pool_in_total_liquidity,
    root_k_last: pool_in_root_k_last,
    liquidity_share: pool_in_liquidity_share,
    trading_fee_numerator: pool_in_trading_fee_numerator,
    trading_fee_denominator: pool_in_trading_fee_denominator,
    order_hash: pool_in_order_hash,
    profit_sharing_opt: pool_in_profit_sharing_opt,
  } = pool_in_datum
  let pool_out_datum = utils.parse_pool_datum(pool_out_datum_raw)
  let PoolDatum {
    total_liquidity: pool_out_total_liquidity,
    root_k_last: pool_out_root_k_last,
    liquidity_share: pool_out_liquidity_share,
    ..
  } = pool_out_datum

  expect utils.verify_pool_datum_in_batch(pool_in_datum, pool_out_datum)
  let Asset { policy_id: asset_a_policy_id, asset_name: asset_a_asset_name } =
    pool_in_asset_a
  let Asset { policy_id: asset_b_policy_id, asset_name: asset_b_asset_name } =
    pool_in_asset_b
  let lp_asset_name =
    utils.compute_lp_asset_name(
      asset_a_policy_id,
      asset_a_asset_name,
      asset_b_policy_id,
      asset_b_asset_name,
    )
  let lp_asset =
    Asset { policy_id: authen_policy_id, asset_name: lp_asset_name }

  // Each Pool UTxO has a Pool Authen Asset (authen_policy_id + pool_auth_asset_name) 
  // This asset must be only stay in Pool UTxO
  // Verify Pool Authen Asset must be existed in Pool Input and Output value
  expect
    value.quantity_of(pool_in_value, authen_policy_id, pool_auth_asset_name) == 1
  expect
    value.quantity_of(pool_out_value, authen_policy_id, pool_auth_asset_name) == 1
  let temp_reserve_a_in =
    value.quantity_of(pool_in_value, asset_a_policy_id, asset_a_asset_name)
  let temp_reserve_a_out =
    value.quantity_of(pool_out_value, asset_a_policy_id, asset_a_asset_name)
  let (reserve_a_in, reserve_a_out) =
    if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
      (temp_reserve_a_in - 3000000, temp_reserve_a_out - 3000000)
    } else {
      (temp_reserve_a_in, temp_reserve_a_out)
    }
  let reserve_b_in =
    value.quantity_of(pool_in_value, asset_b_policy_id, asset_b_asset_name)
  let reserve_b_out =
    value.quantity_of(pool_out_value, asset_b_policy_id, asset_b_asset_name)

  let remaining_liquidity_supply_in =
    value.quantity_of(pool_in_value, authen_policy_id, lp_asset_name)
  let remaining_liquidity_supply_out =
    value.quantity_of(pool_out_value, authen_policy_id, lp_asset_name)

  let pool_state_in =
    PoolState {
      reserve_a: reserve_a_in,
      reserve_b: reserve_b_in,
      root_k_last: pool_in_root_k_last,
      total_liquidity: pool_in_total_liquidity,
      liquidity_share: pool_in_liquidity_share,
      remaining_liquidity_supply: remaining_liquidity_supply_in,
    }
  let pool_state_out =
    PoolState {
      reserve_a: reserve_a_out,
      reserve_b: reserve_b_out,
      root_k_last: pool_out_root_k_last,
      total_liquidity: pool_out_total_liquidity,
      liquidity_share: pool_out_liquidity_share,
      remaining_liquidity_supply: remaining_liquidity_supply_out,
    }
  BatchingPool {
    asset_a: pool_in_asset_a,
    asset_b: pool_in_asset_b,
    lp_asset,
    trading_fee_numerator: pool_in_trading_fee_numerator,
    trading_fee_denominator: pool_in_trading_fee_denominator,
    profit_sharing: pool_in_profit_sharing_opt,
    order_hash: pool_in_order_hash,
    address: pool_in_address,
    pool_state_in,
    pool_state_out,
  }
}

fn validate_batching(
  authen_policy_id: PolicyId,
  pool_auth_asset_name: AssetName,
  all_inputs: List<Input>,
  all_outputs: List<Output>,
  all_datums: Dict<CustomDatumHash, Data>,
  pool_input_ref: OutputReference,
  pool_in_datum: PoolDatum,
  batcher_address: Address,
  input_indexes: List<Int>,
) -> Bool {
  let (pool_input, pool_output) =
    find_pool_input_and_output_in_batching(
      pool_input_ref: pool_input_ref,
      inputs: all_inputs,
      outputs: all_outputs,
    )
  let BatchingPool {
    asset_a,
    asset_b,
    lp_asset,
    trading_fee_numerator,
    trading_fee_denominator,
    profit_sharing,
    order_hash,
    address: pool_address,
    pool_state_in,
    pool_state_out,
  } =
    get_batching_pool(
      pool_input: pool_input,
      pool_output: pool_output,
      authen_policy_id: authen_policy_id,
      pool_auth_asset_name: pool_auth_asset_name,
      pool_in_datum: pool_in_datum,
    )
  let user_inputs =
    list.filter(
      all_inputs,
      fn(input) {
        let Input { output: out, .. } = input
        let Output { address: addr, .. } = out
        let Address { payment_credential: payment_cred, .. } = addr
        when payment_cred is {
          ScriptCredential(hash) -> hash == order_hash
          _ -> False
        }
      },
    )
  let unique_input_indexes = list.unique(input_indexes)
  // Currently, transaction inputs will be sorted by TxId and TxIndex of UTxO.
  // We have to calculate indexes of orders inputs sorting by the ASC created time
  // on the off-chain and on-chain will sort the TxIns by the indexes
  // Input Indexes in parameter will be reversed indexs of @order_inputs to reduce calculate step in On-Chain
  let sorted_user_inputs =
    list.foldl(
      unique_input_indexes,
      [],
      fn(idx, ips) {
        list.push(ips, utils.must_parse_option(list.at(user_inputs, idx)))
      },
    )

  // Order Outputs are Outputs which aren't Pool & Batcher UTxOs
  // Their ordering must be the same with @sorted_order_inputs, so @order_outputs at index i is the output if @sorted_order_inputs at index i
  let user_outputs =
    list.filter(
      all_outputs,
      fn(output) {
        let Output { address: addr, .. } = output
        addr != pool_address && addr != batcher_address
      },
    )

  expect
    unique_input_indexes == input_indexes && // @input_indexes which is provided by Batcher must be unique array
    list.length(user_inputs) == list.length(unique_input_indexes) && // @input_indexes and @user_inputs must have the same length
    // User Inputs and Outputs must have the same length
    list.length(sorted_user_inputs) == list.length(user_outputs)
  expect list.length(sorted_user_inputs) == list.length(user_outputs)
  let PoolState {
    reserve_a: reserve_a_in,
    reserve_b: reserve_b_in,
    root_k_last: root_k_last_in,
    total_liquidity: total_liquidity_in,
    liquidity_share: liquidity_share_in,
    remaining_liquidity_supply: remaining_liquidity_supply_in,
  } = pool_state_in
  let PoolState {
    reserve_a: reserve_a_out,
    reserve_b: reserve_b_out,
    root_k_last: root_k_last_out,
    total_liquidity: total_liquidity_out,
    liquidity_share: liquidity_share_out,
    remaining_liquidity_supply: remaining_liquidity_supply_out,
  } = pool_state_out
  let (
    new_reserve_a,
    new_reserve_b,
    new_total_liquidity,
    new_liquidity_share,
    new_root_k_last,
  ) =
    order_validation.apply_orders(
      all_outputs: all_outputs,
      datum_dict: all_datums,
      asset_a: asset_a,
      asset_b: asset_b,
      lp_asset: lp_asset,
      trading_fee_numerator: trading_fee_numerator,
      trading_fee_denominator: trading_fee_denominator,
      profit_sharing_opt: profit_sharing,
      order_inputs: sorted_user_inputs,
      order_outputs: user_outputs,
      pool_state: (
        reserve_a_in,
        reserve_b_in,
        total_liquidity_in,
        liquidity_share_in,
        root_k_last_in,
      ),
    )

  let delta_total_liquidity = total_liquidity_out - total_liquidity_in
  let delta_remaining_liquidity_supply =
    remaining_liquidity_supply_in - remaining_liquidity_supply_out

  // Total Liquidity contains both share of Liquidity Provider and Minswap Labs
  // Batching transaction transfers Liquidity Provider share to their addresses and keep Minswap Labs share
  // Minswap Labs share is stored in @liquidity_share variable in Pool Datum 
  let is_liquidity_correct =
    delta_total_liquidity == delta_remaining_liquidity_supply

  // Validate the Pool State (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) must be the same with the calculated amount after applying through all orders
  expect
    new_reserve_a == reserve_a_out && // New Reserve A must be equals amount of Asset A in Pool Value
    new_reserve_b == reserve_b_out && // New Reserve B must be equals amount of Asset B in Pool Value
    new_total_liquidity == total_liquidity_out && // New Total Liquidity must be equals with @total_liquidity variable in Pool Out Datum
    new_liquidity_share == liquidity_share_out && // New Liquidity Share must be equals with @liquidity_share variable in Pool Out Datum
    new_root_k_last == root_k_last_out && // New RootKLast must be equals with @root_k_last variable in Pool Out Datum
    is_liquidity_correct
  True
}

fn validate_swap_multi_routing(
  authen_policy_id: PolicyId,
  pool_auth_asset_name: AssetName,
  all_inputs: List<Input>,
  all_outputs: List<Output>,
  all_datums: Dict<CustomDatumHash, Data>,
  pool_input_ref: OutputReference,
  batcher_address: Address,
  routing_in_indexes: List<Int>,
  routing_out_indexes: List<Int>,
) -> Bool {
  // 1. Find Pool Payment Credential
  // 2. Find all Pool Inputs and expect only 2 pool Inputs
  // 3. Find All Pool Outputs and expect only 2 Pool Outputs
  // 4. Find SwapMultiRouting Order and expect only 1 Order
  // 5. Verify that LP Asset of 2 Pools in order is matched
  // 6. Detect Pool 1 & Pool 2 of these pools above and apply Order via them
  let batching_pools =
    find_multi_routing_pools(
      authen_policy_id: authen_policy_id,
      pool_auth_asset_name: pool_auth_asset_name,
      pool_input_ref: pool_input_ref,
      inputs: all_inputs,
      outputs: all_outputs,
      routing_in_indexes: routing_in_indexes,
      routing_out_indexes: routing_out_indexes,
    )

  let BatchingPool {
    order_hash,
    address: Address { payment_credential: pool_payment_credential, .. },
    lp_asset: pool_lp_asset,
    ..
  } = utils.list_at_index(batching_pools, 0)

  let order_inputs =
    list.filter(
      all_inputs,
      fn(input) {
        let Input {
          output: Output {
            address: Address { payment_credential: payment_cred, .. },
            ..
          },
          ..
        } = input
        when payment_cred is {
          ScriptCredential(hash) -> hash == order_hash
          _ -> False
        }
      },
    )
  expect [order_input] = order_inputs
  let order_outputs =
    list.filter(
      all_outputs,
      fn(output) {
        let Output { address: addr, .. } = output
        let Address { payment_credential: payment_cred, .. } = addr
        addr != batcher_address && payment_cred != pool_payment_credential
      },
    )
  expect [order_output] = order_outputs
  let Input { output: order_in_output, .. } = order_input
  let Output { value: order_in_value, .. } = order_in_output
  let Output {
    value: order_out_value,
    address: output_address,
    datum: order_output_datum,
    ..
  } = order_output
  let OrderDatum {
    receiver,
    receiver_datum_hash_opt,
    step: order_step,
    batcher_fee,
    output_ada,
    lp_asset: order_lp_asset,
    ..
  } = utils.must_find_order_datum(all_outputs, all_datums, order_in_output)
  let is_valid_receiver_datum_hash =
    when receiver_datum_hash_opt is {
      Some(datum_hash) -> {
        expect DatumHash(output_datum_hash) = order_output_datum
        output_datum_hash == datum_hash
      }
      None -> order_output_datum == NoDatum
    }
  expect
    receiver == output_address && batcher_fee > 0 && output_ada > 0 && is_valid_receiver_datum_hash && pool_lp_asset == order_lp_asset
  when order_step is {
    SwapMultiRouting(routings, minimum_receive) -> {
      expect minimum_receive > 0
      order_validation.validate_swap_multi_routing_order(
        pools: batching_pools,
        routings: routings,
        order_in_value: order_in_value,
        order_out_value: order_out_value,
        minimum_receive: minimum_receive,
        batcher_fee: batcher_fee,
        output_ada: output_ada,
      )
    }
    _ -> False
  }
}

// TODO: We need carefully verify these logic below 
fn find_multi_routing_pools(
  authen_policy_id: PolicyId,
  pool_auth_asset_name: AssetName,
  pool_input_ref: OutputReference,
  inputs: List<Input>,
  outputs: List<Output>,
  routing_in_indexes: List<Int>,
  routing_out_indexes: List<Int>,
) -> List<BatchingPool> {
  let pool_ins =
    list.map(routing_in_indexes, fn(idx) { utils.list_at_index(inputs, idx) })

  let pool_outs =
    list.map(routing_out_indexes, fn(idx) { utils.list_at_index(outputs, idx) })

  let pool_len = list.length(pool_ins)

  // find input of current script
  expect [own_pool_input] =
    list.filter(
      inputs,
      fn(input) {
        let Input { output_reference: out_ref, .. } = input
        pool_input_ref == out_ref
      },
    )
  let Input {
    output: Output {
      address: Address { payment_credential: own_pool_payment_credential, .. },
      ..
    },
    ..
  } = own_pool_input
  // verify that there's only 2 pools the inputs
  expect
    list.length(
      list.filter(
        inputs,
        fn(input) {
          let Input {
            output: Output { address: Address { payment_credential, .. }, .. },
            ..
          } = input
          payment_credential == own_pool_payment_credential
        },
      ),
    ) == pool_len
  // verify that there's only 2 pools the outputs
  expect
    list.length(
      list.filter(
        outputs,
        fn(output) {
          let Output { address: Address { payment_credential, .. }, .. } =
            output
          payment_credential == own_pool_payment_credential
        },
      ),
    ) == pool_len
  utils.zip_with(
    pool_ins,
    pool_outs,
    fn(pool_in, pool_out) {
      let Input {
        output: Output {
          address: pool_in_address,
          datum: pool_in_datum_raw,
          ..
        },
        ..
      } = pool_in
      let Output { address: pool_out_address, datum: pool_out_datum_raw, .. } =
        pool_out
      let pool_in_datum = utils.parse_pool_datum(pool_in_datum_raw)
      let pool_out_datum = utils.parse_pool_datum(pool_out_datum_raw)

      expect
        pool_in_address == pool_out_address && // hehe
        utils.compare_pool_datum(pool_in_datum, pool_out_datum)
      get_batching_pool(
        pool_input: pool_in,
        pool_output: pool_out,
        authen_policy_id: authen_policy_id,
        pool_auth_asset_name: pool_auth_asset_name,
        pool_in_datum: pool_in_datum,
      )
    },
  )
}
