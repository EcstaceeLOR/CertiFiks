import { Ajv, type ErrorObject, type ValidateFunction } from "ajv";
import manifest from "./schemas/v1/bounty-manifest.schema.json" with {
  type: "json",
};
import attempt from "./schemas/v1/candidate-attempt.schema.json" with {
  type: "json",
};
import event from "./schemas/v1/chain-event.schema.json" with { type: "json" };
import dispute from "./schemas/v1/dispute-case.schema.json" with {
  type: "json",
};
import report from "./schemas/v1/verification-report.schema.json" with {
  type: "json",
};

const ajv = new Ajv({
  allErrors: true,
  strict: true,
  removeAdditional: false,
  useDefaults: false,
  coerceTypes: false,
});
const validators = {
  manifest: ajv.compile(manifest),
  attempt: ajv.compile(attempt),
  report: ajv.compile(report),
  dispute: ajv.compile(dispute),
  event: ajv.compile(event),
};
export type ProtocolSchemaName = keyof typeof validators;
export class SchemaValidationError extends Error {
  constructor(
    public readonly schemaName: ProtocolSchemaName,
    public readonly details: ErrorObject[],
  ) {
    super("Invalid CertiFiks " + schemaName + " v1 schema");
    this.name = "SchemaValidationError";
  }
}
export function validateProtocolDocument(
  name: ProtocolSchemaName,
  value: unknown,
): void {
  const validator: ValidateFunction = validators[name];
  if (!validator(value)) {
    throw new SchemaValidationError(
      name,
      validator.errors ? [...validator.errors] : [],
    );
  }
}
export function isProtocolDocument(
  name: ProtocolSchemaName,
  value: unknown,
): boolean {
  return Boolean(validators[name](value));
}
