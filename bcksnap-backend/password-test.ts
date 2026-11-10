function encodeBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    ;
}

async function hashProfilePassword(salt: string, password: string): Promise<string> {
  let bytes = new TextEncoder().encode(`${salt}:${password}`);

  for (let i = 0; i < 10000; i++) {
    bytes = new Uint8Array(await globalThis.crypto.subtle.digest("SHA-256", bytes));
  }

  return encodeBase64Url(bytes);
}

hashProfilePassword("test-salt", "test123").then((hash) => {
  console.log("Backend test hash:", hash);
});

