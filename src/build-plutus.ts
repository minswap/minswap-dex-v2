import fs from "fs";
import { Lucid } from "lucid-cardano";

import { EmulatorProvider } from "./provider";
import { getContractScripts } from "./script";
import { NetworkId } from "./types/network";

async function main() {
  const lucid = await Lucid.new(new EmulatorProvider(), "Preprod");

  const scripts = getContractScripts(lucid, NetworkId.TESTNET);
  fs.writeFileSync(
    `deployed/preprod/script.json`,
    JSON.stringify(scripts, null, 4)
  );
}

main();
