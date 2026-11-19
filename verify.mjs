import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const [resDir, integrityFile, dropList] = process.argv.slice(2);
const dropped = [];
const expected = JSON.parse(fs.readFileSync(integrityFile, "utf8"));
const sha256 = (b) => crypto.createHash("sha256").update(b).digest("hex");

let files = 0;
let bad = 0;
const fail = (msg) => {
  bad++;
  console.error(`FAIL ${msg}`);
};

function readHeader(fd) {
  const pre = Buffer.alloc(16);
  fs.readSync(fd, pre, 0, 16, 0);
  const headerSize = pre.readUInt32LE(4);
  const len = pre.readUInt32LE(12);
  const raw = Buffer.alloc(len);
  fs.readSync(fd, raw, 0, len, 16);
  return { raw, dataStart: 8 + headerSize };
}

function checkFile(name, node, buf) {
  files++;
  const want = node.integrity;
  if (!want || want.algorithm !== "SHA256") return fail(`${name}: no sha256 integrity`);
  if (sha256(buf) !== want.hash) return fail(`${name}: hash mismatch`);
  const bs = want.blockSize;
  for (let i = 0, o = 0; o < buf.length || i === 0; i++, o += bs) {
    if (sha256(buf.subarray(o, o + bs)) !== want.blocks[i]) return fail(`${name}: block ${i} mismatch`);
    if (buf.length === 0) break;
  }
}

function walk(asarPath, fd, dataStart, dir, rel) {
  for (const [name, node] of Object.entries(dir.files ?? {})) {
    const r = rel ? `${rel}/${name}` : name;
    if (node.files) {
      walk(asarPath, fd, dataStart, node, r);
    } else if (node.link) {
      continue;
    } else if (node.unpacked) {
      const p = path.join(`${asarPath}.unpacked`, r);
      if (!fs.existsSync(p)) return fail(`${r}: unpacked file missing`);
      const buf = fs.readFileSync(p);
      if (sha256(buf) !== node.integrity?.hash && buf.subarray(0, 2).toString() === "MZ") {
        dropped.push(r);
        continue;
      }
      checkFile(r, node, buf);
    } else {
      const buf = Buffer.alloc(node.size);
      fs.readSync(fd, buf, 0, node.size, dataStart + Number(node.offset));
      checkFile(r, node, buf);
    }
  }
}

for (const entry of expected) {
  const name = entry.file.split("\\").pop();
  const asarPath = path.join(resDir, name);
  const fd = fs.openSync(asarPath, "r");
  const { raw, dataStart } = readHeader(fd);
  if (entry.alg !== "SHA256" || sha256(raw) !== entry.value) {
    fail(`${name}: header does not match the signed exe`);
    continue;
  }
  walk(asarPath, fd, dataStart, JSON.parse(raw.toString("utf8")), "");
  fs.closeSync(fd);
}

if (bad) {
  console.error(`${bad} problem(s), refusing to build`);
  process.exit(1);
}
if (dropList) fs.writeFileSync(dropList, dropped.join("\n") + (dropped.length ? "\n" : ""));
console.log(`ok   ${files} files match the signed exe, ${dropped.length} re-signed windows binaries to drop`);
