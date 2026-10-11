// CommonJS parser: build a flat JSON index of every Firefox pref from the
// version-pinned Firefox sources (used by the `ffprefs-index` derivation in
// modules/home/browser/default.nix).
//
// This runs inside the derivation against the pinned Firefox — not manually.
// The index is materialized at ~/.config/ffprefs/index.json by home-manager;
// no snapshot is committed.
//
// Inputs (all pinned to the installed Firefox via the repo's nixpkgs):
//   argv[1]    = StaticPrefList.yaml (from firefox-unwrapped.src): the
//                canonical C++-defined static prefs — explicit `type:` plus a
//                `#` doc-comment description.
//   argv[2..]  = the JS default-pref files with RESOLVED values, pulled from
//                the gre / browser omni.ja archives plus the two unpacked
//                files (greprefs.js, PdfJsDefaultPrefs.js, firefox.js,
//                firefox-branding.js, debugger.js, channel-prefs.js,
//                nixos-default-prefs.js). The build has already applied every
//                #ifdef, so these are the effective on-system defaults.
//   env FFPREF_DESC_FILES = whitespace-separated DESCRIPTION-ONLY source files
//                (modules/libpref/init/all.js + browser/app/profile/firefox.js
//                from the same tarball). The resolved omni files have their
//                comments stripped, so these carry the `//` blocks. They never
//                contribute a name, only a description.
//
// Merge rules (per name):
//   universe   = names from StaticPrefList.yaml ∪ the resolved omni/unpacked JS.
//   type       = StaticPrefList `type:` (normalized) when present, else inferred
//                from the omni JS literal.
//   description= StaticPrefList doc comment if non-empty, else the source-JS
//                `//` block from FFPREF_DESC_FILES, else "".
//   default    = the omni JS value when present (it overrides the C++ static
//                default), else the StaticPrefList `value`.
//   source     = the file:line that supplied `default`.
//   sources    = every file:line the pref appears in.
// `default` is ALWAYS a string; `type` disambiguates.

const fs = require("fs")

function basename(p) {
  return p.split("/").pop()
}

// Strip one pair of matching surrounding quotes; otherwise return as-is.
function stripQuotes(v) {
  const s = v.trim()
  if (s.length >= 2) {
    const a = s[0]
    const b = s[s.length - 1]
    if ((a === '"' && b === '"') || (a === "'" && b === "'")) {
      return s.slice(1, -1)
    }
  }
  return s
}

// Normalize a C++ static-pref type to {bool,int,string,float,other}.
function normType(t) {
  const s = (t || "").trim()
  if (/bool/i.test(s)) return "bool"
  if (/int/i.test(s)) return "int"
  if (/string/i.test(s)) return "string"
  if (/float|double/i.test(s)) return "float"
  return "other"
}

// Infer a type from a JS literal (raw, pre-strip).
function inferType(raw) {
  const v = raw.trim()
  if (v === "true" || v === "false") return "bool"
  if (v.startsWith('"') || v.startsWith("'")) return "string"
  if (/^[-+]?[0-9]/.test(v) && /[.eE]/.test(v)) return "float"
  if (/^[-+]?[0-9]+$/.test(v)) return "int"
  return "other"
}

// Extract a StaticPrefList YAML scalar (may be quoted; may carry a trailing
// inline `#` comment, but not inside quotes). A `@TOKEN@` build token is kept
// verbatim.
function spValue(raw) {
  const v = raw.trim()
  if (v.startsWith('"')) {
    const end = v.indexOf('"', 1)
    return end === -1 ? v : v.slice(1, end)
  }
  if (v.startsWith("'")) {
    const end = v.indexOf("'", 1)
    return end === -1 ? v : v.slice(1, end)
  }
  const hash = v.indexOf("#")
  return (hash === -1 ? v : v.slice(0, hash)).trim()
}

// C/C++ preprocessor directives and //@line source-map markers are structural,
// not descriptions — skip them without disturbing the comment buffer.
function isCppDirective(s) {
  return /^#\s*(if|ifdef|ifndef|else|elif|endif|define|undef|include|pragma|line)\b/.test(s)
}
function isSourceMap(s) {
  return /^\/\/@line\b/.test(s)
}

// name -> {type, value, desc, line}
const sp = {}
// name -> {raw, line, file}  (resolved JS value; last writer wins)
const js = {}
// name -> description, from DESCRIPTION-ONLY source-JS files (first wins)
const jsDesc = {}
// name -> [ "file:line", ... ] in first-seen order
const sources = {}
function addSource(name, label) {
  ;(sources[name] ||= []).push(label)
}

const PREF_RE =
  /^(?:sticky_)?pref\s*\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*(.+)\)\s*;\s*(?:\/\/.*)?$/

function parseStatic(file) {
  let text
  try {
    text = fs.readFileSync(file, "utf8")
  } catch (e) {
    process.stderr.write(`warn: cannot read ${file}: ${e.message}\n`)
    return
  }
  const label = basename(file)
  const lines = text.split("\n")
  let commentBuf = []
  let cur = null
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].replace(/\r$/, "").trim()
    if (t === "") {
      commentBuf = []
      cur = null
      continue
    }
    if (t.startsWith("#")) {
      if (cur === null) commentBuf.push(t.replace(/^#\s?/, ""))
      continue
    }
    // `-\s+name:` — any whitespace after the dash (the file mixes `- name:`
    // and `-   name:`).
    const mName = /^-\s+name:\s*(.+)$/.exec(t)
    if (mName) {
      const name = mName[1].trim()
      cur = {name, type: "", value: "", desc: commentBuf.join("\n"), line: i + 1}
      sp[name] = cur
      addSource(name, `${label}:${i + 1}`)
      commentBuf = []
      continue
    }
    if (cur) {
      const mType = /^type:\s*(.+)$/.exec(t)
      if (mType) {
        cur.type = mType[1].trim()
        continue
      }
      const mValue = /^value:\s*(.+)$/.exec(t)
      if (mValue) {
        cur.value = mValue[1].trim()
        continue
      }
    }
  }
}

// values: contribute names/values/sources. descriptions: harvest `//` blocks
// into jsDesc (description-only; never adds a name).
function parseJs(file, {values, descriptions}) {
  let text
  try {
    text = fs.readFileSync(file, "utf8")
  } catch (e) {
    process.stderr.write(`warn: cannot read ${file}: ${e.message}\n`)
    return
  }
  const label = basename(file)
  const lines = text.split("\n")
  let docBuf = []
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].replace(/\r$/, "").trim()
    if (t === "") {
      docBuf = []
      continue
    }
    if (isCppDirective(t) || isSourceMap(t)) continue
    if (t.startsWith("//")) {
      if (descriptions) docBuf.push(t.replace(/^\/\/\s?/, ""))
      continue
    }
    if (t.startsWith("/*") || t.startsWith("*")) {
      if (descriptions) docBuf.push(t.replace(/^[/*]+\s?/, "").replace(/\s*\*+\/$/, ""))
      continue
    }
    const m = PREF_RE.exec(t)
    if (!m) {
      docBuf = []
      continue
    }
    const name = m[1]
    if (values) {
      js[name] = {raw: m[2].trim(), line: i + 1, file: label}
      addSource(name, `${label}:${i + 1}`)
    }
    if (descriptions) {
      const d = docBuf.join("\n").trim()
      if (d && !(name in jsDesc)) jsDesc[name] = d
    }
    docBuf = []
  }
}

parseStatic(process.argv[2])
for (const f of process.argv.slice(3)) parseJs(f, {values: true, descriptions: false})
for (const f of (process.env.FFPREF_DESC_FILES || "").trim().split(/\s+/).filter(Boolean)) {
  parseJs(f, {values: false, descriptions: true})
}

const out = {}
const names = new Set([...Object.keys(sp), ...Object.keys(js)])
for (const name of [...names].sort()) {
  const s = sp[name]
  const j = js[name]
  const type = s ? normType(s.type) : inferType(j.raw)
  const description = s && s.desc ? s.desc : jsDesc[name] || ""
  const def = j ? stripQuotes(j.raw) : spValue(s.value)
  const source = j ? `${j.file}:${j.line}` : `${basename(process.argv[2])}:${s.line}`
  out[name] = {type, default: def, description, source, sources: sources[name] || []}
}

const keys = Object.keys(out)
const described = keys.filter(k => out[k].description).length
const pct = keys.length ? Math.round((described / keys.length) * 1000) / 10 : 0
process.stderr.write(`keys=${keys.length} described=${described} (${pct}%)\n`)
process.stdout.write(JSON.stringify(out, null, 2) + "\n")
