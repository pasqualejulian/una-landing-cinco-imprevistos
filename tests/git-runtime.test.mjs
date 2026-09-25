import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

import { createGitRuntime } from "../src/git-runtime.mjs";

const baseHtml = `<!doctype html>
<html lang="es">
<head><meta charset="utf-8"><title>Mi idea</title><link rel="stylesheet" href="styles.css"></head>
<body><main><p class="eyebrow">Una idea lista para crecer</p><h1>Dale lugar a tu idea</h1><button>Empezá ahora</button></main></body>
</html>
`;
const baseCss = `:root { --cta: #6750a4; }
body { color: #211a2d; }
button { background: var(--cta); }
`;
const choiceHtml = {
  idea_vida: baseHtml.replace("Dale lugar a tu idea", "Dale vida a tu idea"),
  idea_proxima: baseHtml.replace("Dale lugar a tu idea", "Tu próxima idea empieza acá"),
};
const config = {
  baseHtml,
  baseCss,
  choiceHtml,
  titles: { idea_vida: "Dale vida a tu idea", idea_proxima: "Tu próxima idea empieza acá" },
};

function memoryStorage() {
  const values = new Map();
  return {
    values,
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
  };
}

async function runtime(storage = memoryStorage(), key = "mission") {
  return createGitRuntime({ storage, key, config });
}

test("creates a real base repository and derives choose/add/commit progress from Git", async () => {
  const app = await runtime();
  assert.deepEqual(app.snapshot().preview, { title: "Dale lugar a tu idea", button: "Empezá ahora", color: "#6750a4" });
  assert.equal(app.snapshot().commits, "1");
  assert.equal(app.snapshot().clean, true);
  assert.equal(app.graph().commits.length, 1);

  await app.choose("idea_vida");
  assert.equal(app.snapshot().chosen, true);
  assert.equal(app.snapshot().prepared, false);
  assert.equal(app.snapshot().preview.title, "Dale vida a tu idea");
  assert.equal(app.snapshot().clean, false);

  const diff = await app.execute("git diff");
  assert.equal(diff.exit_code, 0);
  assert.match(diff.output, /-.*Dale lugar a tu idea/);
  assert.match(diff.output, /\+.*Dale vida a tu idea/);

  assert.equal((await app.execute("git add index.html")).exit_code, 0);
  assert.equal(app.snapshot().prepared, true);
  assert.match((await app.execute("git status --short")).output, /^M  index\.html$/m);
  assert.match((await app.execute("git diff --cached")).output, /Dale vida a tu idea/);

  assert.equal((await app.execute('git commit -m "Elegir hero"')).exit_code, 0);
  assert.equal(app.snapshot().completed, true);
  assert.equal(app.snapshot().prepared, false);
  assert.equal(app.snapshot().commits, "2");
  assert.equal(app.snapshot().clean, true);
  const graph = app.graph();
  assert.equal(graph.branch, "main");
  assert.equal(graph.commits.length, 2);
  assert.equal(graph.commits[0].message, "Elegir hero");
  assert.deepEqual(graph.commits[0].parents, [graph.commits[1].hash]);
  assert.match((await app.execute("git log --oneline")).output, /Elegir hero/);
  assert.match((await app.execute("git show HEAD")).output, /Dale vida a tu idea/);
});

test("git add dot stages the selected HTML and the other title also completes", async () => {
  const app = await runtime();
  await app.choose("idea_proxima");
  assert.equal((await app.execute("git add .")).exit_code, 0);
  assert.equal(app.snapshot().prepared, true);
  await app.execute("git commit -m 'Guardar próxima idea'");
  assert.equal(app.snapshot().completed, true);
  assert.equal(app.snapshot().decision, "idea_proxima");
  assert.equal(app.snapshot().preview.title, "Tu próxima idea empieza acá");
});

test("persists partial and completed repositories byte-for-byte", async () => {
  const storage = memoryStorage();
  const first = await runtime(storage);
  await first.choose("idea_vida");
  await first.execute("git add index.html");

  const partial = await runtime(storage);
  assert.equal(partial.snapshot().prepared, true);
  assert.equal(partial.snapshot().completed, false);
  await partial.execute('git commit -m "Persistir versión"');

  const complete = await runtime(storage);
  assert.equal(complete.snapshot().completed, true);
  assert.equal(complete.graph().commits[0].message, "Persistir versión");
  const beforeReload = partial.exportFiles();
  const afterReload = complete.exportFiles();
  assert.deepEqual(Object.keys(afterReload), Object.keys(beforeReload));
  for (const path of Object.keys(beforeReload).filter((path) => path !== ".git/index")) {
    assert.equal(afterReload[path], beforeReload[path], path);
  }
});

test("exported bytes form an independently valid native Git repository", async (t) => {
  const app = await runtime();
  await app.choose("idea_vida");
  await app.execute("git add index.html");
  await app.execute('git commit -m "Verificar fuera del navegador"');

  const destination = mkdtempSync(join(tmpdir(), "omg-web-git-"));
  t.after(() => rmSync(destination, { recursive: true, force: true }));
  for (const [path, base64] of Object.entries(app.exportFiles())) {
    const absolute = join(destination, path);
    mkdirSync(dirname(absolute), { recursive: true });
    writeFileSync(absolute, Buffer.from(base64, "base64"));
  }
  assert.equal(execFileSync("git", ["fsck", "--full"], { cwd: destination, encoding: "utf8" }), "");
  assert.equal(execFileSync("git", ["status", "--porcelain"], { cwd: destination, encoding: "utf8" }), "");
  assert.equal(execFileSync("git", ["rev-list", "--count", "HEAD"], { cwd: destination, encoding: "utf8" }).trim(), "2");
  assert.equal(execFileSync("git", ["log", "-1", "--pretty=%s"], { cwd: destination, encoding: "utf8" }).trim(), "Verificar fuera del navegador");
  assert.equal(execFileSync("git", ["show", "HEAD:index.html"], { cwd: destination, encoding: "utf8" }), choiceHtml.idea_vida);
});

test("restart returns main to the base while discarded commits stay hidden", async () => {
  const app = await runtime();
  await app.choose("idea_vida");
  await app.execute("git add index.html");
  await app.execute('git commit -m "Primer intento"');
  const discarded = app.snapshot().head;

  const restart = await app.restart();
  assert.equal(restart.exit_code, 0);
  assert.equal(app.snapshot().chosen, false);
  assert.equal(app.snapshot().completed, false);
  assert.equal(app.snapshot().commits, "1");
  assert.equal(app.graph().commits.length, 1);
  assert.notEqual(app.snapshot().head, discarded);
  assert.equal(Object.keys(app.exportFiles()).some((path) => path === ".git/refs/guided/checkpoints/stage-0"), true);

  await app.choose("idea_proxima");
  await app.execute("git add index.html");
  await app.execute('git commit -m "Segundo intento"');
  assert.equal(app.snapshot().completed, true);
  assert.equal(app.graph().commits.length, 2);
  assert.equal(app.graph().commits.some((commit) => commit.hash === discarded), false);
});

test("rejects unsafe commands, missing files, premature and empty commits", async () => {
  const app = await runtime();
  const invalidChoice = await app.choose("idea_inexistente");
  assert.equal(invalidChoice.exit_code, 1);
  assert.match(invalidChoice.output, /no está disponible/);
  const rejected = [
    'git commit --allow-empty -m "extra"',
    "git add ../index.html",
    "git add --all",
    "git switch otra",
    "git status; touch /tmp/no",
    'git commit -m "$(touch /tmp/no)"',
    "git show main",
  ];
  for (const command of rejected) {
    const result = await app.execute(command);
    assert.equal(result.exit_code, 1, command);
    assert.equal(result.pretty_command, command);
  }
  assert.equal((await app.execute('git commit -m "Demasiado pronto"')).exit_code, 1);
  await app.choose("idea_vida");
  assert.equal((await app.execute("git add inexistente.html")).exit_code, 1);
  assert.equal(app.snapshot().prepared, false);
  assert.match(app.snapshot().feedback, /No encontré/);
  assert.equal((await app.execute('git commit -m "Vacío"')).exit_code, 1);
  assert.equal(app.snapshot().commits, "1");
  assert.equal(app.snapshot().completed, false);
});

test("extra repository files prevent prepared and completed validation", async () => {
  const storage = memoryStorage();
  const first = await runtime(storage);
  await first.choose("idea_vida");
  const saved = JSON.parse(storage.values.get("mission"));
  saved.files["extra.txt"] = Buffer.from("fuera del objetivo\n").toString("base64");
  storage.values.set("mission", JSON.stringify(saved));

  const resumed = await runtime(storage);
  assert.equal(resumed.snapshot().chosen, true);
  await resumed.execute("git add .");
  assert.equal(resumed.snapshot().prepared, false);
  await resumed.execute('git commit -m "Incluye un archivo extra"');
  assert.equal(resumed.snapshot().completed, false);
  assert.equal(resumed.snapshot().commits, "2");
});

test("rejects a second command while the first command owns the runtime", async () => {
  const app = await runtime();
  const first = app.execute("git status");
  const second = app.execute('git commit -m "Duplicado"');
  const [firstResult, secondResult] = await Promise.all([first, second]);
  assert.equal(firstResult.exit_code, 0);
  assert.equal(secondResult.exit_code, 1);
  assert.match(secondResult.output, /en ejecución/);
  assert.equal(app.snapshot().commits, "1");
});

test("a failed restart preserves the completed state and exposes the failure", async () => {
  const backing = memoryStorage();
  let failWrites = false;
  const storage = {
    getItem: backing.getItem,
    setItem(key, value) {
      if (failWrites) throw new Error("storage unavailable");
      backing.setItem(key, value);
    },
  };
  const app = await runtime(storage);
  await app.choose("idea_vida");
  await app.execute("git add index.html");
  await app.execute('git commit -m "Versión segura"');
  const head = app.snapshot().head;
  failWrites = true;
  const result = await app.restart();
  assert.equal(result.exit_code, 1);
  assert.match(result.output, /No pude reiniciar/);
  assert.equal(app.snapshot().completed, true);
  assert.equal(app.snapshot().decision, "idea_vida");
  assert.equal(app.snapshot().head, head);
  assert.match(app.snapshot().feedback, /No pude reiniciar/);
});
