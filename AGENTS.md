# Agent instructions

## Verify GitHub Actions changes

When changing GitHub Actions workflows, composite actions, or scripts used by workflows, use **both `actionlint` and `act`** before declaring verification complete.

- Run `actionlint` on the affected workflows and fix its findings. If a valid runner label is newer than the linter's label list, use only a narrowly scoped exclusion and report it.
- Use `act` to check the relevant events and jobs. Execute supported jobs locally; use a dry run only as an additional planning check.
- Blink's `xcode-27` jobs require macOS and Xcode. On a Mac with Xcode, `-P xcode-27=-self-hosted` runs them natively; use an isolated workspace for reviewed workflow code because host mode runs without container isolation. Linux containers do not validate those builds. If execution is unsupported, report the limitation, run the corresponding tests/build natively where possible, and leave GitHub-hosted execution unverified. Do not substitute a Linux runner and claim the macOS job passed.
- Do not rely on `act -n` to prevent side effects: native-host shell steps can execute even with that flag. Keep publishing or other external mutations out of the selected workflow/job unless the user authorized them; a dry run is not an authorization or isolation boundary.
- A dry run or a skipped/unsupported job is not a successful job execution. If a tool or prerequisite is unavailable, state the limitation explicitly rather than silently omitting the check.
- Report the commands run, their outcomes, and any exclusions or skipped steps. Keep secrets out of logs, and do not publish releases as part of verification unless the user requested publication.

For the pull-request workflow on a Mac with Xcode, use:

```sh
actionlint .github/workflows/*.yml
act pull_request -W .github/workflows/ci.yml -j test-and-build -P xcode-27=-self-hosted
```

The second command executes the CI job on the host. The `pull_request` event and `-j test-and-build` select neither the Development publish job nor the release workflow; never run `act push` against `ci.yml` with a real token. Use the native commands in [docs/development.md](docs/development.md) when checking individual steps.
