import { createHash } from "node:crypto";

function encodeBase64Url(bytes: Uint8Array): string {
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function hashProfilePassword(salt: string, password: string): string {
  let bytes = new TextEncoder().encode(`${salt}:${password}`);

  for (let i = 0; i < 10000; i++) {
    bytes = new Uint8Array(
      createHash("sha256").update(bytes).digest()
    );
  }

  return encodeBase64Url(bytes);
}

const salt = "test-salt";
const password = "test123";

console.log("Backend test hash:", hashProfilePassword(salt, password));