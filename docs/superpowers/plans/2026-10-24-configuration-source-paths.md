# Configuration Source Paths Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every merged configuration field an unambiguous source identity.

**Architecture:** Configuration emits JSON Pointer keys in sources.fields. Existing hosts forward the source map unchanged; their tests and documentation migrate together. No new abstraction or alternate format.

**Tech Stack:** Ruby, YAML, RSpec/Minitest, Bundler.

**Spec:** `docs/superpowers/specs/2026-10-24-configuration-source-paths.md`

## Global Constraints

- Ruby >= 3.4; no dependency or version-policy change.
- lib method comments Chinese; business literals English.
- Preserve WIP, no commit/push/release.
- Preserve merge semantics, source-relative paths and domain ownership.
- JSON Pointer applies to sources.fields only; no dot-path aliases.

## Review Focus

- Literal dots/slashes cannot collide with nesting.
- Tilde escape order preserves literal ~1 and ~0.
- Empty keys and Unicode keys retain exact identity without normalization.
- Replacing a parent removes only its actual descendant sources.
- Arrays and empty mappings keep their existing merge/source semantics.

### Task 1: Replace ambiguous source keys and migrate consumers

**Files:**
- Modify ctx_cli: `lib/ctx_cli/configuration.rb`, `spec/configuration_spec.rb`, `README.md`, `docs/migration.md`, `CHANGELOG.md`.
- Create ctx_cli: this plan and its spec.
- Modify VXLAN: `spec/cli/configuration_sources_spec.rb`.
- Modify Wireless: `spec/cli/options_spec.rb`.
- Modify net-connector: `test/config_test.rb`, `test/cli_setup_test.rb`.

**Interfaces:**
- Consumes: validated string-keyed YAML mappings and previous merged mapping.
- Produces: `Configuration#sources["fields"]` mapping from JSON Pointer to file path, deeply frozen; examples `/parallel`, `/ssh/port`, `/a.b`, `/a~1b`, `/m~0n`, `/`.

- [x] **Step 1:** Add real layered-YAML regressions for colliding literal and nested keys, parent replacement, escaped tokens, empty/Unicode keys, arrays and nil/false. Migrate existing source expectations to pointer keys.
- [x] **Step 2:** Run `bundle exec rspec spec/configuration_spec.rb`; expect RED from dot-path collisions or missing pointer keys.
- [x] **Step 3:** Change `record_fields` prefix construction to escaped slash tokens and descendant removal to slash-separated prefixes. Keep all merge and ownership logic. Update consumer source-key assertions and docs; no compatibility branch.
- [x] **Step 4:** Run ctx_cli default rake, consumer targeted tests and complete gates in isolated worktrees. Run the existing three-size benchmark before/after; verify same configuration/source counts. Expect green gates and no return to quadratic leaf scans.
- [x] **Step 5:** One independent final review. Guard-copy only listed files into actual checkouts, validate ordinary consumer gates using exact installed CLI candidate, and run plain/Bundler installed source/preview probes. Compare all package metadata/source bytes. Keep uncommitted work and evidence; mark all steps only with passing receipts.
