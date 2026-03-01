import { assertEquals } from "@std/assert";

Deno.test("addition works", () => {
  assertEquals(1 + 1, 2);
});

Deno.test("subtraction works", () => {
  assertEquals(10 - 5, 5);
});

Deno.test("API status format", () => {
  const status = {
    status: "ok",
    runtime: "Deno",
    version: "1.40.0"
  };

  assertEquals(status.status, "ok");
  assertEquals(status.runtime, "Deno");
});
