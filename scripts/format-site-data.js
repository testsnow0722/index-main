// One-shot helper to normalize js/site-data.js formatting.
// Reads the existing window.SITE_DATA assignment, then rewrites it
// with consistent 2-space indentation using JSON.stringify.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const dataPath = path.resolve(__dirname, "..", "js", "site-data.js");
const source = fs.readFileSync(dataPath, "utf8");

const sandbox = { window: {} };
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "site-data.js" });

const data = sandbox.window.SITE_DATA;
if (!data || typeof data !== "object") {
  throw new Error("window.SITE_DATA was not assigned by site-data.js");
}

const body = JSON.stringify(data, null, 2);
const output = `window.SITE_DATA = ${body};\n`;

fs.writeFileSync(dataPath, output, "utf8");
console.log(`Rewrote ${dataPath} (${output.length} bytes).`);
