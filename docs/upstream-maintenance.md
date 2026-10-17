# Upstream maintenance

The **Upstream updates** GitHub Actions workflow runs every Monday at 17:23 UTC
and can be run manually from Actions. Changes to the automation on `main` also
run it, so its PR creation path is exercised when maintained.

Only published stable releases are considered:

- YSwift uses the latest published, non-prerelease GitHub release. Git applies
  the release delta with three-way merge, retaining the fork's CI workflows.
  `.github/upstream-yswift.json` tracks the imported release across squash merges.
  One draft PR on `codex/yswift-upstream` is opened or updated and assigned to the
  fork owner. Unreleased `main` commits are ignored.
- Yrs uses the latest stable, non-yanked version in the official Cargo registry
  index. The updater downloads that published crate and verifies its registry
  checksum before rebasing the local patch. Updates use one reusable
  `codex/yrs-upstream` PR, assigned to the fork owner.
- Git's three-way merge preserves the local undo-manager fix. Conflicts, failed
  imports, and failed builds produce a draft PR and a failed workflow run.
- Validation builds all five Apple target slices, runs native regression tests,
  and builds/tests Swift. It runs directly in this workflow because PRs created
  with `GITHUB_TOKEN` do not trigger ordinary PR workflows. YSwift PRs call CI
  with their merge ref; a conflicting merge fails visibly.
- Yrs import/build jobs have read-only permissions. A fresh runner applies only
  the prepared vendor/package diff and opens the PR without executing it.
  The YSwift PR job manipulates source as data and never runs imported code;
  its separate native/Swift validation job has read-only permissions.
- CI rejects native YSwift changes that retain a previously published binary URL.
- The workflow never merges or publishes releases. A Yrs update clears the old
  binary URL so it cannot accidentally ship a stale framework. After resolving
  and merging an update, use the release script to publish a matching binary.

The workflow uses GitHub-maintained `actions/checkout` and `actions/github-script`
with the repository's built-in `GITHUB_TOKEN`. No deploy key or personal token is
needed. Bot branches are force-updated so each open PR reflects the current base
and latest published release. The fork's workflow files are never imported.
Actions must be enabled, with **Allow GitHub Actions to create and approve pull
requests** enabled in Settings → Actions → General. The workflow creates PRs;
it never approves them. GitHub's workflow-enable API keeps the weekly schedule
active without dummy commits.

To check published releases locally and import a reported update:

```sh
python3 scripts/test-update-yrs.py
python3 scripts/update-yrs.py --discover
# Only when discovery reports an update:
python3 scripts/update-yrs.py --update
YSWIFT_LOCAL=1 ./scripts/build-xcframework.sh
cargo test --manifest-path lib/Cargo.toml --locked
YSWIFT_LOCAL=1 swift test
```

Review `.github/upstream-yrs.json` and `lib/vendor/yrs-undo-drop.patch` alongside
the upstream diff. The merge tests cover independent edits, an upstreamed fix,
conflicts, and removal of a locally patched file.

When resolving conflicts, compare the resolved vendor tree with the pristine
published crate version in `upstream-yrs.json`. Regenerate `yrs-undo-drop.patch`
with `a/` and `b/` paths relative to the crate root, then clear the `conflicts`
array. Run `python3 scripts/update-yrs.py --check` before the native/Swift checks;
CI rejects stale conflict metadata or a patch that cannot be reverse-applied.
