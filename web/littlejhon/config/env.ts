import { z } from "zod";
import type { Address, Hex } from "viem";

const addressSchema = z
  .string()
  .regex(/^0x[a-fA-F0-9]{40}$/, "Expected an EVM address") as z.ZodType<Address>;

const optionalAddressSchema = z.preprocess(
  (value) => (value === "" ? undefined : value),
  z.string().regex(/^0x[a-fA-F0-9]{40}$/, "Expected an EVM address").optional(),
) as z.ZodType<Address | undefined>;

const privateKeySchema = z.preprocess(
  (value) => (value === "" ? undefined : value),
  z.string().regex(/^0x[a-fA-F0-9]{64}$/, "Expected a 32-byte private key").optional(),
) as z.ZodType<Hex | undefined>;

const publicEnvSchema = z.object({
  NEXT_PUBLIC_DEFAULT_CHAIN_ID: z.coerce.number().int().positive().default(46630),
  NEXT_PUBLIC_RH_RPC_URL: z.url().default("https://rpc.testnet.chain.robinhood.com"),
  NEXT_PUBLIC_RH_EXPLORER_URL: z.url().default("https://explorer.testnet.chain.robinhood.com"),
  NEXT_PUBLIC_ARBITRUM_SEPOLIA_RPC_URL: z.url().default("https://sepolia-rollup.arbitrum.io/rpc"),
  NEXT_PUBLIC_ARBITRUM_SEPOLIA_EXPLORER_URL: z.url().default("https://sepolia.arbiscan.io"),
  NEXT_PUBLIC_SHIELD_GUARD_ADDRESS: addressSchema.default("0xB4f9C2151B73eDEa730A72e9642C971d803Fd096"),
  NEXT_PUBLIC_COMPLIANCE_REGISTRY_ADDRESS: addressSchema.default("0x5886F06c5cD7eC7E07396D4787fca22A965032C5"),
  NEXT_PUBLIC_PROOF_OF_RESERVE_ADDRESS: addressSchema.default("0x5eD6fe0C2bF02227153CC5482f7d316475a11625"),
  NEXT_PUBLIC_CIRCUIT_BREAKER_ADDRESS: addressSchema.default("0x8A65a9ae5057eB846ce06c1E890f0aB8ADB05777"),
  NEXT_PUBLIC_API_BASE_PATH: z.string().default("/api"),
  NEXT_PUBLIC_ENABLE_ONCHAIN_EXECUTION: z.coerce.boolean().default(false),
  NEXT_PUBLIC_DEMO_AAPL_TOKEN: optionalAddressSchema,
  NEXT_PUBLIC_DEMO_NVDA_TOKEN: optionalAddressSchema,
  NEXT_PUBLIC_DEMO_FAKE_TOKEN: optionalAddressSchema,
});

const serverEnvSchema = publicEnvSchema.extend({
  TRUSTED_SIGNER_PRIVATE_KEY: privateKeySchema,
  ATTESTATION_TTL_SECONDS: z.coerce.number().int().min(60).max(3600).default(300),
  MAX_RISK_SCORE: z.coerce.number().int().min(0).max(100).default(75),
  ENABLE_ONCHAIN_EXECUTION: z.coerce.boolean().default(false),
  ASSET_REGISTRY_MODE: z.enum(["mock", "env"]).default("mock"),
});

export type PublicEnv = z.infer<typeof publicEnvSchema>;
export type ServerEnv = z.infer<typeof serverEnvSchema>;

export function getPublicEnv(): PublicEnv {
  return publicEnvSchema.parse(process.env);
}

export function getServerEnv(): ServerEnv {
  return serverEnvSchema.parse(process.env);
}
