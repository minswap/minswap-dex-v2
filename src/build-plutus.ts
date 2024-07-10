import fs from "fs";
import { Lucid } from "lucid-cardano";

import { EmulatorProvider } from "./provider";
import { getContractScripts } from "./script";
import { NetworkId } from "./types/network";

async function main() {
  const lucidTestnet = await Lucid.new(new EmulatorProvider(), "Preprod");

  const testnetScripts = getContractScripts(lucidTestnet, NetworkId.TESTNET);
  fs.writeFileSync(
    `deployed/preprod/script.json`,
    JSON.stringify(testnetScripts, null, 4)
  );

  const lucidMainnet = await Lucid.new(new EmulatorProvider(), "Mainnet");

  const mainnetScripts = getContractScripts(lucidMainnet, NetworkId.MAINNET);
  fs.writeFileSync(
    `deployed/mainnet/script.json`,
    JSON.stringify(mainnetScripts, null, 4)
  );
}

main();
