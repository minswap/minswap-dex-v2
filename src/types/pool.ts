import {
    Constr,
    Credential,
    Data,
} from "lucid-cardano";

import { LucidCredential } from "./address";
import { Asset } from "./asset";

export type PoolBaseFee = {
    feeANumerator: bigint;
    feeBNumerator: bigint;
};

export type PoolDatum = {
    poolBatchingStakeCredential: Credential;
    assetA: Asset;
    assetB: Asset;
    totalLiquidity: bigint;
    reserveA: bigint;
    reserveB: bigint;
    baseFee: PoolBaseFee;
    feeSharingNumerator?: bigint;
    allowDynamicFee: boolean;
};

export namespace PoolDatum {
    export function toPlutus(dat: PoolDatum): Constr<Data> {
        return new Constr(0, [
            new Constr(0, [
                LucidCredential.toPlutus(dat.poolBatchingStakeCredential)
            ]),
            Asset.toPlutus(dat.assetA),
            Asset.toPlutus(dat.assetB),
            dat.totalLiquidity,
            dat.reserveA,
            dat.reserveB,
            dat.baseFee.feeANumerator,
            dat.baseFee.feeBNumerator,
            dat.feeSharingNumerator ? new Constr(0, [dat.feeSharingNumerator]) : new Constr(1, []),
            new Constr(dat.allowDynamicFee ? 1 : 0, [])
        ])
    }
}