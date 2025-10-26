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
