import { Constr, Data } from "lucid-cardano"
export const ADA: Asset = {
    policyId: "",
    tokenName: ""
}

export type Asset = {
    policyId: string,
    tokenName: string
}

export namespace Asset {
    export function equals(a1: Asset, a2: Asset): boolean {
        return a1.policyId === a2.policyId && a1.tokenName === a2.tokenName
    }
    export function toPlutus(asset: Asset): Constr<Data> {
        return new Constr(0, [
            asset.policyId,
            asset.tokenName
        ])
    }

    export function toString(asset: Asset): string {
        if (Asset.equals(ADA, asset)) {
            return "lovelace";
        }
        if (asset.tokenName === "") {
            return asset.policyId;
        }
        return `${asset.policyId}${asset.tokenName}`;
    }
}