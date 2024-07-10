import { Constr, Data } from "lucid-cardano";


export enum PoolAuthorizationMethodType {
    SIGNATURE = 0,
    SPEND_SCRIPT,
    WITHDRAW_SCRIPT,
}

export type PoolAuthorizationMethod = {
    type: PoolAuthorizationMethodType,
    hash: string;
}

export namespace PoolAuthorizationMethod {
    export function toPlutus(m: PoolAuthorizationMethod): Constr<Data> {
        return new Constr(m.type, [
            m.hash
        ])
    }
}

export type GlobalSetting = {
    batchers: PoolAuthorizationMethod[],
    poolFeeUpdater: PoolAuthorizationMethod,
    feeSharingTaker: PoolAuthorizationMethod,
    poolStakeKeyUpdater: PoolAuthorizationMethod,
    poolDynamicFeeUpdater: PoolAuthorizationMethod,
    admin: PoolAuthorizationMethod,
}

export namespace GlobalSetting {
    export function toPlutus(gs: GlobalSetting): Constr<Data> {
        return new Constr(0, [
            gs.batchers.map(PoolAuthorizationMethod.toPlutus),
            PoolAuthorizationMethod.toPlutus(gs.poolFeeUpdater),
            PoolAuthorizationMethod.toPlutus(gs.feeSharingTaker),
            PoolAuthorizationMethod.toPlutus(gs.poolStakeKeyUpdater),
            PoolAuthorizationMethod.toPlutus(gs.poolDynamicFeeUpdater),
            PoolAuthorizationMethod.toPlutus(gs.admin)
        ])
    }
}