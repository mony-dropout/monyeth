import { SchemaRegistry } from "@ethereum-attestation-service/eas-sdk";
import { ethers } from "ethers";

const RPC = process.env.RPC_URL_BASE_SEPOLIA;
const PK  = process.env.PLATFORM_PRIVATE_KEY;
const REG = process.env.SCHEMA_REGISTRY_ADDRESS ?? "0x4200000000000000000000000000000000000020"; // Base Sepolia

const SCHEMA = "string app,string username,string goal,string result,bool disputed,string ref";

if (!RPC || !PK) {
  console.error("Missing RPC_URL_BASE_SEPOLIA or PLATFORM_PRIVATE_KEY");
  process.exit(1);
}

const provider = new ethers.JsonRpcProvider(RPC);
const wallet = new ethers.Wallet(PK, provider);

const registry = new SchemaRegistry(REG);
registry.connect(wallet);

console.log("Registering schema on Base Sepolia…");
const tx = await registry.register({
  schema: SCHEMA,
  resolverAddress: "0x0000000000000000000000000000000000000000",
  revocable: true
});
const uid = await tx.wait();
console.log("Schema UID:", uid);
console.log("Paste this into .env.local as EAS_SCHEMA_UID");
