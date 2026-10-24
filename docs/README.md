# Blink documentation

These guides describe the current source. [Verification](verification.md) explains how changes are verified and which acceptance checks remain open.

| Document | Use it for |
| --- | --- |
| [Project README](../README.md) | Build, installation, daily use, shortcuts, and privacy |
| [Contributing](../CONTRIBUTING.md) | Development setup, checks, contribution scope, and pull requests |
| [Security policy](../SECURITY.md) | Private vulnerability reporting and supported versions |
| [Requirements](requirements.md) | Product behavior, defaults, scope, and numbered acceptance criteria |
| [Architecture](architecture.md) | Current module boundaries, data flow, persistence, and source map |
| [Decisions](decisions.md) | Settled choices and the reasons to preserve them |
| [Interface behavior](interface.md) | Overlays, pointer targets, blink timing, and accessibility |
| [Development](development.md) | Build and test commands, isolated state, and observation tools |
| [Release downloads](releases.md) | Development and numbered releases, ad-hoc-signed ZIP packages, checksums, and first-launch verification |
| [Verification](verification.md) | Verification methods, preview limitations, and open acceptance checks |

Keep behavior in Requirements, structure in Architecture, rationale in Decisions, procedures in Development and Releases, and verification methods and open checks in Verification. Update the relevant page when behavior changes and link to it instead of repeating it.

`qa-output/`, `build/`, and `.build/` are generated local directories excluded by `.gitignore`. Keep session transcripts, dated run inventories and superseded proposals out of these guides.
