#!/usr/bin/env node
/**
 * Regenerate the frontend ABI from the local Foundry build.
 *
 * Before the frontend moved into this repo the ABI was copied across by hand,
 * which meant the UI could silently drift from the contract it talks to — a
 * renamed function or changed argument would only surface as a failed
 * transaction in someone's wallet. Now it is derived from `out/`, so the ABI
 * is wrong only if the build is.
 *
 *   npm run gen:abi        (from web/)
 *   forge build && npm --prefix web run gen:abi
 */

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..", "..");

const ARTIFACT = resolve(
  repoRoot,
  "out/BinaryMembershipV2.sol/BinaryMembershipV2.json",
);
const OUT = resolve(here, "..", "lib/contracts/binaryMembershipAbi.ts");

if (!existsSync(ARTIFACT)) {
  console.error(
    `No Foundry artifact at:\n  ${ARTIFACT}\n\nRun \`forge build\` in the repo root first.`,
  );
  process.exit(1);
}

const artifact = JSON.parse(readFileSync(ARTIFACT, "utf8"));
const abi = artifact.abi;

if (!Array.isArray(abi) || abi.length === 0) {
  console.error("Artifact contains no ABI. Did the build succeed?");
  process.exit(1);
}

const counts = abi.reduce((acc, e) => {
  acc[e.type] = (acc[e.type] ?? 0) + 1;
  return acc;
}, {});

// Sanity check: the frontend calls these by name. If the contract renames one,
// fail here rather than shipping a build that reverts in a member's wallet.
const REQUIRED = [
  "registerWithMaxPayment",
  "joinStageWithMaxPayment",
  "findPlacementSlot",
  "getMember",
  "getStageMembership",
  "getStageConfig",
  "getAwardInfo",
  "stageAnchor",
  "quoteStagePayment",
];
const names = new Set(abi.filter((e) => e.type === "function").map((e) => e.name));
const missing = REQUIRED.filter((n) => !names.has(n));
if (missing.length) {
  console.error(`Contract is missing functions the UI calls: ${missing.join(", ")}`);
  process.exit(1);
}

const header = `// GENERATED FILE - do not edit by hand.
// Source: out/BinaryMembershipV2.sol/BinaryMembershipV2.json
// Regenerate: forge build && npm --prefix web run gen:abi

export const BINARY_MEMBERSHIP_ABI = `;

writeFileSync(OUT, `${header}${JSON.stringify(abi, null, 2)} as const;\n`);

console.log(`ABI written to lib/contracts/binaryMembershipAbi.ts`);
console.log(
  `  ${counts.function ?? 0} functions, ${counts.event ?? 0} events, ${counts.error ?? 0} errors`,
);
