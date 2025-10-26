import { EAS, SchemaEncoder } from "@ethereum-attestation-service/eas-sdk";
import { ethers } from "ethers";

const ZERO_UID = "0x0000000000000000000000000000000000000000000000000000000000000000";
const DEFAULT_EAS = "0x4200000000000000000000000000000000000021"; // Base Sepolia EAS
// Schema for this demo:
//   string app,string username,string goal,string result,bool disputed,string ref
// You'll register it and paste UID into EAS_SCHEMA_UID.
const SCHEMA = "string app,string username,string goal,string result,bool disputed,string ref";

type AttestInput = {
  username: string;
  goalTitle: string;
  result: "PASS" | "FAIL";
  disputed: boolean;
  ref: string; // goal id
};

export async function attestResult(input: AttestInput): Promise<{ uid: string; txHash: string; mocked: boolean }> {
  const RPC = process.env.RPC_URL_BASE_SEPOLIA;
  const PK  = process.env.PLATFORM_PRIVATE_KEY;
  const SCHEMA_UID = process.env.EAS_SCHEMA_UID;
  const EAS_ADDR = process.env.EAS_CONTRACT_ADDRESS ?? DEFAULT_EAS;

  // Mock if envs are missing
  if (!RPC || !PK || !SCHEMA_UID) {
    const uid = `MOCK-${input.result}-${input.ref}`;
    return { uid, txHash: "0xMOCK", mocked: true };
  }

  const provider = new ethers.JsonRpcProvider(RPC);
  const wallet = new ethers.Wallet(PK, provider);

  const eas = new EAS(EAS_ADDR);
  eas.connect(wallet);

  const encoder = new SchemaEncoder(SCHEMA);
  const data = encoder.encodeData([
    { name: "app",      type: "string", value: "ProofOfDay" },
    { name: "username", type: "string", value: input.username },
    { name: "goal",     type: "string", value: input.goalTitle },
    { name: "result",   type: "string", value: input.result },
    { name: "disputed", type: "bool",   value: input.disputed },
    { name: "ref",      type: "string", value: input.ref },
  ]);

  const tx = await eas.attest({
    schema: SCHEMA_UID,
    data: {
      recipient: wallet.address,     // platform as recipient for demo
      expirationTime: 0,             // no expiry
      revocable: true,
      refUID: ZERO_UID,
      data,
      value: 0,
    },
  });

  const uid = await tx.wait();
  return { uid, txHash: tx.hash, mocked: false };
}

export const EAS_SCHEMA_STRING = SCHEMA;
