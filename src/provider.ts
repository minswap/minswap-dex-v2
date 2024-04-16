import {
  C,
  Credential,
  Delegation,
  fromHex,
  OutRef,
  PROTOCOL_PARAMETERS_DEFAULT,
  ProtocolParameters,
  Provider,
  UTxO,
} from "lucid-cardano";

import { Redeemer } from "./types/redeemer";

export class EmulatorProvider implements Provider {
  async getProtocolParameters(): Promise<ProtocolParameters> {
    return PROTOCOL_PARAMETERS_DEFAULT;
  }
  async getUtxos(_addressOrCredential: string | Credential): Promise<UTxO[]> {
    return [];
  }
  async getUtxosWithUnit(
    _addressOrCredential: string | Credential,
    _unit: string
  ): Promise<UTxO[]> {
    return [];
  }
  async getUtxoByUnit(_unit: string): Promise<UTxO> {
    throw new Error("Method not implemented.");
  }
  getUtxosByOutRef(_outRefs: OutRef[]): Promise<UTxO[]> {
    throw new Error("Method not implemented.");
  }
  getDelegation(_rewardAddress: string): Promise<Delegation> {
    throw new Error("Method not implemented.");
  }
  getDatum(_datumHash: string): Promise<string> {
    throw new Error("Method not implemented.");
  }
  awaitTx(
    _txHash: string,
    _checkInterval?: number | undefined
  ): Promise<boolean> {
    throw new Error("Method not implemented.");
  }
  async submitTx(tx: string): Promise<string> {
    const cslTx = C.Transaction.from_bytes(fromHex(tx));
    // console.log(cslTx.to_json())
    const cslTxBody = cslTx.body();
    const cslTxId = C.hash_transaction(cslTxBody);
    const cslRedeemers = cslTx.witness_set().redeemers();
    if (cslRedeemers) {
      Redeemer.printRedeemers(cslRedeemers);
    }
    return cslTxId.to_hex();
  }
}
