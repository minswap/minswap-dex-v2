use aiken/dict.{Dict}
use aiken/hash.{Blake2b_256, Hash}
use aiken/list
use aiken/transaction.{
  DatumHash, Input, NoDatum, Output, OutputReference, ScriptContext, Spend,
  Transaction,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{
  AssetName, PolicyId, Value, ada_asset_name, ada_policy_id,
}
use amm_dex_v2/math
use amm_dex_v2/types.{
  Asset, Batching, Deposit, MultiRouting, OrderDatum, PoolDatum, PoolRedeemer,
  ProfitSharing, SwapExactIn, SwapExactOut, UpdateFeeTo, Withdraw,
  WithdrawLiquidityShare, ZapIn, ZapOut,
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
      Batching(batcher_address, input_indexes, license_index) ->
        validate_batching(
          authen_policy_id: authen_policy_id,
          license_policy_id: license_policy_id,
          pool_auth_asset_name: pool_auth_asset_name,
          maximum_deadline_range: maximum_deadline_range,
          transaction: transaction,
          pool_input_ref: pool_input_ref,
          pool_in_datum: datum,
          batcher_address: batcher_address,
          input_indexes: input_indexes,
          license_index: license_index,
        )
      MultiRouting(_batcher_address, _license_index) -> True
      UpdateFeeTo(_admin_index) -> True
      WithdrawLiquidityShare(_admin_index, _fee_to_index) -> True
    }
  }
}

fn validate_batching(
  authen_policy_id: PolicyId,
  license_policy_id: PolicyId,
  pool_auth_asset_name: AssetName,
  maximum_deadline_range: Int,
  transaction: Transaction,
  pool_input_ref: OutputReference,
  pool_in_datum: PoolDatum,
  batcher_address: Address,
  input_indexes: List<Int>,
  license_index: Int,
) -> Bool {
  let Transaction {
    inputs,
    outputs,
    extra_signatories,
    validity_range,
    mint,
    datums,
    ..
  } = transaction
  let pool_inputs =
    list.filter(
      inputs,
      fn(input) {
        let Input { output_reference: out_ref, .. } = input
        pool_input_ref == out_ref
      },
    )
  expect [pool_input] = pool_inputs
  let Input { output: pool_in_output, .. } = pool_input
  let Output { address: pool_in_address, value: pool_in_value, .. } =
    pool_in_output
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
  let Output { value: pool_out_value, datum: pool_out_datum_raw, .. } =
    pool_output

  // Due to combination with Minswap Stake Address, Pool Contract can have multiple Base Addresses
  // This logic will verify that the transaction is processing in single Pool
  //Verify that having only one Pool Input and Pool Output in the transaction
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
  let PoolDatum {
    asset_a: pool_out_asset_a,
    asset_b: pool_out_asset_b,
    total_liquidity: pool_out_total_liquidity,
    root_k_last: pool_out_root_k_last,
    liquidity_share: pool_out_liquidity_share,
    trading_fee_numerator: pool_out_trading_fee_numerator,
    trading_fee_denominator: pool_out_trading_fee_denominator,
    order_hash: pool_out_order_hash,
    profit_sharing_opt: pool_out_profit_sharing_opt,
  } = utils.parse_pool_datum(pool_out_datum_raw)

  // A set of variables in Pool Datum must be unchanged in this transaction
  expect
    pool_in_asset_a == pool_out_asset_a && pool_in_asset_b == pool_out_asset_b && // Asset A & B must be unchanged
    pool_in_trading_fee_numerator == pool_out_trading_fee_numerator && pool_in_trading_fee_denominator == pool_out_trading_fee_denominator && // Trading Fee config must be unchanged
    pool_in_order_hash == pool_out_order_hash && // Order Hash config must be unchanged
    pool_in_profit_sharing_opt == pool_out_profit_sharing_opt
  //^ Profit Sharing config must be unchanged
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

  // Each Pool UTxO has a Pool Authen Asset (authen_policy_id + pool_auth_asset_name) 
  // This asset must be only stay in Pool UTxO
  // Verify Pool Authen Asset must be existed in Pool Input and Output value
  expect
    value.quantity_of(pool_in_value, authen_policy_id, pool_auth_asset_name) == 1
  expect
    value.quantity_of(pool_out_value, authen_policy_id, pool_auth_asset_name) == 1
  // Batching Redeemer provides @license_index which help save calculation cost
  let license_input = utils.must_parse_option(list.at(inputs, license_index))
  let license_deadline =
    utils.find_license_deadline(license_policy_id, license_input.output.value)
  let (start_valid_time_range, end_valid_time_range) =
    utils.find_posix_time_range(validity_range)
  // - Only Batcher with valid license token can trigger @ApplyPool redeemer validation.  
  // - A valid license token is the token with @tokenName (representing for expired milliseconds) 
  //   and must be within the time range from current_time to current_time + maximum_deadline_range
  let Address { payment_credential: batcher_payment_credential, .. } =
    batcher_address
  expect VerificationKeyCredential(batcher_pkh) = batcher_payment_credential
  // Verify Batcher with valid license token must be a signer of transaction
  expect
    list.has(extra_signatories, batcher_pkh) && license_deadline >= end_valid_time_range && license_deadline <= start_valid_time_range + maximum_deadline_range
  let order_inputs =
    list.filter(
      inputs,
      fn(input) {
        let Input { output: out, .. } = input
        let Output { address: addr, .. } = out
        let Address { payment_credential: payment_cred, .. } = addr
        when payment_cred is {
          ScriptCredential(hash) -> hash == pool_in_order_hash
          _ -> False
        }
      },
    )
  // Currently, transaction inputs will be sorted by TxId and TxIndex of UTxO.
  // We have to calculate indexes of orders inputs sorting by the ASC created time
  // on the off-chain and on-chain will sort the TxIns by the indexes
  // Input Indexes in parameter will be reversed indexs of @order_inputs to reduce calculate step in On-Chain
  let sorted_order_inputs =
    list.foldl(
      input_indexes,
      [],
      fn(idx, ips) {
        list.push(ips, utils.must_parse_option(list.at(order_inputs, idx)))
      },
    )

  // Order Outputs are Outputs which aren't Pool & Batcher UTxOs
  // Their ordering must be the same with @sorted_order_inputs, so @order_outputs at index i is the output if @sorted_order_inputs at index i
  let order_outputs =
    list.filter(
      outputs,
      fn(output) {
        let Output { address: addr, .. } = output
        addr != pool_in_address && addr != batcher_address
      },
    )
  let reserve_a_in =
    value.quantity_of(pool_in_value, asset_a_policy_id, asset_a_asset_name)
  let reserve_a_out =
    value.quantity_of(pool_out_value, asset_a_policy_id, asset_a_asset_name)
  let reserve_b_in =
    value.quantity_of(pool_in_value, asset_b_policy_id, asset_b_asset_name)
  let reserve_b_out =
    value.quantity_of(pool_out_value, asset_b_policy_id, asset_b_asset_name)

  let total_liquidity_in =
    value.quantity_of(pool_in_value, authen_policy_id, lp_asset_name)
  let total_liquidity_out =
    value.quantity_of(pool_out_value, authen_policy_id, lp_asset_name)
  let lp_asset =
    Asset { policy_id: authen_policy_id, asset_name: lp_asset_name }
  expect list.length(sorted_order_inputs) == list.length(order_outputs)
  let (
    new_reserve_a,
    new_reserve_b,
    new_total_liquidity,
    new_liquidity_share,
    new_root_k_last,
  ) =
    apply_orders(
      all_outputs: outputs,
      datum_dict: datums,
      asset_a: pool_in_asset_a,
      asset_b: pool_in_asset_b,
      lp_asset: lp_asset,
      trading_fee_numerator: pool_in_trading_fee_numerator,
      trading_fee_denominator: pool_in_trading_fee_denominator,
      profit_sharing_opt: pool_in_profit_sharing_opt,
      order_inputs: sorted_order_inputs,
      order_outputs: order_outputs,
      pool_state: (
        reserve_a_in,
        reserve_b_in,
        pool_in_total_liquidity,
        pool_in_liquidity_share,
        pool_in_root_k_last,
      ),
    )

  let delta_total_liquidity = pool_out_total_liquidity - pool_in_total_liquidity
  let delta_liquidity_share = pool_out_liquidity_share - pool_in_liquidity_share
  let delta_liquidity_in_pool_value = total_liquidity_in - total_liquidity_out

  // Total Liquidity contains both share of Liquidity Provider and Minswap Labs
  // Batching transaction transfers Liquidity Provider share to their addresses and keep Minswap Labs share
  // Minswap Labs share is stored in @liquidity_share variable in Pool Datum 
  let is_liquidity_correct =
    delta_total_liquidity == delta_liquidity_share + delta_liquidity_in_pool_value

  // Validate the Pool State (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) must be the same with the calculated amount after applying through all orders
  expect
    new_reserve_a == reserve_a_out && // New Reserve A must be equals amount of Asset A in Pool Value
    new_reserve_b == reserve_b_out && // New Reserve B must be equals amount of Asset B in Pool Value
    new_total_liquidity == pool_out_total_liquidity && // New Total Liquidity must be equals with @total_liquidity variable in Pool Out Datum
    new_liquidity_share == pool_out_liquidity_share && // New Liquidity Share must be equals with @liquidity_share variable in Pool Out Datum
    new_root_k_last == pool_out_root_k_last && // New RootKLast must be equals with @root_k_last variable in Pool Out Datum
    is_liquidity_correct
  let mint_value = value.from_minted_value(mint)
  expect [] = value.flatten(mint_value)
  True
}

fn find_order_datum(
  outputs: List<Output>,
  datums: Dict<Hash<Blake2b_256, Data>, Data>,
  output: Output,
) -> OrderDatum {
  expect order_datum: OrderDatum =
    utils.must_find_script_datum(outputs, datums, output)
  order_datum
}

fn apply_orders(
  all_outputs: List<Output>,
  datum_dict: Dict<Hash<Blake2b_256, Data>, Data>,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  profit_sharing_opt: Option<ProfitSharing>,
  order_inputs: List<Input>,
  order_outputs: List<Output>,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  when order_inputs is {
    [] -> pool_state
    [input, ..inputs] ->
      when order_outputs is {
        [] -> pool_state
        [output, ..outputs] -> {
          let Input { output: order_in_output, .. } = input
          let Output { value: order_in_value, .. } = order_in_output
          let Output {
            value: order_out_value,
            address: output_address,
            datum: order_output_datum,
            ..
          } = output
          let OrderDatum {
            receiver,
            receiver_datum_hash_opt,
            step: order_step,
            batcher_fee,
            output_ada,
            lp_asset: order_lp_asset,
            ..
          } = find_order_datum(all_outputs, datum_dict, order_in_output)
          let is_valid_receiver_datum_hash =
            when receiver_datum_hash_opt is {
              Some(datum_hash) -> {
                expect DatumHash(output_datum_hash) = order_output_datum
                output_datum_hash == datum_hash
              }
              None -> order_output_datum == NoDatum
            }
          expect
            receiver == output_address && batcher_fee > 0 && output_ada > 0 && is_valid_receiver_datum_hash && lp_asset == order_lp_asset
          let new_state =
            when order_step is {
              SwapExactIn(a_to_b_direction, minimum_receive) ->
                validate_swap_exact_in(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  a_to_b_direction: a_to_b_direction,
                  minimum_receive: minimum_receive,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  batcher_fee: batcher_fee,
                  output_ada: output_ada,
                  trading_fee_numerator: trading_fee_numerator,
                  trading_fee_denominator: trading_fee_denominator,
                  pool_state: pool_state,
                )
              SwapExactOut(a_to_b_direction, expected_receive) ->
                validate_swap_exact_out(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  a_to_b_direction: a_to_b_direction,
                  expected_receive: expected_receive,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  batcher_fee: batcher_fee,
                  output_ada: output_ada,
                  trading_fee_numerator: trading_fee_numerator,
                  trading_fee_denominator: trading_fee_denominator,
                  pool_state: pool_state,
                )
              Deposit(minimum_lp) ->
                validate_deposit(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  minimum_lp: minimum_lp,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  lp_asset: lp_asset,
                  batcher_fee: batcher_fee,
                  output_ada: output_ada,
                  profit_sharing_opt: profit_sharing_opt,
                  pool_state: pool_state,
                )
              Withdraw(minimum_asset_a, minimum_asset_b) ->
                validate_withdraw(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  minimum_amount_a: minimum_asset_a,
                  minimum_amount_b: minimum_asset_b,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  lp_asset: lp_asset,
                  output_ada: output_ada,
                  profit_sharing_opt: profit_sharing_opt,
                  pool_state: pool_state,
                )
              ZapIn(a_to_b_direction, minimum_lp) ->
                validate_zap_in(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  minimum_lp: minimum_lp,
                  a_to_b_direction: a_to_b_direction,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  lp_asset: lp_asset,
                  batcher_fee: batcher_fee,
                  output_ada: output_ada,
                  profit_sharing_opt: profit_sharing_opt,
                  trading_fee_numerator: trading_fee_numerator,
                  trading_fee_denominator: trading_fee_denominator,
                  pool_state: pool_state,
                )
              ZapOut(a_to_b_direction, minimum_receive) ->
                validate_zap_out(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  minimum_receive: minimum_receive,
                  a_to_b_direction: a_to_b_direction,
                  asset_a: asset_a,
                  asset_b: asset_b,
                  lp_asset: lp_asset,
                  output_ada: output_ada,
                  profit_sharing_opt: profit_sharing_opt,
                  trading_fee_numerator: trading_fee_numerator,
                  trading_fee_denominator: trading_fee_denominator,
                  pool_state: pool_state,
                )
            }
          apply_orders(
            all_outputs: all_outputs,
            datum_dict: datum_dict,
            asset_a: asset_a,
            asset_b: asset_b,
            lp_asset: lp_asset,
            trading_fee_numerator: trading_fee_numerator,
            trading_fee_denominator: trading_fee_denominator,
            profit_sharing_opt: profit_sharing_opt,
            order_inputs: inputs,
            order_outputs: outputs,
            pool_state: new_state,
          )
        }
      }
  }
}

fn validate_swap_exact_in(
  order_in_value: Value,
  order_out_value: Value,
  a_to_b_direction: Bool,
  minimum_receive: Int,
  asset_a: Asset,
  asset_b: Asset,
  batcher_fee: Int,
  output_ada: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  let (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) =
    pool_state
  let (asset_in, asset_out, reserve_in, reserve_out) =
    if a_to_b_direction {
      (asset_a, asset_b, reserve_a, reserve_b)
    } else {
      (asset_b, asset_a, reserve_b, reserve_a)
    }
  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let temp_amount_in =
    value.quantity_of(order_in_value, asset_in_policy_id, asset_in_asset_name)
  let amount_in =
    if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
      temp_amount_in - ( batcher_fee + output_ada )
    } else {
      temp_amount_in
    }
  let has_enough_amount_in = amount_in > 0
  let amount_out =
    math.calculate_amount_out(
      reserve_in,
      reserve_out,
      amount_in,
      trading_fee_numerator,
      trading_fee_denominator,
    )
  let not_over_slippage = amount_out >= minimum_receive
  let actual_amount_out =
    value.quantity_of(
      order_out_value,
      asset_out_policy_id,
      asset_out_asset_name,
    )
  let is_valid_amount_out =
    if utils.is_ada_asset(asset_out_policy_id, asset_out_asset_name) {
      amount_out + output_ada == actual_amount_out
    } else {
      let ada_amount =
        value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
      amount_out == actual_amount_out && ada_amount == output_ada
    }
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  if a_to_b_direction {
    (
      reserve_a + amount_in,
      reserve_b - amount_out,
      total_liquidity,
      liquidity_share,
      root_k_last,
    )
  } else {
    (
      reserve_a - amount_out,
      reserve_b + amount_in,
      total_liquidity,
      liquidity_share,
      root_k_last,
    )
  }
}

fn validate_swap_exact_out(
  order_in_value: Value,
  order_out_value: Value,
  a_to_b_direction: Bool,
  expected_receive: Int,
  asset_a: Asset,
  asset_b: Asset,
  batcher_fee: Int,
  output_ada: Int,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  let (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) =
    pool_state
  let (asset_in, asset_out, reserve_in, reserve_out) =
    if a_to_b_direction {
      (asset_a, asset_b, reserve_a, reserve_b)
    } else {
      (asset_b, asset_a, reserve_b, reserve_a)
    }
  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let temp_amount_in =
    value.quantity_of(order_in_value, asset_in_policy_id, asset_in_asset_name)
  let maximum_amount_in =
    if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
      temp_amount_in - ( batcher_fee + output_ada )
    } else {
      temp_amount_in
    }
  let has_enough_amount_in = maximum_amount_in > 0
  let necessary_amount_in_opt =
    math.calculate_amount_in(
      reserve_in,
      reserve_out,
      expected_receive,
      trading_fee_numerator,
      trading_fee_denominator,
    )
  let necessary_amount_in = utils.must_parse_option(necessary_amount_in_opt)
  let not_over_slippage = necessary_amount_in <= maximum_amount_in
  let actual_amount_out =
    value.quantity_of(
      order_out_value,
      asset_out_policy_id,
      asset_out_asset_name,
    )
  let ada_amount =
    value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
  let change_amount_in =
    value.quantity_of(order_out_value, asset_in_policy_id, asset_in_asset_name)
  let is_valid_amount_out =
    if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
      actual_amount_out == expected_receive && ada_amount == output_ada + maximum_amount_in - necessary_amount_in
    } else if
    utils.is_ada_asset(asset_out_policy_id, asset_out_asset_name){
    
      actual_amount_out == expected_receive + output_ada && change_amount_in == maximum_amount_in - necessary_amount_in
    } else {
      actual_amount_out == expected_receive && change_amount_in == maximum_amount_in - necessary_amount_in && ada_amount == output_ada
    }
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  if a_to_b_direction {
    (
      reserve_a + necessary_amount_in,
      reserve_b - expected_receive,
      total_liquidity,
      liquidity_share,
      root_k_last,
    )
  } else {
    (
      reserve_a - expected_receive,
      reserve_b + necessary_amount_in,
      total_liquidity,
      liquidity_share,
      root_k_last,
    )
  }
}

fn validate_deposit(
  order_in_value: Value,
  order_out_value: Value,
  minimum_lp: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  batcher_fee: Int,
  output_ada: Int,
  profit_sharing_opt: Option<ProfitSharing>,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  let (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) =
    pool_state
  let Asset { policy_id: asset_a_policy_id, asset_name: asset_a_asset_name } =
    asset_a
  let Asset { policy_id: asset_b_policy_id, asset_name: asset_b_asset_name } =
    asset_b
  let Asset { policy_id: lp_asset_policy_id, asset_name: lp_asset_asset_name } =
    lp_asset
  let temp_amount_a =
    value.quantity_of(order_in_value, asset_a_policy_id, asset_a_asset_name)
  let temp_amount_b =
    value.quantity_of(order_in_value, asset_b_policy_id, asset_b_asset_name)
  let amount_a =
    if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
      temp_amount_a - ( batcher_fee + output_ada )
    } else {
      temp_amount_a
    }
  let amount_b =
    if utils.is_ada_asset(asset_b_policy_id, asset_b_asset_name) {
      temp_amount_b - ( batcher_fee + output_ada )
    } else {
      temp_amount_b
    }
  let has_enough_amount_in = amount_a > 0 && amount_b > 0
  let (necessary_a, necessary_b, delta_liquidity) =
    utils.must_parse_option(
      math.calculate_deposit_amount(
        amount_a,
        amount_b,
        reserve_a,
        reserve_b,
        total_liquidity,
      ),
    )
  let not_over_slippage = delta_liquidity >= minimum_lp
  let lp_amount_out =
    value.quantity_of(order_out_value, lp_asset_policy_id, lp_asset_asset_name)
  let ada_amount_out =
    value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
  let change_amount_a =
    value.quantity_of(order_out_value, asset_a_policy_id, asset_a_asset_name)
  let change_amount_b =
    value.quantity_of(order_out_value, asset_b_policy_id, asset_b_asset_name)

  let is_valid_amount_out =
    if amount_a > necessary_a {
      if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
        ada_amount_out == amount_a - necessary_a + output_ada && lp_amount_out == delta_liquidity
      } else {
        ada_amount_out == output_ada && lp_amount_out == delta_liquidity && change_amount_a == amount_a - necessary_a
      }
    } else if amount_b > necessary_b {
      if utils.is_ada_asset(asset_b_policy_id, asset_b_asset_name) {
        ada_amount_out == amount_b - necessary_b + output_ada && lp_amount_out == delta_liquidity
      } else {
        ada_amount_out == output_ada && lp_amount_out == delta_liquidity && change_amount_b == amount_b - necessary_b
      }
    } else {
      ada_amount_out == output_ada && lp_amount_out == delta_liquidity
    }

  let new_reserve_a = reserve_a + necessary_a
  let new_reserve_b = reserve_b + necessary_b

  let (delta_liquidity_share, new_root_k_last) =
    when profit_sharing_opt is {
      Some(profit_sharing) -> {
        let ProfitSharing { fee_sharing_numerator, fee_sharing_denominator, .. } =
          profit_sharing
        let delta_liquidity_share =
          math.calculate_profit_sharing(
            root_k_last,
            reserve_a * reserve_b,
            total_liquidity,
            fee_sharing_numerator,
            fee_sharing_denominator,
          )
        let new_root_k_last = math.calculate_sqrt(new_reserve_a * new_reserve_b)
        (delta_liquidity_share, new_root_k_last)
      }
      None -> (0, root_k_last)
    }
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  (
    new_reserve_a,
    new_reserve_b,
    total_liquidity + delta_liquidity + delta_liquidity_share,
    liquidity_share + delta_liquidity_share,
    new_root_k_last,
  )
}

fn validate_withdraw(
  order_in_value: Value,
  order_out_value: Value,
  minimum_amount_a: Int,
  minimum_amount_b: Int,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  output_ada: Int,
  profit_sharing_opt: Option<ProfitSharing>,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  let (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) =
    pool_state
  let Asset { policy_id: asset_a_policy_id, asset_name: asset_a_asset_name } =
    asset_a
  let Asset { policy_id: asset_b_policy_id, asset_name: asset_b_asset_name } =
    asset_b
  let Asset { policy_id: lp_policy_id, asset_name: lp_asset_name } = lp_asset
  let withdrawal_lp_amount =
    value.quantity_of(order_in_value, lp_policy_id, lp_asset_name)
  let has_enough_amount_in = withdrawal_lp_amount > 0
  let (amount_a_out, amount_b_out) =
    math.calculate_withdraw(
      reserve_a,
      reserve_b,
      withdrawal_lp_amount,
      total_liquidity,
    )
  let not_over_slippage =
    amount_a_out >= minimum_amount_a && amount_b_out >= minimum_amount_b
  let actual_amount_a_out =
    value.quantity_of(order_out_value, asset_a_policy_id, asset_a_asset_name)
  let actual_amount_b_out =
    value.quantity_of(order_out_value, asset_b_policy_id, asset_b_asset_name)
  let ada_amount_out =
    value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
  let is_valid_amount_out =
    if utils.is_ada_asset(asset_a_policy_id, asset_a_asset_name) {
      actual_amount_a_out == amount_a_out + output_ada && actual_amount_b_out == amount_b_out
    } else if
    utils.is_ada_asset(asset_b_policy_id, asset_b_asset_name){
    
      actual_amount_b_out == amount_b_out + output_ada && actual_amount_a_out == amount_a_out
    } else {
      ada_amount_out == output_ada && actual_amount_a_out == amount_a_out && actual_amount_b_out == amount_b_out
    }
  let new_reserve_a = reserve_a - amount_a_out
  let new_reserve_b = reserve_b - amount_b_out
  let (delta_liquidity_share, new_root_k_last) =
    when profit_sharing_opt is {
      Some(profit_sharing) -> {
        let ProfitSharing { fee_sharing_numerator, fee_sharing_denominator, .. } =
          profit_sharing
        let delta_liquidity_share =
          math.calculate_profit_sharing(
            root_k_last,
            reserve_a * reserve_b,
            total_liquidity,
            fee_sharing_numerator,
            fee_sharing_denominator,
          )
        let new_root_k_last = math.calculate_sqrt(new_reserve_a * new_reserve_b)
        (delta_liquidity_share, new_root_k_last)
      }
      None -> (0, root_k_last)
    }
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  (
    new_reserve_a,
    new_reserve_b,
    total_liquidity - withdrawal_lp_amount + delta_liquidity_share,
    liquidity_share + delta_liquidity_share,
    new_root_k_last,
  )
}

fn validate_zap_in(
  order_in_value: Value,
  order_out_value: Value,
  minimum_lp: Int,
  a_to_b_direction: Bool,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  batcher_fee: Int,
  output_ada: Int,
  profit_sharing_opt: Option<ProfitSharing>,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  let (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) =
    pool_state
  let (asset_in, reserve_in, reserve_out) =
    if a_to_b_direction {
      (asset_a, reserve_a, reserve_b)
    } else {
      (asset_b, reserve_b, reserve_a)
    }
  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    asset_in
  let Asset { policy_id: lp_policy_id, asset_name: lp_asset_name } = lp_asset
  let temp_amount_in =
    value.quantity_of(order_in_value, asset_in_policy_id, asset_in_asset_name)
  let amount_in =
    if utils.is_ada_asset(asset_in_policy_id, asset_in_asset_name) {
      temp_amount_in - ( output_ada + batcher_fee )
    } else {
      temp_amount_in
    }
  let has_enough_amount_in = amount_in > 0
  let swap_amount_in =
    math.calculate_zap_swap_amount(
      reserve_in,
      amount_in,
      trading_fee_numerator,
      trading_fee_denominator,
    )
  let swap_to_asset_out_amount =
    math.calculate_amount_out(
      reserve_in,
      reserve_out,
      swap_amount_in,
      trading_fee_numerator,
      trading_fee_denominator,
    )
  let reserve_in_before_deposit = reserve_in + swap_amount_in
  let reserve_out_before_deposit = reserve_out - swap_to_asset_out_amount
  let reserve_in_after_deposit = reserve_in + amount_in
  let reserve_out_after_deposit = reserve_out
  let delta_liquidity =
    swap_to_asset_out_amount * total_liquidity / reserve_out_before_deposit

  let (delta_liquidity_share, new_root_k_last) =
    when profit_sharing_opt is {
      Some(profit_sharing) -> {
        let ProfitSharing { fee_sharing_numerator, fee_sharing_denominator, .. } =
          profit_sharing
        let delta_liquidity_share =
          math.calculate_profit_sharing(
            root_k_last,
            reserve_in_before_deposit * reserve_out_before_deposit,
            total_liquidity,
            fee_sharing_numerator,
            fee_sharing_denominator,
          )
        let new_root_k_last =
          math.calculate_sqrt(
            reserve_in_after_deposit * reserve_out_after_deposit,
          )
        (delta_liquidity_share, new_root_k_last)
      }
      None -> (0, root_k_last)
    }
  let (new_reserve_a, new_reserve_b) =
    if a_to_b_direction {
      (reserve_in_after_deposit, reserve_out_after_deposit)
    } else {
      (reserve_out_after_deposit, reserve_in_after_deposit)
    }
  let not_over_slippage = delta_liquidity >= minimum_lp
  let lp_amount_out =
    value.quantity_of(order_out_value, lp_policy_id, lp_asset_name)
  let ada_amount_out =
    value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
  let is_valid_amount_out =
    lp_amount_out == delta_liquidity && ada_amount_out == output_ada
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  (
    new_reserve_a,
    new_reserve_b,
    total_liquidity + delta_liquidity + delta_liquidity_share,
    liquidity_share + delta_liquidity_share,
    new_root_k_last,
  )
}

fn validate_zap_out(
  order_in_value: Value,
  order_out_value: Value,
  minimum_receive: Int,
  a_to_b_direction: Bool,
  asset_a: Asset,
  asset_b: Asset,
  lp_asset: Asset,
  output_ada: Int,
  profit_sharing_opt: Option<ProfitSharing>,
  trading_fee_numerator: Int,
  trading_fee_denominator: Int,
  pool_state: (Int, Int, Int, Int, Int),
) -> (Int, Int, Int, Int, Int) {
  let (reserve_a, reserve_b, total_liquidity, liquidity_share, root_k_last) =
    pool_state
  let asset_out =
    if a_to_b_direction {
      asset_b
    } else {
      asset_a
    }
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let Asset { policy_id: lp_policy_id, asset_name: lp_asset_name } = lp_asset
  let withdrawal_lp_amount =
    value.quantity_of(
      self: order_in_value,
      policy_id: lp_policy_id,
      asset_name: lp_asset_name,
    )
  let has_enough_amount_in = withdrawal_lp_amount > 0

  let (withdrawal_asset_a_amount, withdrawal_asset_b_amount) =
    math.calculate_withdraw(
      reserve_a: reserve_a,
      reserve_b: reserve_b,
      withdrawal_lp_amount: withdrawal_lp_amount,
      total_liquidity: total_liquidity,
    )
  let reserve_a_after_withdraw = reserve_a - withdrawal_asset_a_amount
  let reserve_b_after_withdraw = reserve_b - withdrawal_asset_b_amount
  let (delta_liquidity_share, new_root_k_last) =
    when profit_sharing_opt is {
      Some(profit_sharing) -> {
        let ProfitSharing { fee_sharing_numerator, fee_sharing_denominator, .. } =
          profit_sharing
        let delta_liquidity_share =
          math.calculate_profit_sharing(
            root_k_last,
            reserve_a * reserve_b,
            total_liquidity,
            fee_sharing_numerator,
            fee_sharing_denominator,
          )
        let new_root_k_last =
          math.calculate_sqrt(
            reserve_a_after_withdraw * reserve_b_after_withdraw,
          )
        (delta_liquidity_share, new_root_k_last)
      }
      None -> (0, root_k_last)
    }
  let amount_out =
    if a_to_b_direction {
      let extra_amount_out =
        math.calculate_amount_out(
          reserve_in: reserve_a_after_withdraw,
          reserve_out: reserve_b_after_withdraw,
          amount_in: withdrawal_asset_a_amount,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
        )
      withdrawal_asset_b_amount + extra_amount_out
    } else {
      let extra_amount_out =
        math.calculate_amount_out(
          reserve_in: reserve_b_after_withdraw,
          reserve_out: reserve_a_after_withdraw,
          amount_in: withdrawal_asset_b_amount,
          trading_fee_numerator: trading_fee_numerator,
          trading_fee_denominator: trading_fee_denominator,
        )
      withdrawal_asset_a_amount + extra_amount_out
    }
  let not_over_slippage = amount_out >= minimum_receive
  let ada_amount =
    value.quantity_of(order_out_value, ada_policy_id, ada_asset_name)
  let actual_amount_out =
    value.quantity_of(
      order_out_value,
      asset_out_policy_id,
      asset_out_asset_name,
    )
  let is_valid_amount_out =
    if utils.is_ada_asset(asset_out_policy_id, asset_out_asset_name) {
      actual_amount_out == output_ada + amount_out
    } else {
      actual_amount_out == amount_out && output_ada == ada_amount
    }
  expect has_enough_amount_in && not_over_slippage && is_valid_amount_out
  if a_to_b_direction {
    (
      reserve_a,
      reserve_b - amount_out,
      total_liquidity - withdrawal_lp_amount + delta_liquidity_share,
      liquidity_share + delta_liquidity_share,
      new_root_k_last,
    )
  } else {
    (
      reserve_a - amount_out,
      reserve_b,
      total_liquidity - withdrawal_lp_amount + delta_liquidity_share,
      liquidity_share + delta_liquidity_share,
      new_root_k_last,
    )
  }
}
