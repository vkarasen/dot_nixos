// CommonJS parser: extract every Tridactyl ex command from src/excmds.ts
// as a flat JSON map. Every key is namespaced with the `excmd.` prefix (e.g.
// `excmd.restart`); the prefix is a namespace marker, not part of the literal
// command name:
//   "excmd.<name>": { description, params, source, mode, kind: "excmd" }.
//
// Style mirrors _parse-config.cjs (require('typescript'), ts.createSourceFile,
// AST walk, cleanJsdoc helper). Intended to run against the pinned `tridactyl`
// flake input, not manually.
//
// Usage:
//   NODE_PATH=<typescript lib> node _parse-excmds.cjs <path>/src/excmds.ts > excmds.json
//
// For each top-level `export function name(...)` / `export async function
// name(...)` it emits:
//   description - JSDoc body with /** */ and leading * markers stripped,
//                 inner markdown kept
//   params      - [{ name, type }] from the signature (type "" if untyped)
//   source      - "src/excmds.ts:<line>"
//   mode        - "background" / "content" / "" from the //#background /
//                 //#content macro comment
//
// Non-function exports (constants, classes, type aliases, re-exports) are
// skipped.

const fs = require("fs")
const ts = require("typescript")

const file = process.argv[2] || "excmds.ts"
// Upstream path label used in the `source` field of every record.
const SOURCE_PATH = "src/excmds.ts"
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

function lineOf(node) {
    return sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1
}

// The `//#background` / `//#content` macro comment sits between the JSDoc and
// the signature. Scan the leading trivia comment ranges for a line comment
// whose text is exactly `//#background` or `//#content` (the `_helper`
// variants used before imports must not match).
function modeFor(node) {
    const ranges = ts.getLeadingCommentRanges(src, node.getFullStart()) || []
    for (const r of ranges) {
        const text = src.slice(r.pos, r.end)
        if (text === "//#background") return "background"
        if (text === "//#content") return "content"
    }
    return ""
}

// Parameter name as written: identifier, or the raw binding text for a
// destructured param. The `...` rest marker lives on dotDotDotToken, not on
// `name`, so using the name node never picks up the rest marker or the type
// annotation.
function paramName(p) {
    if (ts.isIdentifier(p.name)) return p.name.text
    return p.name.getText(sf)
}

function paramsFor(node) {
    return node.parameters.map(p => ({
        name: paramName(p),
        type: p.type ? p.type.getText(sf) : "",
    }))
}

const out = {}

function visit(node) {
    if (ts.isFunctionDeclaration(node) && node.name) {
        // Only exported function declarations are ex commands.
        const mods = ts.getModifiers(node) || []
        const exported = mods.some(m => m.kind === ts.SyntaxKind.ExportKeyword)
        if (exported) {
            const key = "excmd." + node.name.text
            out[key] = {
                description: jsdocFor(node),
                params: paramsFor(node),
                source: `${SOURCE_PATH}:${lineOf(node)}`,
                mode: modeFor(node),
                kind: "excmd",
            }
        }
    }
    ts.forEachChild(node, visit)
}
visit(sf)

process.stdout.write(JSON.stringify(out, null, 2) + "\n")
