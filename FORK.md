# Clarc — fork build (dttxorg/Clarc)

This is a **personal fork** of [ttnear/Clarc](https://github.com/ttnear/Clarc).
It exists because the upstream PR that adds the on-request auto-approval
feature ([#16](https://github.com/ttnear/Clarc/pull/16)) was filed upstream
but is not yet merged. This fork keeps that change available as a
downloadable build so you can use it regardless of upstream's release
cadence.

## What's in this fork

The fork branch `feat/auto-approve-in-project-root` contains:

- **Phase 1 on-request approval** — auto-approve `Edit`/`Write`/`MultiEdit`
  tool calls whose target path is lexically inside the registered project
  root. Modal still appears for any path outside the project.
- **Bash safety whitelist expansion** — 16 additional read-only commands
  (`tokei`, `cloc`, `tar`, `unzip`, `zip`, `xxd`, `hexdump`, `od`,
  `strings`, `shasum`, `md5sum`, `sha256sum`, `base64`, `id`, `groups`,
  `rev`, `time`, `cal`).
- **`PathContainment.isInside(parent:child:)`** in `ClarcCore` (lexical,
  no filesystem access, no symlink resolution).
- 12 new unit tests in `Packages/Tests/ClarcCoreTests/PathContainmentTests.swift`.

No changes to UI, hook matcher, `PermissionMode` enum, or `appcast.xml`.

## How to install a fork build

1. Go to the [Releases page](https://github.com/dttxorg/Clarc/releases).
2. Download the latest `Clarc-x.y.z-fork.n.zip`.
3. Unzip and move `Clarc.app` to `/Applications` (overwrite the upstream
   install if you have one — the bundle ID `com.idealapp.Clarc` is the same).
4. On first launch, **right-click `Clarc.app` → Open** and confirm the
   Gatekeeper prompt. The build is **ad-hoc signed** (not notarized with
   an Apple Developer ID), so this manual approval is required.
5. After the first launch, normal double-click works.

## How to update a fork build

The Sparkle auto-updater inside Clarc points at the upstream
`ttnear/Clarc` appcast, so it will **not** see fork builds as updates.
Pick one of:

- **Disable auto-update in the app** (Clarc → Check for Updates, never
  enable it for fork builds). Re-download from this fork's Releases page
  when a new fork build ships.
- **Replace the installed `.app` manually** by repeating the install
  steps above. Your `~/Library/Application Support/Clarc/` data is kept
  across replacements.

## How the fork is built

This fork ships a fork-only GitHub Actions workflow
(`.github/workflows/fork-build.yml`) that:

- Runs on `macos-14` runners with Xcode 15.4.
- Builds `Clarc.app` in `Release` configuration with ad-hoc signing
  (`CODE_SIGN_IDENTITY=-`).
- Packages the `.app` into a zip with the same flags the upstream
  `scripts/build_zip.sh` uses (notably `--norsrc --noextattr --noqtn`
  to avoid AppleDouble entries that break embedded frameworks).
- On tag push (`v*` matching), creates a draft GitHub Release and
  uploads the zip as an artifact.

It does **not** run Apple notarization, because the fork does not have
a Developer ID certificate. That is why the install requires the
right-click → Open dance.

## Triggering a fork build manually

```bash
git tag v1.3.2-fork.1
git push origin v1.3.2-fork.1
```

GitHub Actions will build, then attach `Clarc-1.3.2-fork.1.zip` to a
draft release. Promote the draft to public when you're happy with it.

## Re-syncing with upstream

```bash
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
git checkout feat/auto-approve-in-project-root
git rebase main
# resolve any conflicts, then:
git push --force-with-lease origin feat/auto-approve-in-project-root
```

## License

Apache License 2.0, same as upstream. See [LICENSE](LICENSE).
