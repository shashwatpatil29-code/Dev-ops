# Working on this repo

## Branches

| Branch | What lives there | Who merges into it |
|---|---|---|
| `main` | Released code only. Every commit on `main` is tagged `vX.Y.Z` or is a hotfix. Jenkins deploys from here. | Release PRs from `develop`, hotfix PRs |
| `develop` | Integration branch. Always builds, always passes tests. | Feature PRs |
| `feature/FT-<id>-<short-name>` | One backlog item, e.g. `feature/FT-07-dashboard-search` | – |
| `fix/FT-<id>-<short-name>` | Bug fix found during development | – |
| `hotfix/<short-name>` | Urgent fix cut from `main` | – |
| `release/<version>` | Optional freeze before tagging, e.g. `release/1.1.0` | – |

Names are lower-case, words separated with `-`, and always carry the backlog id so the
PR, the branch and the card on the board can be matched up.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/) style, imperative mood:

```
feat(entry): reject future dates on the fill form
fix(alerts): ignore odometer typos when computing mileage
test(ui): add Selenium journey for overfill alert
ci: run Selenium suite before docker build
docs: add Ansible rollback walkthrough
```

Types used here: `feat`, `fix`, `test`, `docs`, `ci`, `build`, `chore`, `refactor`.

## Pull requests

1. Branch off `develop`, push, open a PR back into `develop` using the PR template.
2. At least one reviewer approves. Address comments with new commits (don't force-push during review).
3. CI must be green (`./mvnw verify`).
4. Merge with **"Create a merge commit"** so the feature stays visible in history. Delete the branch.

## Releasing

```
git checkout main && git merge --no-ff develop -m "release: v1.2.0"
git tag -a v1.2.0 -m "Fuel Tracker 1.2.0"
git push origin main --tags
```
Bump `<version>` in `pom.xml` on `develop` first.
