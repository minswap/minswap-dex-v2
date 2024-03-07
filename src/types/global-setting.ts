import { Constr, Data } from "lucid-cardano";

import { AddressPlutusData } from "./address";

export type GlobalSetting = {
    batchers: string[],
    poolFeeUpdater: string,
    feeSharingTaker: string,
    poolStakeKeyUpdater: string,
    poolDynamicFeeUpdater: string,
    admin: string,
}

export namespace GlobalSetting {
    export function toPlutus(gs: GlobalSetting): Constr<Data> {
        return new Constr(0, [
            gs.batchers.map(AddressPlutusData.toPlutus),
            AddressPlutusData.toPlutus(gs.poolFeeUpdater),
            AddressPlutusData.toPlutus(gs.feeSharingTaker),
            AddressPlutusData.toPlutus(gs.poolStakeKeyUpdater),
            AddressPlutusData.toPlutus(gs.poolDynamicFeeUpdater),
            AddressPlutusData.toPlutus(gs.admin)
        ])
    }
}