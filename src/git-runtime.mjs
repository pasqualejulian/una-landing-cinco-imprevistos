import * as git from "isomorphic-git";
import { createFsFromVolume, Volume } from "memfs";
import { createTwoFilesPatch } from "diff";

const DIR = "/repo";
const INTERNAL_BASE_REF = "refs/guided/checkpoints/stage-0";
const AUTHOR = { name: "Oh My Git", email: "guided@ohmygit.invalid" };
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function bytesToBase64(bytes) {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function base64ToBytes(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

function makeFs(files = null) {
  const volume = new Volume();
  const fs = createFsFromVolume(volume);
  fs.mkdirSync(DIR, { recursive: true });
  if (files) {
    for (const [path, value] of Object.entries(files)) {
      const absolute = `${DIR}/${path}`;
      fs.mkdirSync(absolute.slice(0, absolute.lastIndexOf("/")), { recursive: true });
      fs.writeFileSync(absolute, base64ToBytes(value));
    }
  }
  return { volume, fs };
}

function allFiles(fs) {
  const result = {};
  const visit = (absolute, relative) => {
    for (const name of fs.readdirSync(absolute)) {
      const childAbsolute = `${absolute}/${name}`;
      const childRelative = relative ? `${relative}/${name}` : name;
      const stat = fs.statSync(childAbsolute);
      if (stat.isDirectory()) visit(childAbsolute, childRelative);
      else result[childRelative] = bytesToBase64(new Uint8Array(fs.readFileSync(childAbsolute)));
    }
  };
  visit(DIR, "");
  return result;
}

function readText(fs, filepath) {
  return decoder.decode(fs.readFileSync(`${DIR}/${filepath}`));
}

function parsePreview(html, css) {
  return {
    title: html.match(/<h1>([\s\S]*?)<\/h1>/)?.[1] ?? "",
    button: html.match(/<button>([\s\S]*?)<\/button>/)?.[1] ?? "",
    color: css.match(/--cta\s*:\s*([^;]+);/)?.[1].trim() ?? "",
  };
}

function friendlyError(error) {
  const message = String(error?.message ?? error).replace(/^Error:\s*/, "").trim();
  if (/No files added to commit|nothing to commit|NoChangesError/i.test(message)) {
    return "No hay cambios preparados para guardar.";
  }
  if (/ENOENT|Could not find|not found/i.test(message)) return "No encontré ese archivo en la landing.";
  return message || "Git no pudo ejecutar el comando.";
}

async function currentBlob(fs, oid, filepath) {
  try {
    return decoder.decode((await git.readBlob({ fs, dir: DIR, oid, filepath })).blob);
  } catch {
    return null;
  }
}

async function stagedBlob(fs, filepath) {
  let oid = null;
  await git.walk({
    fs,
    dir: DIR,
    trees: [git.STAGE()],
    map: async (path, [entry]) => {
      if (path === filepath && entry) oid = await entry.oid();
    },
  });
  if (!oid) return null;
  const object = await git.readObject({ fs, dir: DIR, oid, format: "content" });
  return decoder.decode(object.object);
}

async function commitTreeShape(fs, oid) {
  const { commit } = await git.readCommit({ fs, dir: DIR, oid });
  const files = [];
  const visit = async (treeOid, prefix = "") => {
    const { tree } = await git.readTree({ fs, dir: DIR, oid: treeOid });
    for (const entry of tree) {
      const path = prefix ? `${prefix}/${entry.path}` : entry.path;
      if (entry.type === "tree") await visit(entry.oid, path);
      else files.push({ path, mode: entry.mode, type: entry.type });
    }
  };
  await visit(commit.tree);
  return files.sort((a, b) => a.path.localeCompare(b.path));
}

function shortStatusLine(filepath, head, workdir, stage) {
  let x = " ";
  let y = " ";
  if (head === 0 && stage > 0) x = "A";
  else if (head > 0 && stage === 0) x = "D";
  else if (head !== stage) x = "M";
  if (stage === 0 && workdir > 0) y = "?";
  else if (stage > 0 && workdir === 0) y = "D";
  else if (workdir !== stage) y = "M";
  return `${x}${y} ${filepath}`;
}

export async function createGitRuntime({ storage, key, config }) {
  if (!storage || typeof storage.getItem !== "function" || typeof storage.setItem !== "function") {
    throw new TypeError("storage must provide getItem and setItem");
  }
  for (const field of ["baseHtml", "baseCss", "choiceHtml", "titles"]) {
    if (config?.[field] == null) throw new TypeError(`config.${field} is required`);
  }

  let fs;
  let decision = "";
  let feedback = "";
  let cachedSnapshot = null;
  let cachedGraph = null;
  let busy = false;
  let restored = false;

  const raw = storage.getItem(key);
  if (raw) {
    try {
      const saved = JSON.parse(raw);
      ({ fs } = makeFs(saved.files));
      decision = typeof saved.decision === "string" ? saved.decision : "";
      feedback = typeof saved.feedback === "string" ? saved.feedback : "";
      await git.resolveRef({ fs, dir: DIR, ref: "HEAD" });
      restored = true;
    } catch {
      fs = null;
      decision = "";
      feedback = "No pude recuperar la partida guardada. Empecé una nueva.";
    }
  }

  async function initialize() {
    ({ fs } = makeFs());
    await git.init({ fs, dir: DIR, defaultBranch: "main" });
    fs.writeFileSync(`${DIR}/index.html`, config.baseHtml);
    fs.writeFileSync(`${DIR}/styles.css`, config.baseCss);
    await git.add({ fs, dir: DIR, filepath: "index.html" });
    await git.add({ fs, dir: DIR, filepath: "styles.css" });
    const base = await git.commit({ fs, dir: DIR, message: "Base de la landing", author: AUTHOR });
    await git.writeRef({ fs, dir: DIR, ref: INTERNAL_BASE_REF, value: base, force: true });
  }
  if (!fs) await initialize();

  function persist() {
    storage.setItem(key, JSON.stringify({ version: 1, files: allFiles(fs), decision, feedback }));
  }

  async function refresh() {
    const head = await git.resolveRef({ fs, dir: DIR, ref: "HEAD" });
    const base = await git.resolveRef({ fs, dir: DIR, ref: INTERNAL_BASE_REF });
    const branch = await git.currentBranch({ fs, dir: DIR, fullname: false });
    const matrix = await git.statusMatrix({ fs, dir: DIR });
    const byPath = new Map(matrix.map((row) => [row[0], row.slice(1)]));
    const clean = matrix.every(([, headStatus, workdirStatus, stageStatus]) => headStatus === workdirStatus && workdirStatus === stageStatus);
    const html = readText(fs, "index.html");
    const css = readText(fs, "styles.css");
    const selectedHtml = config.choiceHtml[decision] ?? null;
    const chosen = Boolean(selectedHtml) && branch === "main" && head === base && html === selectedHtml && css === config.baseCss;
    const indexStatus = byPath.get("index.html") ?? [0, 0, 0];
    const stylesStatus = byPath.get("styles.css") ?? [0, 0, 0];
    const prepared = chosen && byPath.size === 2 && indexStatus[0] === 1 && indexStatus[1] === 2 && indexStatus[2] === 2 && stylesStatus.every((value) => value === 1);

    const logs = await git.log({ fs, dir: DIR, ref: "HEAD" });
    let completed = false;
    if (decision && logs.length === 2 && logs[1].oid === base && logs[0].commit.parent.length === 1 && logs[0].commit.parent[0] === base) {
      const committedHtml = await currentBlob(fs, logs[0].oid, "index.html");
      const committedCss = await currentBlob(fs, logs[0].oid, "styles.css");
      const baseShape = await commitTreeShape(fs, base);
      const headShape = await commitTreeShape(fs, logs[0].oid);
      completed = branch === "main" && clean && JSON.stringify(headShape) === JSON.stringify(baseShape) && committedHtml === selectedHtml && committedCss === config.baseCss && logs[0].commit.message.trim() !== "";
    }
    const effectiveChosen = chosen || completed;
    cachedSnapshot = {
      chosen: effectiveChosen,
      prepared,
      completed,
      can_continue: false,
      preview: parsePreview(html, css),
      commits: String(logs.length),
      head,
      clean,
      step: completed ? "stage_0_done" : prepared ? "commit_title" : effectiveChosen ? "add_title" : "choose_title",
      feedback,
      decision,
    };
    cachedGraph = {
      head,
      commits: await Promise.all(logs.map(async (entry) => ({
        hash: entry.oid,
        message: entry.commit.message.trim(),
        parents: [...entry.commit.parent],
        tree: entry.commit.tree,
      }))),
      branch: branch ?? "main",
    };
  }

  async function saveAndRefresh() {
    persist();
    await refresh();
  }

  async function fail(output, pretty_command = "") {
    feedback = output;
    try { persist(); } catch { /* Keep the failure visible in this session. */ }
    await refresh();
    return { exit_code: 1, output, pretty_command };
  }

  async function choose(id) {
    if (busy) {
      return { exit_code: 1, output: "Esperá a que termine el comando actual.", pretty_command: `choose ${id}` };
    }
    if (!(id in config.choiceHtml) || !(id in config.titles)) {
      return await fail("Esa opción no está disponible en esta misión.", `choose ${id}`);
    }
    if (cachedSnapshot.completed) {
      return await fail("Ya guardaste tu versión. Reiniciá la misión para elegir de nuevo.", `choose ${id}`);
    }
    const base = await git.resolveRef({ fs, dir: DIR, ref: INTERNAL_BASE_REF });
    const head = await git.resolveRef({ fs, dir: DIR, ref: "HEAD" });
    if (head !== base || !cachedSnapshot.clean) {
      return await fail("El repositorio no está en el punto inicial. Reiniciá la misión para elegir de nuevo.", `choose ${id}`);
    }
    decision = id;
    fs.writeFileSync(`${DIR}/index.html`, config.choiceHtml[id]);
    feedback = "Elegiste un título nuevo. Prepará index.html para incluirlo en la próxima versión.";
    await saveAndRefresh();
    return cachedSnapshot;
  }

  function validate(command) {
    if (["git status", "git status --short", "git log", "git log --oneline", "git diff", "git diff --cached", "git show", "git show HEAD"].includes(command)) return { verb: command.split(" ")[1] };
    const add = command.match(/^git add ([A-Za-z0-9_.-]+|\.)$/);
    if (add && !add[1].includes("..")) return { verb: "add", filepath: add[1] };
    const commit = command.match(/^git commit -m ("([^"$`\\\r\n]+)"|'([^'$`\\\r\n]+)')$/);
    if (commit && (commit[2] ?? commit[3]).trim()) return { verb: "commit", message: commit[2] ?? commit[3] };
    return null;
  }

  async function statusOutput(short) {
    const matrix = await git.statusMatrix({ fs, dir: DIR });
    const changed = matrix.filter(([, head, workdir, stage]) => !(head === workdir && workdir === stage));
    if (short) return changed.map((row) => shortStatusLine(...row)).join("\n");
    const branch = await git.currentBranch({ fs, dir: DIR, fullname: false });
    if (!changed.length) return `En la rama ${branch}\nno hay nada para guardar, el árbol de trabajo está limpio`;
    const staged = changed.filter(([, head, , stage]) => head !== stage).map(([path]) => `  modificado: ${path}`);
    const unstaged = changed.filter(([, , workdir, stage]) => workdir !== stage).map(([path]) => `  modificado: ${path}`);
    return [`En la rama ${branch}`, staged.length ? `Cambios preparados:\n${staged.join("\n")}` : "", unstaged.length ? `Cambios no preparados:\n${unstaged.join("\n")}` : ""].filter(Boolean).join("\n\n");
  }

  async function diffOutput(cached) {
    const head = await git.resolveRef({ fs, dir: DIR, ref: "HEAD" });
    const matrix = await git.statusMatrix({ fs, dir: DIR });
    const patches = [];
    for (const [filepath, headStatus, workdirStatus, stageStatus] of matrix) {
      if (cached ? headStatus === stageStatus : workdirStatus === stageStatus) continue;
      const before = cached
        ? ((await currentBlob(fs, head, filepath)) ?? "")
        : ((await stagedBlob(fs, filepath)) ?? "");
      const after = cached ? ((await stagedBlob(fs, filepath)) ?? "") : (fs.existsSync(`${DIR}/${filepath}`) ? readText(fs, filepath) : "");
      patches.push(createTwoFilesPatch(`a/${filepath}`, `b/${filepath}`, before, after, "HEAD", cached ? "index" : "working tree"));
    }
    return patches.join("\n").trim();
  }

  async function logOutput(oneline) {
    const logs = await git.log({ fs, dir: DIR, ref: "HEAD" });
    if (oneline) return logs.map((entry) => `${entry.oid.slice(0, 7)} ${entry.commit.message.trim()}`).join("\n");
    return logs.map((entry) => `commit ${entry.oid}\nAuthor: ${entry.commit.author.name} <${entry.commit.author.email}>\n\n    ${entry.commit.message.trim()}`).join("\n\n");
  }

  async function showOutput() {
    const head = await git.resolveRef({ fs, dir: DIR, ref: "HEAD" });
    const record = await git.readCommit({ fs, dir: DIR, oid: head });
    let patch = "";
    if (record.commit.parent.length) {
      const parent = record.commit.parent[0];
      const paths = new Set([...(await git.listFiles({ fs, dir: DIR, ref: parent })), ...(await git.listFiles({ fs, dir: DIR, ref: head }))]);
      const patches = [];
      for (const filepath of [...paths].sort()) {
        const before = (await currentBlob(fs, parent, filepath)) ?? "";
        const after = (await currentBlob(fs, head, filepath)) ?? "";
        if (before !== after) patches.push(createTwoFilesPatch(`a/${filepath}`, `b/${filepath}`, before, after, parent.slice(0, 7), head.slice(0, 7)));
      }
      patch = patches.join("\n");
    }
    return `commit ${head}\nAuthor: ${record.commit.author.name} <${record.commit.author.email}>\n\n    ${record.commit.message.trim()}${patch ? `\n\n${patch.trim()}` : ""}`;
  }

  async function execute(input) {
    const command = String(input).trim();
    if (busy) return { exit_code: 1, output: "Ya hay un comando de Git en ejecución.", pretty_command: command };
    busy = true;
    try {
      const parsed = validate(command);
      if (!parsed) return await fail("Ese comando no está disponible en esta misión.", command);
      let output = "";
      if (parsed.verb === "status") output = await statusOutput(command.endsWith("--short"));
      else if (parsed.verb === "log") output = await logOutput(command.endsWith("--oneline"));
      else if (parsed.verb === "diff") output = await diffOutput(command.endsWith("--cached"));
      else if (parsed.verb === "show") output = await showOutput();
      else if (parsed.verb === "add") {
        if (!decision) return await fail("Primero elegí uno de los títulos de la misión.", command);
        const targets = parsed.filepath === "."
          ? (await git.statusMatrix({ fs, dir: DIR })).filter(([, , workdir]) => workdir > 0).map(([path]) => path)
          : [parsed.filepath];
        if (!targets.length || targets.some((path) => !fs.existsSync(`${DIR}/${path}`))) return await fail("No encontré ese archivo en la landing.", command);
        for (const filepath of targets) await git.add({ fs, dir: DIR, filepath });
        feedback = "El cambio quedó preparado. Ahora guardalo con un commit.";
      } else if (parsed.verb === "commit") {
        if (!decision) return await fail("Primero elegí un título.", command);
        const staged = (await git.statusMatrix({ fs, dir: DIR })).some(([, headStatus, , stageStatus]) => headStatus !== stageStatus);
        if (!staged) return await fail("No hay cambios preparados para guardar.", command);
        const oid = await git.commit({ fs, dir: DIR, message: parsed.message, author: AUTHOR });
        output = `[main ${oid.slice(0, 7)}] ${parsed.message}`;
        feedback = "Guardaste una versión real de la landing.";
      }
      await saveAndRefresh();
      if (["status", "log", "diff", "show"].includes(parsed.verb)) feedback = output || "El comando terminó sin mostrar cambios.";
      else if (!cachedSnapshot.completed && parsed.verb === "commit") feedback = "El commit no coincide con el objetivo de la misión. Reiniciá para volver al punto inicial.";
      await saveAndRefresh();
      return { exit_code: 0, output, pretty_command: command };
    } catch (error) {
      return await fail(friendlyError(error), command);
    } finally {
      busy = false;
    }
  }

  async function restart() {
    if (busy) return { exit_code: 1, output: "Ya hay una operación de Git en ejecución.", pretty_command: "restart" };
    busy = true;
    const backup = { files: allFiles(fs), decision, feedback };
    try {
      const base = await git.resolveRef({ fs, dir: DIR, ref: INTERNAL_BASE_REF });
      await git.writeRef({ fs, dir: DIR, ref: "refs/heads/main", value: base, force: true });
      await git.checkout({ fs, dir: DIR, ref: "main", force: true });
      decision = "";
      feedback = "Volviste a la landing inicial. Elegí un título para probar de nuevo.";
      await saveAndRefresh();
      return { exit_code: 0, output: feedback, pretty_command: "restart" };
    } catch (error) {
      ({ fs } = makeFs(backup.files));
      decision = backup.decision;
      feedback = `No pude reiniciar la misión: ${friendlyError(error)}`;
      try { persist(); } catch { /* The in-memory failure remains visible. */ }
      await refresh();
      return { exit_code: 1, output: feedback, pretty_command: "restart" };
    } finally {
      busy = false;
    }
  }

  await refresh();
  if (!restored) persist();
  return {
    choose,
    execute,
    restart,
    snapshot: () => structuredClone(cachedSnapshot),
    graph: () => structuredClone(cachedGraph),
    exportFiles: () => ({ ...allFiles(fs) }),
  };
}

// Shared repository primitives used by the continuous campaign as well.
export {makeFs, allFiles, readText, parsePreview, friendlyError, currentBlob, stagedBlob, commitTreeShape, shortStatusLine};
