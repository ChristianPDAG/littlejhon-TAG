import { describe, expect, it } from "vitest";
import { privateKeyToAccount } from "viem/accounts";
import { verifyTypedData } from "viem";
import { riskAttestationTypes } from "@/lib/contracts/abis";
import { getRiskDomain } from "@/server/attestations/sign";

const privateKey = "0x59c6995e998f97a5a0044966f094538e2d1f090a1d9bd8e8874a4e6a366e3a9d";

describe("risk attestation typed data", () => {
  it("matches the ShieldRWAGuard RiskAttestation shape", async () => {
    const signer = privateKeyToAccount(privateKey);
    const message = {
      token: "0x1111111111111111111111111111111111111111",
      from: "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D",
      to: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      amount: BigInt(25_000_000),
      nonce: BigInt(1),
      deadline: BigInt(1_780_000_000),
      riskScore: BigInt(12),
    } as const;

    const signature = await signer.signTypedData({
      domain: getRiskDomain(46630),
      types: riskAttestationTypes,
      primaryType: "RiskAttestation",
      message,
    });

    await expect(
      verifyTypedData({
        address: signer.address,
        domain: getRiskDomain(46630),
        types: riskAttestationTypes,
        primaryType: "RiskAttestation",
        message,
        signature,
      }),
    ).resolves.toBe(true);
  });
});
