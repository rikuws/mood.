import { createHash } from "node:crypto";
import {
  copyFile,
  mkdir,
  readFile,
  rm,
  stat
} from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const rootDirectory = path.resolve(scriptDirectory, "..");
const outputDirectory = path.join(rootDirectory, "dist");
const expectedExtensionID = "ohhhjpbfjecipcnkahlhaggckmdjfndg";
const runtimeFiles = [
  "manifest.json",
  "background/service-worker.js",
  "content/x-content.css",
  "content/x-content.js",
  "lib/capture-helpers.js"
];

function extensionIDFromKey(encodedKey) {
  const digest = createHash("sha256").update(Buffer.from(encodedKey, "base64")).digest();
  const firstHalf = digest.subarray(0, 16).toString("hex");
  return firstHalf.replace(/[0-9a-f]/g, (digit) => {
    return String.fromCharCode("a".charCodeAt(0) + Number.parseInt(digit, 16));
  });
}

const manifest = JSON.parse(await readFile(path.join(rootDirectory, "manifest.json"), "utf8"));
if (manifest.manifest_version !== 3) {
  throw new Error("Pinax must remain a Manifest V3 extension");
}

const extensionID = extensionIDFromKey(manifest.key);
if (extensionID !== expectedExtensionID) {
  throw new Error(`Manifest key generated ${extensionID}; expected ${expectedExtensionID}`);
}

const expectedPermissions = ["activeTab", "nativeMessaging", "scripting"];
if (JSON.stringify([...manifest.permissions].sort()) !== JSON.stringify(expectedPermissions.sort())) {
  throw new Error("Manifest permissions changed; review least-privilege guarantees before building");
}
if (manifest.host_permissions?.length) {
  throw new Error("Persistent host permissions are not expected; use activeTab and X content-script matches");
}

for (const relativePath of runtimeFiles) {
  const absolutePath = path.join(rootDirectory, relativePath);
  const fileStat = await stat(absolutePath);
  if (!fileStat.isFile()) {
    throw new Error(`Missing runtime file: ${relativePath}`);
  }

  if (relativePath.endsWith(".js")) {
    const source = await readFile(absolutePath, "utf8");
    new vm.Script(source, { filename: relativePath });
    if (/\beval\s*\(|\bnew\s+Function\s*\(/.test(source)) {
      throw new Error(`Remote-code-compatible construct found in ${relativePath}`);
    }
  }
}

await rm(outputDirectory, { recursive: true, force: true });
for (const relativePath of runtimeFiles) {
  const destination = path.join(outputDirectory, relativePath);
  await mkdir(path.dirname(destination), { recursive: true });
  await copyFile(path.join(rootDirectory, relativePath), destination);
}

process.stdout.write(`Built ${runtimeFiles.length} extension files in dist/ (ID ${extensionID}).\n`);
