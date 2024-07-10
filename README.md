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

### Mainnet
The smart contract has already been deployed on Mainnet.

The detailed information on the deployment is located in [References](/deployed/mainnet/references.json)

Here is the deployed transaction:
- [Order](https://cardanoscan.io/transaction/cf4ecddde0d81f9ce8fcc881a85eb1f8ccdaf6807f03fea4cd02da896a621776)
- [Liquidity Pool](https://cardanoscan.io/transaction/2536194d2a976370a932174c10975493ab58fd7c16395d50e62b7c0e1949baea)
- [Factory](https://cardanoscan.io/transaction/59c7fa5c30cbab4e6d38f65e15d1adef71495321365588506ad089d237b602e0)
- [Authentication](https://cardanoscan.io/transaction/dbc1498500a6e79baa0f34d10de55cdb4289ca6c722bd70e1e1b78a858f136b9)
- [Liquidity Pool Batching](https://cardanoscan.io/transaction/d46bd227bd2cf93dedd22ae9b6d92d30140cf0d68b756f6608e38d680c61ad17)
- [Expired Order Cancellation](https://cardanoscan.io/transaction/ef3acc7dfc5a98bffe8f4d4400e65a9ade5a1316b2fcb7145c3b83dba38a66f5)

The smart contract parameters is located on [Params](/deployed/mainnet/params.json) file

Official Tokens and Smart contract address are maintained by Minswap Labs includes:
- Pool Validity Asset: f5808c2c990d86da54bfc97d89cee6efa20cd8461616359478d96b4c.4d5350
- Factory Validity Asset: f5808c2c990d86da54bfc97d89cee6efa20cd8461616359478d96b4c.4d5346
- Global Setting Validity Asset: f5808c2c990d86da54bfc97d89cee6efa20cd8461616359478d96b4c.4d534753
- LP Token Policy ID: f5808c2c990d86da54bfc97d89cee6efa20cd8461616359478d96b4c
- Pool Script Hash: ea07b733d932129c378af627436e7cbc2ef0bf96e0036bb51b3bde6b
- Order Script Hash: c3e28c36c3447315ba5a56f33da6a6ddc1770a876a8d9f0cb3a97c4c
- Factory Script Hash: 7bc5fbd41a95f561be84369631e0e35895efb0b73e0a7480bb9ed730
- Global Setting Script Hash: f5808c2c990d86da54bfc97d89cee6efa20cd8461616359478d96b4c
- Pool Creation Address (default address of a new liquidity pool): addr1z84q0denmyep98ph3tmzwsmw0j7zau9ljmsqx6a4rvaau66j2c79gy9l76sdg0xwhd7r0c0kna0tycz4y5s6mlenh8pq777e2a
- Liquidity Pool Batching stake address: stake17y02a946720zw6pw50upt2arvxsvvpvaghjtl054h0f0gjsfyjz59
- Expired Order Cancellation stake address: stake178ytpnrpxax5p8leepgjx9cq8ecedgly6jz4xwvvv4kvzfq9s6295

Example transactions:
- [DEX Initialization](https://cardanoscan.io/transaction/22a2ae40124855a98b262e32b69218c51c6a159cd4fa99f1c34a798d3a0ff8a9)
- [Liquidity Pool Creation](https://cardanoscan.io/transaction/3167ca40518b1b77b331aeda378e36997a566ec7b557d70eb026aa952e2ecf6d)
- [Batching](https://cardanoscan.io/transaction/a544364aacd0f8b61aa8abf9f024e06e57a8858669eead2d3aaab0b9878e1bc3)
- [Swap Exact In](https://cardanoscan.io/transaction/a0fc29c9191762ab3485bc431616d306de0ff414d8f785ffa59d40a8fc7dc0df)
- [Limit](https://cardanoscan.io/transaction/bd824cdfb80f5fc722dedc494bf94eb06794ca724bfc27c4dd5fcbbdd91b1d66)
- [Stop](https://cardanoscan.io/transaction/18f9f12dec65d8e84e06f8c202710d4cf366081a4ce94b05855cca2b6834459e
)
- [OCO](https://cardanoscan.io/transaction/c76594de9d089698055e6034547b71da46c5db43567c37472f827fe77d99fc34
)
- [Partial Swap](https://cardanoscan.io/transaction/1615cd9caddf206ab22dee08d364f2950448cf6b91352142eed5b37308e81df1)
- [Zap In](https://cardanoscan.io/transaction/4ec9236ea1ff0e4767b30f9f4d1e8bc0d2ce7262513ab3f9d944cd04fe3fd8b3)
- [Deposit](https://cardanoscan.io/transaction/8354d700e233878cf460c7821b8b49e8158c96aaa462f8e6d43aa66994a93837)
- [Zap Out](https://cardanoscan.io/transaction/46046d1f4a68227802d6057b1815ac93ec7ee572ee2957aef1527170fcbb4ef1)
- [Withdraw](https://cardanoscan.io/transaction/5313373a182fb26bc7e097f1c32de7cdb89d3c9da6e00d625b0f3684477615cd)
- [Order Cancellation](https://cardanoscan.io/transaction/ca11ebacbbff1b93b72abb71083ac41c95c2d237af5091dc95519f76e2799e27)
- [Expired Order Cancellation](https://cardanoscan.io/transaction/ce350ae5822281a3bbccdab61719ca97ecf3955b9b496e27b6e18aba4dc4bf1a)


## Audit Report

The contract audit has been conducted by Certik and Anastasia Labs
The Audit report is available under [Audit Report](/audit-report) folder

## References

1. [Specification](/amm-v2-docs/amm-v2-specs.md)
2. [Formula](/amm-v2-docs/formula.md)