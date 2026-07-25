# Design: `design-pattern-advisor` Skill

**Date**: 2026-07-25
**Status**: Approved (pending implementation plan)

## Problem

`ddd-domain-modeling`'s stage 4 (`references/4-ood-patterns.md`) already suggests design
patterns based on context, but the signal table only covers 7 patterns (Strategy, Builder,
State, Observer, Factory, Adapter, Decorator), each with a single-line signal/rationale. A
10-part design pattern course (subtitles copied into
`31 DesignPattern課程影片-字幕/`) covers 10 patterns, 6 of which
(Template Method, Chain of Responsibility, Command, Proxy, Facade, Composite) are missing
entirely. The existing entries are also too shallow to explain *why* a pattern fits or what
it costs once applied.

The pattern knowledge also needs to be reusable by other skills in this repo in the future
(`java-clean-arch-codegen`, `go-clean-arch-codegen`), so it shouldn't live embedded inside
`ddd-domain-modeling`.

## Goals

- Broaden pattern coverage from 7 to 13 patterns.
- Deepen each pattern's write-up so the reasoning ("why this pattern, what does applying it
  cost") is explicit, not just a one-line signal.
- Make the knowledge base a standalone, shareable skill — not just an internal file of
  `ddd-domain-modeling`.
- Integrate it into `ddd-domain-modeling` stage 4 so pattern suggestions come from this
  shared source instead of a duplicated table.

## Non-goals

- Wiring `java-clean-arch-codegen` / `go-clean-arch-codegen` into this knowledge base. The
  skill is designed to be shareable, but actually integrating those two skills is future
  work, out of scope here.
- Code generation. `design-pattern-advisor` is advisory only — it explains and shows
  pseudocode, it does not write production code for the caller.

## Design

### New skill: `design-pattern-advisor`

Standalone, stateless knowledge-base skill. Structure:

```
design-pattern-advisor/
├── SKILL.md                          # triggers, usage, phrasing guidance
└── references/
    ├── signal-table.md               # master index: signal → pattern → category → link
    └── patterns/
        ├── strategy.md
        ├── template-method.md
        ├── chain-of-responsibility.md
        ├── observer.md
        ├── command.md
        ├── state.md
        ├── proxy.md
        ├── facade.md
        ├── adapter.md
        ├── composite.md
        ├── builder.md
        ├── factory.md
        └── decorator.md
```

**Triggers** (in `SKILL.md` description): standalone questions like "這裡要不要套 design
pattern", "這個情境適合什麼設計模式", plus being invoked by other skills (currently
`ddd-domain-modeling` stage 4) that need pattern candidates for a described variation point.

### Per-pattern file format

Each `references/patterns/<name>.md` uses a 4-part pattern-form (Context / Forces /
Solution / Resulting Context), chosen so the reasoning behind a suggestion and its
consequences are both visible instead of a bare recommendation:

```markdown
# <Pattern Name>

## Context
(1-2 sentences: what kind of module/scenario this variation point typically shows up in)

## Forces
(the competing pressures pulling against each other in this context — e.g. "don't want to
touch existing classes when adding an algorithm" vs "callers want a single simple
interface" vs "avoid if/else sprawl on type". Whether these forces are *actually* in
tension is the practical test for whether it's worth applying the pattern now.)

## Solution
(how the pattern resolves the forces above; pseudocode showing structure before/after,
language-agnostic)

## Resulting Context
(what's gained, and what new cost/complexity appears — e.g. "adding an algorithm no longer
touches existing code, but the number of classes grows; overkill if the scenario stays
simple")
```

There is no separate "apply now vs. wait" field — that judgment is meant to fall out of
whether Forces are genuinely in conflict and whether the Resulting Context cost is worth
it, per the user's request to make "套用原因跟結果" (the reason and the result) visible
directly.

`signal-table.md` stays a flat quick-reference table:

```markdown
| 變異點訊號 | Pattern | 分類 | 詳解 |
|---|---|---|---|
| 同一動作依類型分支不同算法(if/switch on type) | Strategy | 行為型 | patterns/strategy.md |
...
```

### Content sources (13 patterns, two groups)

| Group | Patterns | Source |
|---|---|---|
| Course-backed (10) | Strategy, Template Method, Chain of Responsibility, Observer, Command, State, Proxy, Facade, Adapter, Composite | Extract signals/forces/trade-offs from `31 DesignPattern課程影片-字幕/*.txt`, cross-check against standard GoF knowledge to fill gaps the course doesn't cover |
| GoF-only (3) | Builder, Factory, Decorator | No course material; write from general GoF knowledge, reusing content already implicit in the current `4-ood-patterns.md` table |

### Changes to `ddd-domain-modeling`

**`SKILL.md`**: remove "這裡要不要套 design pattern" from the trigger-phrase list in the
description — that generic question is now owned by `design-pattern-advisor`. Domain-model
specific triggers (event storming, aggregate boundaries, etc.) are unchanged.

**`references/4-ood-patterns.md`**:
- Remove the embedded "訊號 → 候選對照" table and the pattern-specific parts of "怎麼提出建議"
- Replace with an instruction: when a behavioral variation point is spotted while filling
  in methods, call the `design-pattern-advisor` skill (with a description of the situation)
  to get pattern candidates (Context/Forces/Resulting Context); whether to adopt one still
  follows the general YAGNI rule already in this file — suggest applying only if the user
  confirms a second variation is likely to actually happen
- Keep the "先問誰該負責這個邏輯" (Information Expert) section — that's a distinct earlier
  step, not pattern selection
- Keep the `domain-model.md` output table format — that's `ddd-domain-modeling`'s own
  artifact, not the advisor's concern
- Keep "停止條件"

## Validation plan

No automated tests (this is a markdown knowledge skill). Manual dry runs instead:

1. **Standalone trigger**: ask "這個情境要不要套 Strategy pattern" and confirm
   `design-pattern-advisor` triggers and loads `patterns/strategy.md`.
2. **Integrated trigger**: walk through `ddd-domain-modeling` stage 4 using the course's
   "英雄攻擊方式" scenario (from the Strategy subtitle transcript) and confirm it calls
   `design-pattern-advisor` mid-flow instead of reasoning from a local table.
3. **Content spot-check**: manually verify Context/Forces/Resulting Context accuracy for at
   least 2-3 pattern files — one course-sourced (e.g. Chain of Responsibility), one
   GoF-only (e.g. Builder).

## Open questions / follow-ups (not blocking this design)

- Whether/how `java-clean-arch-codegen` and `go-clean-arch-codegen` eventually consume
  `design-pattern-advisor` is left for a future design.
