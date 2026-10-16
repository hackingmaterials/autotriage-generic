# Customizing autotriage for a repository

Instructions for an agent, working in the autotriage-generic directory.
You are given a repository, `OWNER/REPO`, and possibly a mode. `setup.sh`
does the mechanical part: it writes the files for the mode, with working
defaults, to `output/REPO/.github/`. You do the part that needs judgment:
filling in what's specific to this repo, in those output files. The person
copies the folder into their repo afterwards. If they already ran
`setup.sh` and only want the rules tailored, skip to step 3.

Ground rules:
- Only write under `output/`. Gather facts about the target repo read-only:
  don't push, open PRs, comment, create labels or secrets, or change its
  settings unless the person asks.
- Base every filled-in value on evidence (files, settings, PR and issue
  history), and record it in the report. Never guess a maintainer handle.
- When unsure, choose the more restrictive option and list it under
  "Questions for you" in the report.

## 1. Pick the mode and settings

Always show the person this table and the note under it, word for word,
before anything else. Do this even if they already named a mode.

> | | conservative | normal | mayhem |
> |---|---|---|---|
> | Review PRs: comment, label, escalate | yes | yes | yes |
> | Merge docs, dependency upgrades, small changes with tests | no | yes | yes |
> | Merge anything that passes CI and review | no | no | yes |
> | `@claude fix` on an issue opens a PR | no | yes, a draft | yes, ready |
> | `@claude fix` on a PR commits to it | no | yes | yes |
> | Merge its own fixes | no | no | yes |
> | Always escalate security and cost risks, protected files, domain risk areas | yes | yes | yes |
>
> **You can adjust any of this later.** Switch modes by editing the `mode`
> line in `.github/autotriage.conf`. Change single behaviors with the other
> lines in that file, e.g. how many PRs each sweep handles, whether
> maintainers can tag `@claude`, which kinds of PR merge, turning off
> `@claude fix`, or protecting more files. Change how often the bot sweeps
> with the `cron` line in `.github/workflows/autotriage.yml`. Conservative
> mode always wins: it stops every merge and commit.

If the person named a mode, say which column applies and carry on.
Otherwise ask which mode they want, recommending one:
- **Recommend conservative** if any of these hold:
  - merging deploys or publishes with no further human step;
  - it is a running service, or touches production data or credentials;
  - many projects or a public database depend on its outputs;
  - CI doesn't run tests on PRs, or the default branch's CI is red;
  - no human has merged anything in 12 months.
- **Otherwise recommend normal.**
- **Recommend mayhem** only when the person asks for it. If any
  conservative condition holds, warn them and ask them to confirm.

Then ask about three settings, offering the defaults:

| Setting | Choices | Default | `setup.sh` option |
|---|---|---|---|
| How often the bot sweeps open PRs | Weekdays, daily, weekly, every 6 hours, or never (only when tagged) | Weekdays at 9am Pacific | `--cron weekdays\|daily\|weekly\|6h\|never` |
| How many PRs each sweep may act on | Any whole number | 5; 10 for repos with dozens of open PRs; 3 if dormant | `--max-prs N` |
| Can maintainers tag `@claude` on issues and PRs for answers, investigations, and reviews? | on or off | on | `--mentions on\|off` |

Stop instead if the repo is archived, a fork, or a template, or its or its
organization's AI policy forbids AI bots.

## 2. Run setup.sh

In this directory:

```sh
./setup.sh --repo OWNER/REPO --mode MODE --maintainer @DEFAULT \
  --cron WHEN --max-prs N --mentions on|off
```

Add these as needed:
- **`--maintainer @HANDLE`, repeated.** The first is who the bot escalates
  to: the person who merged the most of others' PRs in the last 12 months.
  The rest are other maintainers. Only list people with write access
  (`gh api repos/OWNER/REPO/collaborators/HANDLE/permission`).
- **`--test-command CMD` and `--install-command CMD`** (normal and mayhem),
  copied from the repo's CI. If the tests can't run on a plain GitHub
  runner (they need cluster access, licensed codes, or secrets), use
  `--no-autofix` instead.
- **`--pip-tools`** only if the repo keeps pip-tools lock files in
  `requirements/`.

`setup.sh` replaces `output/REPO/.github/` on every run, and prints the
setup checklist; put it in your report.

## 3. Fill in the repo-specific sections

Gather facts. A 403 or 404 means no access or no such setting, so note which.

```sh
R=OWNER/REPO
gh repo view $R --json description,visibility,defaultBranchRef,primaryLanguage,pushedAt,squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed
gh api "repos/$R/collaborators?per_page=100" --jq '.[] | [.login, .role_name] | @tsv'
gh pr list -R $R --state merged --limit 200 --json number,title,author,mergedBy,mergedAt,closingIssuesReferences
gh api repos/OWNER/.github/contents --jq '.[].path'   # org-wide policies
```

Read README, CONTRIBUTING, the PR template, CODEOWNERS, any `AGENTS.md` or
`CLAUDE.md`, and every workflow. Then read about 10 merged PRs with review
discussion and 5 issues closed by a PR (`gh pr view N -R $R --comments`).
For each, note who made the decision and what evidence settled it.

In `output/REPO/.github/autotriage_rules.md`, replace each "not assessed
yet" or "none listed yet":

| Section | How to fill it |
|---|---|
| Activity | Last human merge within 3 months: active; within 12: low; else dormant. Add what that means, e.g. "escalations may go unanswered; make summaries self-contained". |
| Related repositories | Upstream and downstream repos, and any code that moved to another repo. |
| AI policy | A link from the repo or `OWNER/.github`, or "none". |
| Additional escalation | The lead or PI whose word settles disputes; ask if unclear. |
| Area owners | Who resolves each area's questions in PR and issue history. |
| Domain risk areas | 3-10 real paths, each with a few words. Look for constants, units, defaults and tolerances; data files; parsers for external formats; base classes; serialization; and what past breaking PRs touched. |
| Contribution requirements | Musts from CONTRIBUTING, the PR template, and repeated reviewer requests. |
| Known dependents | The packages, databases, or services to check for impact. |

Leave a default in place if you find nothing better. Also:
- For a private or team-only repo, delete the fork CI-approval case in rule
  3 and the "first-time contributors" line.
- For a repo that isn't scientific, delete the LaTeX line.

In `output/REPO/.github/autotriage.conf`:
- **Dependency PRs:** set `deps_branch` and `deps_paths` for the repo's
  dependency bot.

  | Bot | Setting |
  |---|---|
  | pip-tools (`--pip-tools`) | Keep the defaults. Match the Python versions in `upgrade-dependencies.yml` to CI. |
  | Dependabot | `deps_branch = dependabot/*`, plus the lock files it edits. |
  | Renovate | `deps_branch = renovate/*`, plus the lock files it edits. |
  | None | Delete both lines. |
- **Paths:** match `docs_paths` and `test_paths` to the repo's layout.
- **Protected files:** add patterns for what the repo has. Packaging files
  for other ecosystems (`package.json`, `Cargo.toml`, `go.mod`).
  Infrastructure for services (`migrations/*`, `*.tf`, `docker-compose*`,
  `deploy/*`). Prompt and skill directories. Data directories.
- **Merge method:** set `merge_method` to one the repo allows.

## 4. Refine, if the person asks

Each refinement is a line in `.github/autotriage.conf`, except the
schedule. The ones about merging and committing don't apply in conservative
mode, which never merges or commits.

| The person wants | Set |
|---|---|
| The bot to sweep more or less often | The `cron` line in `.github/workflows/autotriage.yml` |
| More or fewer PRs handled per sweep | `max_prs_per_run` |
| Maintainers unable to tag `@claude` | `mentions = off` |
| Different kinds of PR merged | `merge = docs`, `deps`, `tested`, `reviewed`, or `none`. Repeat for several; the list replaces the mode's. |
| No `@claude fix` | `autofix = off`, and delete the autofix files |
| The bot kept away from more files | More `protected` patterns |
| Bot changes kept to some directories | `autofix_paths` patterns |
| Some branches never merged by the bot | `block_branch` patterns |
| Different size limits | `max_changed_lines`, `autofix_max_files`, `autofix_max_changed_lines` |

To change the mode itself, rerun `setup.sh` with the new mode, so the files
and workflow permissions match it, then copy again and delete files the new
mode no longer lists. Switching to conservative by editing the `mode` line
alone also works at once: both gate scripts then refuse everything.

## 5. Check and report

Check:
- Every maintainer handle has write access, and every risk-area path exists.
- The config still loads:
  `bash -c 'cd output/REPO && source .github/autotriage_lib.sh && load_conf .github/autotriage.conf && echo "$mode"'`.
- The workflows in `output/REPO/.github/workflows/` pass `actionlint`, if it
  is installed.

Report to the person:
1. This, word for word, first:
   > **Nothing runs until these files are on your repository's default
   > branch (usually `main`).** Copy the contents of `output/REPO/.github/`
   > into the repo's `.github/` folder, commit, and merge to the default
   > branch. GitHub only runs scheduled and comment-triggered workflows from
   > there.
2. The mode and settings, why, and any warning you gave. Repeat that they
   can adjust any of it later in `.github/autotriage.conf`, and the schedule
   in `.github/workflows/autotriage.yml`.
3. What you filled in, with one line of evidence each.
4. The setup checklist `setup.sh` printed, and its "Anthropic API key"
   note. If the key isn't set, give them the link it printed. Don't offer
   to set the key yourself; they paste it in their own terminal.
5. Questions for you: anything you couldn't settle.
