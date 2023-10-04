use aiken/list
use aiken/transaction.{Input, Output, ValidityRange}
use aiken/transaction/credential.{Address, VerificationKeyCredential}
use aiken/transaction/value.{PolicyId}
use amm_dex_v2/types.{PubKeyHash}
use amm_dex_v2/utils

pub fn validate_batcher(
  inputs: List<Input>,
  validity_range: ValidityRange,
  extra_signatories: List<PubKeyHash>,
  batcher_address: Address,
  license_policy_id: PolicyId,
  license_index: Int,
  maximum_deadline_range: Int,
) -> Bool {
  // Batching Redeemer provides @license_index which help save calculation cost
  let Input { output: Output { value: license_value, .. }, .. } =
    utils.must_parse_option(list.at(inputs, license_index))
  let license_deadline =
    utils.find_license_deadline(license_policy_id, license_value)
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
  True
}
