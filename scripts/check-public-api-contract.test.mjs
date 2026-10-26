import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const document = JSON.parse(
  readFileSync(new URL("../protocol/public-api.v1.json", import.meta.url), "utf8"),
);
const serverSource = readFileSync(
  new URL("../apps/api/src/app.ts", import.meta.url),
  "utf8",
);

test("versioned partner OpenAPI lists only actual read endpoints with no fake mutations", () => {
  assert.equal(document.openapi, "3.1.0");
  const paths = Object.keys(document.paths).sort();
  assert.deepEqual(paths, [
    "/v1/bounties",
    "/v1/bounties/{bountyId}",
    "/v1/partner/bounties",
  ]);
  for (const [route, methods] of Object.entries(document.paths)) {
    assert.deepEqual(Object.keys(methods), ["get"]);
    const fastifyPath = route.replace("{bountyId}", ":bountyId");
    assert.ok(serverSource.includes(`app.get("${fastifyPath}"`));
    assert.equal(methods.get["x-certifiks-actual-implementation"], true);
    assert.ok(methods.get.responses["200"]);
    assert.ok(methods.get.responses["503"]);
  }
});

test("public projections cannot imply verification or transmit private evidence", () => {
  const schema = document.components.schemas.PublicBountyV1;
  assert.equal(schema.additionalProperties, false);
  assert.equal(schema.properties.verificationProven.const, false);
  assert.equal(schema.properties.rewardAtoms.type, "string");
  assert.ok(!JSON.stringify(schema).includes("privateArtifact"));
  assert.ok(!JSON.stringify(schema).includes("walletPrivateKey"));
});

test("partner key security and HTTP errors are documented as implemented", () => {
  const operation = document.paths["/v1/partner/bounties"].get;
  assert.deepEqual(operation.security, [{ PartnerKey: [] }]);
  assert.equal(
    document.components.securitySchemes.PartnerKey.name,
    "x-certifiks-api-key",
  );
  assert.ok(operation.responses["401"]);
  assert.ok(operation.responses["503"]);
  assert.ok(!("post" in document.paths["/v1/bounties"]));
});
