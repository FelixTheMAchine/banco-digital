import test from "node:test";
import assert from "node:assert/strict";
import { retainUncertainFailure } from "../src/lib/financial-intents.ts";

test("retains uncertain failures including malformed success after a possible commit", () => {
  for (const error of [new Error("network"), { status: 0 }, { status: 201, code: "invalid_response" }, { status: 500 }, { status: 503 }, { status: NaN }]) assert.equal(retainUncertainFailure(error), true);
});
test("releases only confirmed HTTP client rejections", () => {
  for (const status of [400, 401, 403, 404, 409, 422, 429]) assert.equal(retainUncertainFailure({ status }), false);
});
