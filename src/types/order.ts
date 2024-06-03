import { Constr, Data } from "lucid-cardano"

import { AddressPlutusData } from "./address";
import { Asset } from "./asset";

export enum OrderExtraDatumType {
    NO_DATUM = 0,
    DATUM_HASH,
    INLINE_DATUM,
}

export type OrderExtraDatum =
    | {
        type: OrderExtraDatumType.NO_DATUM;
    }
    | {
        type: OrderExtraDatumType.DATUM_HASH | OrderExtraDatumType.INLINE_DATUM;
        hash: string;
    };

export namespace OrderExtraDatum {
    export function toPlutus(d: OrderExtraDatum): Constr<Data> {
        switch (d.type) {
            case OrderExtraDatumType.NO_DATUM: {
                return new Constr(d.type, [])
            }
            case OrderExtraDatumType.DATUM_HASH: {
                return new Constr(d.type, [
                    d.hash
                ])
            }
            case OrderExtraDatumType.INLINE_DATUM: {
                return new Constr(d.type, [
                    d.hash
                ])
            }
        }
    }
}

export type OrderExpiry = {
    expiredTime: bigint;
    maxCancellingTip: bigint;
}

export enum OrderDirection {
    B_TO_A = 0,
    A_TO_B,
}

export namespace OrderDirection {
    export function toPlutus(o: OrderDirection): Constr<Data> {
        return new Constr(o, [])
    }
}

export enum OrderKillable {
    PENDING_ON_FAILED = 0,
    KILL_ON_FAILED,
}

export namespace OrderKillable {
    export function toPlutus(o: OrderKillable): Constr<Data> {
        return new Constr(o, [])
    }
}

export enum OrderAmountType {
    SPECIFIC_AMOUNT = 0,
    ALL,
}

export type OrderSwapAmountOption =
    | {
        type: OrderAmountType.SPECIFIC_AMOUNT;
        swapAmount: bigint;
    }
    | {
        type: OrderAmountType.ALL;
        deductedAmount: bigint;
    };

export namespace OrderSwapAmountOption {
    export function toPlutus(o: OrderSwapAmountOption): Constr<Data> {
        switch (o.type) {
            case OrderAmountType.SPECIFIC_AMOUNT: {
                return new Constr(o.type, [
                    o.swapAmount
                ])
            }
            case OrderAmountType.ALL: {
                return new Constr(o.type, [
                    o.deductedAmount
                ])
            }
        }
    }
}

export type OrderSwapExactInStep = {
    direction: OrderDirection;
    swapAmountOption: OrderSwapAmountOption;
    minimumReceived: bigint;
    killable: OrderKillable;
}

export namespace OrderStep {
    export function toPlutus(step: OrderSwapExactInStep): Constr<Data> {
        return new Constr(0, [
            OrderDirection.toPlutus(step.direction),
            OrderSwapAmountOption.toPlutus(step.swapAmountOption),
            step.minimumReceived,
            OrderKillable.toPlutus(step.killable)
        ])
    }
}

export enum OrderAuthorizationMethodType {
    SIGNATURE = 0,
    SPEND_SCRIPT,
    WITHDRAW_SCRIPT,
    MINT_SCRIPT
}

export type OrderAuthorizationMethod = {
    type: OrderAuthorizationMethodType,
    hash: string;
}

export namespace OrderAuthorizationMethod {
    export function toPlutus(m: OrderAuthorizationMethod): Constr<Data> {
        return new Constr(m.type, [
            m.hash
        ])
    }
}

export type OrderDatum = {
    canceller: OrderAuthorizationMethod,
    refundReceiver: string;
    refundReceiverDatum: OrderExtraDatum;
    successReceiver: string;
    successReceiverDatum: OrderExtraDatum;
    lpAsset: Asset;
    step: OrderSwapExactInStep;
    maxBatcherFee: bigint;
    expiredOptions?: OrderExpiry;
}

export namespace OrderDatum {
    export function toPlutus(dat: OrderDatum): Constr<Data>{
        return new Constr(0, [
            OrderAuthorizationMethod.toPlutus(dat.canceller),
            AddressPlutusData.toPlutus(dat.refundReceiver),
            OrderExtraDatum.toPlutus(dat.refundReceiverDatum),
            AddressPlutusData.toPlutus(dat.successReceiver),
            OrderExtraDatum.toPlutus(dat.successReceiverDatum),
            Asset.toPlutus(dat.lpAsset),
            OrderStep.toPlutus(dat.step),
            dat.maxBatcherFee,
            dat.expiredOptions ? new Constr(0, [
                dat.expiredOptions.expiredTime,
                dat.expiredOptions.maxCancellingTip
            ]) : new Constr(1, [])
        ])
    }
}