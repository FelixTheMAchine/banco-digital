import test from "node:test";
import assert from "node:assert/strict";
import { editableCents, formatCents, integerInRange, parseCents, positiveCents } from "../src/lib/money.ts";

test("parses Brazilian currency without fractional-cent rounding", () => {
  assert.equal(parseCents("1.234.567,89"), 123456789);
  assert.equal(parseCents("0,01"), 1);
  assert.equal(parseCents(" 15,5 "), 1550);
  assert.equal(parseCents("10"), 1000);
  assert.equal(parseCents("0,00"), 0);
});

test("rejects negative amounts, exponents, malformed grouping and fractional cents", () => {
  for (const input of ["-1,00", "+1,00", "1e5", "1,005", "1.23", "1,2,3", "NaN", "Infinity", "", "1 000,00"]) {
    assert.throws(() => parseCents(input), input);
  }
  assert.throws(() => positiveCents("0,00"));
});

test("preserves the safe backend maximum and refuses larger values", () => {
  assert.equal(parseCents("90.000.000.000.000,00"), 9_000_000_000_000_000);
  assert.throws(() => parseCents("90.000.000.000.000,01"));
  assert.throws(() => parseCents("999999999999999999999999999999999999999,00"));
});

test("formats signed integer cents and refuses lossy numeric input", () => {
  assert.equal(formatCents(123456789), "R$ 1.234.567,89");
  assert.equal(formatCents(-1), "−R$ 0,01");
  assert.equal(formatCents("9000000000000000"), "R$ 90.000.000.000.000,00");
  assert.equal(formatCents(1.1), "—");
  assert.equal(formatCents(Number.MAX_SAFE_INTEGER + 1), "—");
  assert.equal(formatCents(undefined), "—");
});

test("keeps editable profile amounts exact on round trips", () => {
  for (const cents of [0, 1, 99, 100, 1000001, 9_000_000_000_000_000]) {
    assert.equal(parseCents(editableCents(cents)), cents);
  }
});

test("accepts only bounded integer terms", () => {
  assert.equal(integerInRange("120", 1, 120), 120);
  for (const value of ["0", "121", "1.5", "1e2", "-1", "9007199254740992", ""]) {
    assert.throws(() => integerInRange(value, 1, 120));
  }
});
