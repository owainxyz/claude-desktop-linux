import fs from "node:fs";
import path from "node:path";

const app = process.argv[2];
const build = path.join(app, ".vite/build");
const here = path.dirname(new URL(import.meta.url).pathname);

fs.copyFileSync(path.join(here, "../compat/linux-compat.js"), path.join(build, "linux-compat.js"));
const pkg = JSON.parse(fs.readFileSync(path.join(app, "package.json"), "utf8"));
const entry = path.join(app, pkg.main);
const src = fs.readFileSync(entry, "utf8");
const inject = 'require("./linux-compat.js");';
if (!src.startsWith(inject)) fs.writeFileSync(entry, inject + src);
console.log("ok   linux-compat injected into", pkg.main);
