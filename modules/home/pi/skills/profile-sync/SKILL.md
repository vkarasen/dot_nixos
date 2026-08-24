---
name: profile-sync
description: Compare the digital twin to the LinkedIn profile and produce
  paste-ready proposed changes per section. Load when asked to review, audit,
  or update a LinkedIn profile.
---

# LinkedIn profile sync

There is no write API — all proposed changes are delivered as paste-ready copy
for the user to apply manually.

---

## 1. Load the digital twin

Load the `obsidian-vault-read` skill, then fetch these notes from
`$OBSIDIAN_GLOBAL_VAULT_DIR/memory/identity/`:

- `professional-summary` — headline framing, narrative, location/availability
- `work-history` — roles, dates, concrete examples
- `skills-inventory` — proficiency levels, what to surface vs. omit
- `education` — credentials, publications, patents
- `disclosure-rules` — **read this before writing anything**. Use the
  **"LinkedIn / public"** column throughout. LinkedIn is permanently indexed —
  apply that column even when a detail feels minor.

---

## 2. Fetch LinkedIn data

Load the `linkedin-profile` skill for API mechanics. Fetch:

```text
PROFILE  PROFILE_SUMMARY  POSITIONS  EDUCATION  SKILLS  LANGUAGES
CERTIFICATIONS  PUBLICATIONS  PATENTS  HONORS  PROJECTS
```

---

## 3. Gap analysis

Compare twin to LinkedIn section by section and present:

```text
## Gap analysis

### Headline
Current: "..."
Twin suggests: "..."
Delta: [what to change and why]

### About / Summary
Current: [first ~200 chars or full if short]
Delta: [missing framing, stale content, tone issues]

### Experience — <Role at Org>
Current bullets: [...]
Delta: [missing details, stale phrasing, stronger claims available]

### Skills
In twin but missing on LinkedIn: [list]
On LinkedIn but not in twin (consider removing): [list]

### Education / Certifications / Publications / Patents
Gaps or stale entries: [list]

### Overall priority
[High / medium / low — ordered by impact]
```

Present the full gap analysis and wait for acknowledgement before writing
proposed copy.

---

## 4. Write proposed copy

For each section with a material delta, write paste-ready text:

- **Headline**: ≤220 characters
- **About**: 2–4 short paragraphs; first-person or third-person matching
  current style; slightly more narrative than a CV is fine, but no fluffy
  adjectives
- **Experience bullets**: active verbs, named technologies, verifiable
  outcomes — same discipline as the CV, phrasing can be marginally less terse
  since readers are not skimming a one-page document

Where the twin contains a stronger claim that would require the internal column
of `disclosure-rules`, write the LinkedIn-safe version and add:
`[note: stronger claim possible — check disclosure-rules before deciding]`

Deliver all proposed changes together in one block.

---

## Prose style

- Active verbs: "Built", "Designed", "Led", "Shipped"
- Named technologies over generic descriptions
- Verifiable outcomes where they exist (patent numbers, published papers,
  public tapeouts)
- Avoid: "passionate about", "results-driven", "dynamic", "leveraged",
  vague impact claims without a concrete anchor
