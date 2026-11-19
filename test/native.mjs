import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const n = require(path.resolve(process.argv[2] ?? "shim/claude-native"));
const C = fs.constants;

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "cdl-native-"));
const root = path.join(tmp, "root");
fs.mkdirSync(path.join(root, "a", "b"), { recursive: true });
fs.writeFileSync(path.join(root, "a", "f"), "inside");
fs.writeFileSync(path.join(tmp, "secret"), "outside");
fs.symlinkSync(path.join(tmp, "secret"), path.join(root, "a", "leaflink"));
fs.symlinkSync(tmp, path.join(root, "dirlink"));
fs.symlinkSync("/proc/self/root", path.join(root, "magic"));

let failed = 0;
const pass = (name) => console.log(`ok   ${name}`);
const bad = (name, why) => {
  failed++;
  console.error(`FAIL ${name}: ${why}`);
};

async function refuses(name, fn, codes) {
  try {
    const r = await fn();
    if (typeof r === "number") fs.closeSync(r);
    bad(name, "allowed");
  } catch (e) {
    const code = /^([A-Z]+):/.exec(e.message)?.[1];
    codes.includes(code) ? pass(`${name} (${code})`) : bad(name, e.message);
  }
}

async function allows(name, fn) {
  try {
    await fn();
    pass(name);
  } catch (e) {
    bad(name, e.message);
  }
}

const r = await n.openRootDir(root);
const ro = C.O_RDONLY;

await allows("open inside", async () => {
  const fd = await n.openBeneath(r, ["a", "f"], ro, 0);
  if (fs.readFileSync(fd, "utf8") !== "inside") throw new Error("wrong content");
  fs.closeSync(fd);
});
await allows("read with a mode set", async () => {
  fs.closeSync(await n.openBeneath(r, ["a", "f"], ro, 0o600));
});
await refuses("leaf symlink", () => n.openBeneath(r, ["a", "leaflink"], ro, 0), ["ELOOP"]);
await refuses("dir symlink", () => n.openBeneath(r, ["dirlink", "secret"], ro, 0), ["ELOOP"]);
await refuses("magic link", () => n.openBeneath(r, ["magic", "etc", "passwd"], ro, 0), ["ELOOP"]);
await refuses("dotdot", () => n.openBeneath(r, ["..", "secret"], ro, 0), ["EXDEV"]);
await refuses("slash in segment", () => n.openBeneath(r, ["a/../../secret"], ro, 0), ["EXDEV"]);
await refuses("absolute segment", () => n.openBeneath(r, ["/etc/passwd"], ro, 0), ["EXDEV"]);
await refuses("nul byte", () => n.openBeneath(r, ["a\0b"], ro, 0), ["EXDEV"]);
await refuses("empty segment", () => n.openBeneath(r, ["a", "", "f"], ro, 0), ["EXDEV"]);
await refuses("too deep", () => n.openBeneath(r, Array(2000).fill("a"), ro, 0), ["ENAMETOOLONG"]);
await refuses("negative fd", () => n.openBeneath(-1, ["a", "f"], ro, 0), ["EBADF"]);
await refuses("create through dir symlink", () => n.openBeneath(r, ["dirlink", "planted"], C.O_WRONLY | C.O_CREAT, 0o600), ["ELOOP"]);
if (fs.existsSync(path.join(tmp, "planted"))) bad("create through dir symlink", "file appeared outside root");
await refuses("mkdir through dir symlink", () => n.mkdirBeneath(r, ["dirlink", "x"], 0o700), ["ELOOP"]);
await refuses("unlink through dir symlink", () => n.unlinkBeneath(r, ["dirlink", "secret"]), ["ELOOP"]);
await refuses("rename out", () => n.renameBeneath(r, ["a", "f"], ["dirlink", "stolen"]), ["ELOOP"]);
await refuses("link out", () => n.linkBeneath(r, ["a", "f"], ["dirlink", "stolen"]), ["ELOOP"]);
await refuses("readdir through dir symlink", () => n.readdirBeneath(r, ["dirlink"]), ["ELOOP"]);
await refuses("stat follows symlink", () => n.statBeneath(r, ["a", "leaflink"]), ["ELOOP"]);

await allows("lstat sees symlink", async () => {
  const s = await n.lstatBeneath(r, ["a", "leaflink"]);
  if ((s.mode & 0o170000) !== 0o120000) throw new Error("not a symlink");
});

await allows("hard link caught", async () => {
  const fd = await n.openBeneath(r, ["a", "f"], ro, 0);
  fs.linkSync(path.join(root, "a", "f"), path.join(root, "a", "f2"));
  try {
    await n.verifyLeafBeneath(r, ["a", "f"], fd);
    throw new Error("not caught");
  } catch (e) {
    if (!e.message.startsWith("EMLINK: handle-links")) throw e;
  } finally {
    fs.unlinkSync(path.join(root, "a", "f2"));
    fs.closeSync(fd);
  }
});

await allows("swapped file caught", async () => {
  const fd = await n.openBeneath(r, ["a", "f"], ro, 0);
  fs.renameSync(path.join(root, "a", "f"), path.join(root, "a", "f.old"));
  fs.writeFileSync(path.join(root, "a", "f"), "swapped");
  try {
    await n.verifyLeafBeneath(r, ["a", "f"], fd);
    throw new Error("not caught");
  } catch (e) {
    if (e.message !== "EMLINK: name-other") throw e;
  } finally {
    fs.closeSync(fd);
    fs.renameSync(path.join(root, "a", "f.old"), path.join(root, "a", "f"));
  }
});

await allows("rename onto free name won't clobber", async () => {
  fs.writeFileSync(path.join(root, "a", "new"), "new");
  try {
    await n.renameBeneathOntoFreeName(r, ["a", "new"], ["a", "f"]);
    throw new Error("clobbered");
  } catch (e) {
    if (!e.message.startsWith("EEXIST")) throw e;
  }
  if (fs.readFileSync(path.join(root, "a", "f"), "utf8") !== "inside") throw new Error("target changed");
  fs.unlinkSync(path.join(root, "a", "new"));
});

await allows("mkdir, create, rename, readdir, unlink, rmdir", async () => {
  await n.mkdirBeneath(r, ["a", "d"], 0o700);
  const w = await n.openBeneath(r, ["a", "d", "x"], C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600);
  fs.writeSync(w, "x");
  fs.closeSync(w);
  await n.renameBeneathOntoFreeName(r, ["a", "d", "x"], ["a", "d", "y"]);
  const l = await n.readdirBeneath(r, ["a", "d"]);
  if (l.entries.map((e) => e.name).join() !== "y") throw new Error("readdir wrong");
  await n.unlinkBeneath(r, ["a", "d", "y"]);
  await n.rmdirBeneath(r, ["a", "d"]);
});

await allows("readdir truncates", async () => {
  const l = await n.readdirBeneath(r, ["a"], 1);
  if (!l.truncated || l.entries.length !== 1) throw new Error("no truncation");
});

fs.closeSync(r);
if (fs.readFileSync(path.join(tmp, "secret"), "utf8") !== "outside") bad("outside file", "modified");
fs.rmSync(tmp, { recursive: true, force: true });

if (failed) {
  console.error(`${failed} native test(s) failed`);
  process.exit(1);
}
console.log("ok   native module passes all escape tests");
