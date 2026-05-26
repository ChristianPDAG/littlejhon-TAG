import { z } from "zod";

const addressSchema = z.string().regex(/^0x[a-fA-F0-9]{40}$/);
const hexSchema = z.string().regex(/^0x[a-fA-F0-9]*$/);

export const riskCheckRequestSchema = z.object({
  chainId: z.number().int().positive(),
  from: addressSchema,
  to: addressSchema,
  data: hexSchema.optional(),
  value: z.string().default("0"),
  asset: z.string().min(1),
  token: addressSchema.optional(),
  amount: z.string().regex(/^\d+$/),
  context: z
    .object({
      action: z.enum(["TRANSFER", "APPROVE", "TRANSFER_FROM"]).optional(),
      policyId: z.string().min(1).optional(),
      scenarioId: z.enum(["safe-transfer", "unlimited-approval", "fake-token", "ineligible-recipient"]).optional(),
      recipientEligible: z.boolean().optional(),
      spender: addressSchema.optional(),
    })
    .optional(),
});

export const attestRequestSchema = riskCheckRequestSchema.extend({
  nonce: z.string().regex(/^\d+$/).optional(),
  deadline: z.string().regex(/^\d+$/).optional(),
});
