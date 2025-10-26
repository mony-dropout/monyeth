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
