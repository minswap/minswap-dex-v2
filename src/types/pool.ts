import {
    Constr,
    Credential,
    Data,
} from "lucid-cardano";

import { LucidCredential } from "./address";
import { Asset } from "./asset";

export type PoolBaseFee = {
    feeA: [bigint, bigint];
    feeB: [bigint, bigint];
};

export type PoolDatum = {
    poolBatchingStakeCredential: Credential;
    assetA: Asset;
    assetB: Asset;
    totalLiquidity: bigint;
    reserveA: bigint;
    reserveB: bigint;
    baseFee: PoolBaseFee;
    profitSharing?: [bigint, bigint];
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
            dat.baseFee.feeA[0],
            dat.baseFee.feeA[1],
            dat.baseFee.feeB[0],
            dat.baseFee.feeB[1],
            dat.profitSharing ? new Constr(0, [
                [dat.profitSharing[0], dat.profitSharing[1]]
            ]) : new Constr(1, []),
            new Constr(dat.allowDynamicFee ? 1 : 0, [])
        ])
    }
}