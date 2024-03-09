import { C } from "lucid-cardano"

export namespace Redeemer {
    export function printRedeemers(redeemers: C.Redeemers): void {
        let totalCpu = 0n
        let totalMem = 0n
        for (let i = 0; i < redeemers.len(); i++) {
            const redeemer = redeemers.get(i)
            const tag = redeemer.tag()
            const index = redeemer.index().to_str()
            const exUnit = redeemer.ex_units()
            const cpu = exUnit.steps().to_str()
            const mem = exUnit.mem().to_str()
            totalCpu += BigInt(cpu)
            totalMem += BigInt(mem)

            let kind = ""
            switch (tag.kind()) {
                case C.RedeemerTagKind.Spend: {
                    kind = "Spend"
                    break;
                }
                case C.RedeemerTagKind.Mint: {
                    kind = "Mint"
                    break;
                }
                case C.RedeemerTagKind.Cert: {
                    kind = "Cert"
                    break;
                }
                case C.RedeemerTagKind.Reward: {
                    kind = "Reward"
                    break;
                }
                default: {
                    throw new Error(`ExUnit: Unsupported Redeemer Kind: ${tag.kind()}`);
                }
            }

            // const text = kind + " index " + index + " cost " + mem + " mem and " + cpu + " cpu"
            // console.log(text)
        }
        console.log(`Total: ${totalMem} mem and ${totalCpu} cpu`)
    }
}