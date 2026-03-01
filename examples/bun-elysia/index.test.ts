import { describe, expect, test } from "bun:test";

describe("Math operations", () => {
  test("addition", () => {
    expect(1 + 1).toBe(2);
  });

  test("subtraction", () => {
    expect(10 - 5).toBe(5);
  });

  test("multiplication", () => {
    expect(3 * 4).toBe(12);
  });
});

describe("API", () => {
  test("status format", () => {
    const status = {
      status: "ok",
      runtime: "Bun",
      version: "1.0.0"
    };

    expect(status.status).toBe("ok");
    expect(status.runtime).toBe("Bun");
  });
});
