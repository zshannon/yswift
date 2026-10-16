# Upstream maintenance

The **Upstream updates** GitHub Actions workflow runs every Monday at 17:23 UTC
and can be run manually from Actions. Changes to the automation on `main` also
run it, so its PR creation path is exercised when maintained. It checks both `y-crdt/yswift:main` and
`y-crdt/y-crdt:main`, including unreleased Yrs commits.

- YSwift changes open one cross-fork merge PR and assign the fork owner.
- Yrs changes update the vendored crate, Cargo lockfile, provenance, and generated
  bindings in one reusable `codex/yrs-upstream` PR, assigned to the fork owner.
- Git's three-way merge preserves the local undo-manager fix. Conflicts, failed
  imports, and failed builds produce a draft PR and a failed workflow run.
- Validation builds all five Apple target slices, runs native regression tests,
  and builds/tests Swift. It runs directly in this workflow because PRs created
  with `GITHUB_TOKEN` do not trigger ordinary PR workflows. YSwift PRs call CI
  with their merge ref; a conflicting merge fails visibly.
- Upstream import/build jobs have read-only permissions. A fresh runner applies
  only the prepared vendor/package diff and opens the PR without executing it.
- CI rejects native YSwift changes that retain a previously published binary URL.
- The workflow never merges or publishes releases. A Yrs update clears the old
  binary URL so it cannot accidentally ship a stale framework. After resolving
  and merging an update, use the release script to publish a matching binary.

The workflow uses the repository's `GITHUB_TOKEN`; no personal token is needed.
Actions must be enabled, with **Allow GitHub Actions to create and approve pull
requests** enabled in Settings → Actions → General. The workflow creates PRs;
it never approves them. A pinned keepalive action prevents GitHub's scheduled
workflow inactivity shutdown without creating dummy commits.

For a local import, clone `y-crdt/y-crdt` and run:

```sh
python3 scripts/test-update-yrs.py
python3 scripts/update-yrs.py --source /path/to/y-crdt
YSWIFT_LOCAL=1 ./scripts/build-xcframework.sh
cargo test --manifest-path lib/Cargo.toml --locked
YSWIFT_LOCAL=1 swift test
```

Review `.github/upstream-yrs.json` and `lib/vendor/yrs-undo-drop.patch` alongside
the upstream diff. The merge tests cover independent edits, an upstreamed fix,
conflicts, and removal of a locally patched file.

When resolving conflicts, compare the resolved vendor tree with the pristine
crate at the revision in `upstream-yrs.json`. Regenerate `yrs-undo-drop.patch`
with `a/` and `b/` paths relative to the crate root, then clear the `conflicts`
array. Run `python3 scripts/update-yrs.py --check` before the native/Swift checks;
CI rejects stale conflict metadata or a patch that cannot be reverse-applied.
