export const PROTOCOL_NAME = "CertiFiks";
export const SPECIFICATION_STATUS = "unverified" as const;
export type BountyStatus =
  | "draft"
  | "funded"
  | "assigned"
  | "submitted"
  | "verifying"
  | "review"
  | "disputed"
  | "payable"
  | "settled"
  | "refunded";
export * from "./commitments.js";
export * from "./validation.js";
export type { paths, components } from "./generated/openapi.js";
