# 😻 Minswap DEX V2 Contract

## Structure
- Main contracts:
  - [Authen Minting Policy](/validators/authen_minting_policy.ak)
  - [Pool Factory Validator](/validators/factory_validator.ak)
  - [Liquidity Pool Validator](/validators/pool_validator.ak)
  - [Order Validator](/validators/order_validator.ak)
- Library: under [library](/lib/amm_dex_v2) package

## Building

### Prerequisites
- Install [npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)
- Install [Aiken v1.0.24-alpha](https://aiken-lang.org/installation-instructions)
- Run `aiken build` to double check scripts bytecode in `plutus.json` file 
- Run `npm install` to install necessary dependencies 
- Run `npm run exec src/build-plutus.ts` to build scripts with initial parameters. The result is `script.json` file

## Testing

- Run `aiken check` to run all unit tests of the contract


## Deployment

### Testnet Preprod
The smart contract has already been deployed on Testnet Preprod.

The detailed information on the deployment is located in [References](/deployed/preprod/references.json)

## Audit Report

The contract audit has been conducted by Certik and Anastasia Labs
The Audit report is available under [Audit Report](/audit-report) folder

## References

1. [Specification](/amm-v2-docs/amm-v2-specs.md)
2. [Formula](/amm-v2-docs/formula.md)
