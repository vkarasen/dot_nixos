// CommonJS parser: extract every Tridactyl `:set` setting from
// src/lib/config.ts (the `default_config` class) as a flat JSON map.
//
// This runs inside the `tridactyl-index` derivation in
// modules/home/tridactyl/default.nix, against the pinned `tridactyl` flake
// input — not manually. The index is materialized at
// ~/.config/tridactyl/index.json by home-manager; no snapshot is committed.
//
// Usage (as invoked by the build):
//   NODE_PATH=<typescript lib> node _parse-config.cjs config.ts > settings.json
//
// Every key is namespaced with the `set.` prefix (e.g. `set.profiledir`,
// `set.update.nag`); the prefix is a namespace marker, not part of the
// literal `:set` name. For each property declaration on `default_config` it
// emits:
//   "set.<name>": { description, type, default, source, kind: "set" }
//
// Scope: this is a *settings* index, so fields that are mutated by a command
// other than `:set` are excluded entirely (see EXCLUDE), and for the remaining
// object-literal fields only the flattened `parent.child` entries are emitted
// (not the parent object blob). Exceptions: an object-literal field with no
// children (an empty map like `jsurls = {}`) is kept as a parent record so the
// setting is not silently lost.

const fs = require("fs")
const ts = require("typescript")

const file = process.argv[2] || "config.ts"
// Upstream path label used in the `source` field of every record.
const SOURCE_PATH = "src/lib/config.ts"
const src = fs.readFileSync(file, "utf8")
const sf = ts.createSourceFile(file, src, ts.ScriptTarget.Latest, /*setParentNodes*/ true)

function cleanJsdoc(raw) {
    let s = raw.trim()
    if (s.startsWith("/**")) s = s.slice(3)
    if (s.endsWith("*/")) s = s.slice(0, -2)
    const lines = s
        .split("\n")
        .map(l => l.replace(/^\s*\*? ?/, ""))
    while (lines.length && lines[0].trim() === "") lines.shift()
    while (lines.length && lines[lines.length - 1].trim() === "") lines.pop()
    return lines.join("\n").trim()
}

function jsdocFor(node) {
    const docs = node.jsDoc
    if (docs && docs.length) {
        return cleanJsdoc(docs[docs.length - 1].getText(sf))
    }
    return ""
}

// Fields that are NOT plain `:set` settings: mutated by `:bind`, `:alias`,
// `:seturl`/`:setmode`, `:abbreviate`, or internal storage. Omitted entirely.
const EXCLUDE = new Set([
    // keybinding maps - mutated with `:bind` / `bind [--mode=...]`
    "nmaps",
    "exmaps",
    "imaps",
    "inputmaps",
    "ignoremaps",
    "vmaps",
    "hintmaps",
    "browsermaps",
    // commandline aliases - mutated with `:alias` / `command alias`
    "exaliases",
    // per-site config - mutated with `:seturl` / `:unseturl`
    "subconfigs",
    // per-mode config - mutated with `:setmode` / `:unsetmode`
    "modesubconfigs",
    // ex-mode abbreviations - mutated with `:abbreviate`
    "abbreviations",
    // internal storage for `:reader`, not user-settable
    "reader_articles",
])

function nameText(name) {
    if (!name) return ""
    if (ts.isIdentifier(name) || ts.isStringLiteral(name) || ts.isNumericLiteral(name)) {
        return name.text
    }
    // ComputedPropertyName etc: strip brackets/quotes
    return name.getText(sf).replace(/^\[|\]$/g, "").replace(/^["'`]|["'`]$/g, "")
}

function lineOf(node) {
    return sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1
}

const out = {}

function record(node, key) {
    out["set." + key] = {
        description: jsdocFor(node),
        type: node.type ? node.type.getText(sf) : "",
        default: node.initializer ? node.initializer.getText(sf) : "",
        source: `${SOURCE_PATH}:${lineOf(node)}`,
        kind: "set",
    }
}

function flattenObject(prefix, objLit) {
    for (const prop of objLit.properties) {
        if (!prop.name) continue
        const key = `${prefix}.${nameText(prop.name)}`
        const isPropAssign = ts.isPropertyAssignment(prop) || ts.isShorthandPropertyAssignment(prop)
        const init = isPropAssign ? prop.initializer : undefined
        out["set." + key] = {
            description: jsdocFor(prop),
            type: prop.type ? prop.type.getText(sf) : "",
            default: init ? init.getText(sf) : "",
            source: `${SOURCE_PATH}:${lineOf(prop)}`,
            kind: "set",
        }
        if (init && ts.isObjectLiteralExpression(init)) {
            flattenObject(key, init)
        }
    }
}

// Locate `class default_config`
let cls = null
function visit(node) {
    if (ts.isClassDeclaration(node) && node.name && node.name.text === "default_config") {
        cls = node
        return
    }
    ts.forEachChild(node, visit)
}
visit(sf)
if (!cls) {
    console.error("ERROR: class default_config not found")
    process.exit(1)
}

for (const member of cls.members) {
    if (!ts.isPropertyDeclaration(member)) continue
    const key = nameText(member.name)
    if (!key) continue
    if (EXCLUDE.has(key)) continue

    const init = member.initializer
    if (init && ts.isObjectLiteralExpression(init)) {
        // Group/map field: emit only the flattened `parent.child` entries.
        const before = Object.keys(out).length
        flattenObject(key, init)
        if (Object.keys(out).length === before) {
            // Empty map: keep the parent so the setting is not lost.
            record(member, key)
        }
    } else {
        // Scalar field: plain top-level key.
        record(member, key)
    }
}

process.stdout.write(JSON.stringify(out, null, 2) + "\n")
