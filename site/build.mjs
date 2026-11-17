// Builds site/dist. No dependencies. The telemetry on the page is computed
// here from the repo itself, so it can't drift from the code.
import { cpSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const site = dirname(fileURLToPath(import.meta.url));
const root = join(site, "..");
const dist = join(site, "dist");

const walk = (dir) =>
  readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)]);

const swift = (dir) => walk(join(root, dir)).filter((f) => f.endsWith(".swift"));

const commitFull = process.env.VERCEL_GIT_COMMIT_SHA
  || execSync("git rev-parse HEAD", { cwd: root }).toString().trim();

const facts = {
  version: readFileSync(join(root, "build.sh"), "utf8")
    .match(/CFBundleShortVersionString<\/key><string>([^<]+)</)[1],
  commit: commitFull.slice(0, 7),
  commitFull,
  swiftFiles: swift("Sources").length,
  tests: swift("Tests")
    .map((f) => (readFileSync(f, "utf8").match(/@Test\b/g) || []).length)
    .reduce((a, b) => a + b, 0),
};

rmSync(dist, { recursive: true, force: true });
cpSync(join(site, "src"), dist, { recursive: true });

const page = join(dist, "index.html");
const html = readFileSync(page, "utf8").replace(/\{\{(\w+)\}\}/g, (_, key) => {
  if (!(key in facts)) throw new Error(`No value for {{${key}}}`);
  return String(facts[key]);
});
writeFileSync(page, html);

console.log("built site/dist", facts);
