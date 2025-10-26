# save me as env_rescue.sh, then: bash env_rescue.sh
set -euo pipefail

mkdir -p scripts

# A. prints whether Node can see your env (never leaks your full PK)
cat > scripts/print-env.mjs <<'MJS'
import fs from "node:fs";
import path from "node:path";
import dotenv from "dotenv";

// Load .env.local if present (Next-style); otherwise .env; otherwise nothing.
const root = process.cwd();
const envLocal = path.join(root, ".env.local");
const envDefault = path.join(root, ".env");
if (fs.existsSync(envLocal)) {
  dotenv.config({ path: envLocal });
  console.log("Loaded: .env.local");
} else if (fs.existsSync(envDefault)) {
  dotenv.config({ path: envDefault });
  console.log("Loaded: .env");
} else {
  console.log("No .env.local or .env found");
}

const rpc = process.env.RPC_URL_BASE_SEPOLIA || null;
const pk  = process.env.PLATFORM_PRIVATE_KEY || null;
const eas = process.env.EAS_CONTRACT_ADDRESS || null;
const reg = process.env.SCHEMA_REGISTRY_ADDRESS || null;

const pkPreview = pk ? (pk.startsWith("0x") ? (pk.slice(0,6) + "…" + pk.slice(-4)) : "(invalid format)") : null;

console.log({
  cwd: process.cwd(),
  hasEnvLocal: fs.existsSync(envLocal),
  RPC_URL_BASE_SEPOLIA: !!rpc,
  PLATFORM_PRIVATE_KEY_present: !!pk,
  PLATFORM_PRIVATE_KEY_preview: pkPreview,
  EAS_CONTRACT_ADDRESS: eas || "(unset)",
  SCHEMA_REGISTRY_ADDRESS: reg || "(unset)"
});
MJS

# B. schema register script that auto-loads .env.local and validates inputs
cat > scripts/register-eas-schema.mjs <<'MJS'
import fs from "node:fs";
import path from "node:path";
import dotenv from "dotenv";
import { SchemaRegistry } from "@ethereum-attestation-service/eas-sdk";
import { ethers } from "ethers";

// Load .env.local (or .env)
const root = process.cwd();
const envLocal = path.join(root, ".env.local");
const envDefault = path.join(root, ".env");
if (fs.existsSync(envLocal)) {
  dotenv.config({ path: envLocal });
  console.log("Loaded: .env.local");
} else if (fs.existsSync(envDefault)) {
  dotenv.config({ path: envDefault });
  console.log("Loaded: .env");
} else {
  console.log("No .env.local or .env found; relying on process.env");
}

const RPC = process.env.RPC_URL_BASE_SEPOLIA;
const PK  = process.env.PLATFORM_PRIVATE_KEY;
const REG = process.env.SCHEMA_REGISTRY_ADDRESS ?? "0x4200000000000000000000000000000000000020"; // Base Sepolia registry

if (!RPC || !PK) {
  console.error("Missing RPC_URL_BASE_SEPOLIA or PLATFORM_PRIVATE_KEY");
  process.exit(1);
}
if (!PK.startsWith("0x")) {
  console.error("PLATFORM_PRIVATE_KEY must start with 0x");
  process.exit(1);
}

// demo schema: string app,string username,string goal,string result,bool disputed,string ref
const SCHEMA = "string app,string username,string goal,string result,bool disputed,string ref";

async function main(){
  const provider = new ethers.JsonRpcProvider(RPC);
  const wallet = new ethers.Wallet(PK, provider);

  console.log("Registering schema on Base Sepolia…");
  console.log("Registry:", REG);
  console.log("From:", wallet.address);

  const registry = new SchemaRegistry(REG);
  registry.connect(wallet);

  const tx = await registry.register({
    schema: SCHEMA,
    resolverAddress: "0x0000000000000000000000000000000000000000",
    revocable: true
  });
  const uid = await tx.wait();
  console.log("Schema UID:", uid);
  console.log("Paste that into .env.local as EAS_SCHEMA_UID");
}

main().catch(err => {
  console.error("Schema registration failed:");
  console.error(err?.reason || err?.message || err);
  process.exit(1);
});
MJS

echo "✅ Wrote scripts/print-env.mjs and scripts/register-eas-schema.mjs"

# Optional: make the Complete button show unless PASSED
perl -0777 -pe '
  s/\{g\.status===\x27PENDING\x27\s*&&\s*\(\<button className=\x22btn\x22 onClick=\{\(\)=>startComplete\(g\.id\)\} disabled=\{\!\!activeId\}\>Complete\<\/button\>\)\}/\{g\.status !== \x27PASSED\x27 \&\& \!activeId \&\& \(\<button className=\x22btn\x22 onClick=\{\(\)=>startComplete\(g\.id\)\}\>Complete\<\/button\>\)\}/
' -i '' src/app/profile/page.tsx 2>/dev/null || true

echo "✅ (Optional) Relaxed Complete button condition"
echo "Done."
