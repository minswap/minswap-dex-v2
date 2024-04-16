import { Constr, Data } from "lucid-cardano"

export type TxIn = {
    txId: string,
    index: number
}

export namespace TxIn {
    export function toPlutus(txIn: TxIn): Constr<Data> {
        return new Constr(0, [
            new Constr(0, [
                txIn.txId
            ]),
            BigInt(txIn.index)
        ])
    }

    export function compare(a: TxIn, b: TxIn): number {
        if (a.txId === b.txId) {
            return a.index - b.index;
        } else if (a.txId < b.txId) {
            return -1
        } else {
            return 1
        }
    }
}