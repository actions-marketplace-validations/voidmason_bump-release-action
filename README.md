# bump-release-action

Bump the version of a cargo workspace, commit, tag, push, and optionally
create a GitHub release. The manual release entry point for projects that
version from CI: one dispatch input picks the semver action, the rest is
automated.

## What it does

Runs on the current branch of the calling workflow:

1. bumps the version with `cargo set-version --workspace` according to the
   requested action;
2. commits every touched manifest and `Cargo.lock` as
   `Bump version to vX.Y.Z` (plus an optional note);
3. tags `vX.Y.Z` and pushes the branch with the tag;
4. creates a GitHub release with generated notes. By default only final
   versions are released - a pre-release is just tagged, and the `finalize`
   release covers the whole beta series; `prerelease: true` opts in to
   publishing beta tags as GitHub pre-releases.

Supported actions:

| Action                     | Example                                                 |
|----------------------------|---------------------------------------------------------|
| `patch`, `minor`, `major`  | `0.1.5 -> 0.1.6 / 0.2.0 / 1.0.0`                        |
| `beta`                     | `0.1.5 -> 0.1.6-beta.1`, `0.1.6-beta.1 -> 0.1.6-beta.2` |
| `beta-minor`, `beta-major` | `0.1.5 -> 0.2.0-beta.1 / 1.0.0-beta.1`                  |
| `finalize`                 | `0.1.6-beta.2 -> 0.1.6`                                 |

`finalize` on a version with no active pre-release fails loud instead of
releasing nothing.

## Usage

```yaml
name: Bump version and release

on:
  workflow_dispatch:
    inputs:
      version:
        description: "Release action"
        type: choice
        options: [patch, minor, major, beta, beta-minor, beta-major, finalize]
        default: patch
      commit_note:
        description: "Optional text appended to commit message"
        type: string
        default: ""

permissions:
  contents: write

jobs:
  bump:
    runs-on: ubuntu-latest
    steps:
      - uses: nerjs/bump-release-action@v1
        with:
          token: ${{ secrets.RELEASE_TOKEN }}
          version: ${{ inputs.version }}
          commit_note: ${{ inputs.commit_note }}
```

## Inputs

| Input         | Required | Description                                                |
|---------------|----------|------------------------------------------------------------|
| `token`       | yes      | PAT, see below.                                            |
| `version`     | yes      | One of the actions above.                                  |
| `commit_note` | no       | Text appended to the bump commit message. Default empty.   |
| `release`     | no       | Create a release for a final version tag. Default `true`.  |
| `prerelease`  | no       | Publish beta tags as pre-releases too. Default `false`.    |
| `name`        | no       | Committer name. Default `nerjs`.                           |
| `email`       | no       | Committer email. Default `nerjs@users.noreply.github.com`. |

## Outputs

| Output    | Description                                  |
|-----------|----------------------------------------------|
| `version` | The version after the bump (`1.2.3-beta.1`). |
| `tag`     | The pushed tag (`v1.2.3-beta.1`).            |

## Token

A PAT is required, not the default `GITHUB_TOKEN`: the bump commit is pushed
to the release branch, which is usually protected, and `GITHUB_TOKEN`
(github-actions[bot]) cannot bypass branch rules. A tag pushed with
`GITHUB_TOKEN` also does not trigger downstream workflows (tag-driven
publishing, for example). Contents: read+write is enough; the same token
creates the release, so the release is authored by the PAT owner.

## Requirements

- The runner needs `cargo`, `jq`, `gh` and `git`; `ubuntu-latest` ships all
  of them. `cargo-edit` is installed by the action itself.
- The workspace must have a root package: the current version is read via
  `cargo read-manifest`, which does not work in a virtual workspace
  (workspace without a root `[package]`).

## License

MIT, see [LICENSE](LICENSE).
