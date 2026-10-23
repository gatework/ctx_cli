# Changelog

## Unreleased

## 0.2.1 (2026-10-23)

- Use English command help, prompts and collection/review diagnostics.
- Allow compatible dotenv versions without an upper version bound.

## 0.2.0 (2026-10-23)

- Rename Initialization to Initializer and Application to Router; remove the old constants and require paths in the 0.2.0 candidate.
- Preserve caller argument strings during routing and publish configuration applicability only after every layer succeeds.
- Remove quadratic field-source scans for leaf configuration values.
- Bound offline review source counts and cumulative bytes, and treat batch directory names literally.
- Redact adapter argument and dependency errors at the collection boundary.
- Share offline review preflight/publication ordering and redacted diagnostics without depending on Runner or domain schemas.
- Bound input bytes and configuration nesting/nodes before deserialization; merge owned layers without recursive copies.
- Synchronize newly created parent directories before publishing configuration templates.

## 0.1.0 (2026-10-22)

- Extract reusable configuration discovery, private initialization, command dispatch, option groups, terminal interaction, input/output and collection entrypoint orchestration.
- Integrate existing VXLAN, Wireless and net-connector backup/topology entrypoints; keep baseline integration limited to the existing coverage script.
- Preserve Ruby 3.4 compatibility and verify standalone package installation without application or device dependencies.
