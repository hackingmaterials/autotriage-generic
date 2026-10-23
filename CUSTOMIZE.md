# Customizing autotriage for a repository

Instructions for an agent, working in the autotriage-generic directory.
You are given a repository, `OWNER/REPO`, and possibly a mode. `setup.sh`
does the mechanical part: it writes the files for the mode, with working
defaults, to `output/REPO/.github/`. You do the part that needs judgment:
filling in what's specific to this repo, in those output files. The person
copies the folder into their repo afterwards.

**First, check for existing output.** Look for `output/REPO/.github/`, where
REPO is the part of `OWNER/REPO` after the slash.
- **If it exists,** those are the files to customize. Don't run `setup.sh`
  again unless step 2 says to.
  1. Read the mode and settings in `output/REPO/.github/autotriage.conf`,
     and the `cron` line in `output/REPO/.github/workflows/autotriage.yml`.
  2. Show the table from step 1, and say which mode and settings the files
     use.
  3. Ask the fine-tune question from step 1. If no, go on to step 5.
  4. Ask the auto-adjust question from step 1.
  5. Ask the style question from the end of step 1.
  6. Make any changes the person asks for by editing those files (step 4).
  7. Go on to step 3.
- **If it doesn't exist,** start at step 1.

Ground rules:
- Only write under `output/`. Gather facts about the target repo read-only:
  don't push, open PRs, comment, create labels or secrets, or change its
  settings unless the person asks.
- The steps `setup.sh` lists under "To install" and "Anthropic API key" are
  the person's to do: setting secrets, installing the Claude GitHub App, and
  changing repo settings. Show them the steps and links; don't run them.
  Never ask the person to paste an API key or token into the chat.
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
> | "@claude fix" on an issue opens a PR | no | yes, a draft | yes, ready |
> | "@claude fix" on a PR commits to it | no | yes | yes |
> | Merge its own fixes | no | no | yes |
> | Always escalate security and cost risks, protected files, domain risk areas | yes | yes | yes |
>
> **You can adjust any of this later.** Switch modes by editing the `mode`
> line in `.github/autotriage.conf`. Change single behaviors with the other
> lines in that file, e.g. how many PRs each sweep handles, whether
> maintainers can tag "@claude", which kinds of PR merge, turning off
> "@claude fix", or protecting more files. Change how often the bot sweeps
> with the `cron` line in `.github/workflows/autotriage.yml`. Conservative
> mode always wins: it stops every merge and commit.

If the person named a mode, say which column applies and carry on.
Otherwise ask which mode they want. Always offer all three, conservative,
normal, and mayhem, and mark one as recommended. If you ask with a
multiple-choice tool, give exactly those three options. Recommend one this
way:
- **Recommend conservative** if any of these hold:
  - merging deploys or publishes with no further human step;
  - it is a running service, or touches production data or credentials;
  - many projects or a public database depend on its outputs;
  - CI doesn't run tests on PRs, or the default branch's CI is red;
  - no human has merged anything in 12 months.
- **Otherwise recommend normal.**
- **Mayhem** is always available. Offer it like the others.

Then ask this, word for word (with the chosen mode), as yes or no, with yes
as the default:

> Do you want to answer a few questions to fine-tune the setup? If not, I'll
> use MODE mode's defaults and only ask who maintains the repo.

- **If yes,** follow every step below, in order.
- **If no,** use the mode's defaults:
  - Skip questions 0-5a, the two settings, and the auto-adjust question.
    Treat auto-adjust as no.
  - Ask only the maintainers question at the end of this step, unless the
    person already named maintainers.
  - In step 2, leave out `--cron`, `--max-prs`, and `--mentions`, so
    `setup.sh` uses its defaults. Don't write answers into
    `autotriage.conf`.
  - Skip the style question and step 3, and go on to step 5.

Then ask these questions **one at a time**, in order. Each is yes or no;
offer the chosen mode's answer as the default. Skip 0a if 0 is no, and 5a
if 5 is no. The comment-only questions (0, 0a) come before the ones that
merge or change code (1-5a).

| # | Question | conservative / normal / mayhem |
|---|---|---|
| 0 | Should Claude review PRs: comment, label, and escalate to maintainers? | yes / yes / yes |
| 0a | Should maintainers be able to tag "@claude" on issues and PRs for answers, investigations, and reviews? Claude only replies with a comment. This is separate from "@claude fix" (questions 4 and 5), which changes code. | yes / yes / yes |
| 1 | Should Claude auto-merge dependency upgrades? | no / yes / yes |
| 2 | Should Claude auto-merge trivial doc updates and typo fixes? | no / yes / yes |
| 3 | Should Claude auto-merge PRs that pass CI and follow the code guidance (tests included, nothing risky, no protected files like `.github/`)? | no / yes / yes |
| 4 | Should Claude commit fixes to PRs failing CI or the code guidance, when a maintainer asks ("@claude fix" on the PR)? | no / yes / yes |
| 5 | Should Claude open PRs fixing issues, when a maintainer asks ("@claude fix" on the issue)? | no / yes / yes |
| 5a | Should Claude merge its own issue-fix PRs once CI passes? | no / no / yes |

Merging a PR after Claude commits to it (4) follows the answer to 3.
If the mode is conservative and any of 1-5 is yes, switch to normal and
say why: conservative never merges or commits.

Pass the answer to 0a to `setup.sh` as `--mentions on` or `--mentions off`.

Then ask about two settings, offering the defaults. If 0 is no, skip
them: the bot then never sweeps and ignores mentions (`--cron never
--mentions off`); only "@claude fix" works.

| Setting | Choices | Default | `setup.sh` option |
|---|---|---|---|
| How often the bot sweeps open PRs | Weekdays, daily, weekly, every 6 hours, or never (only when tagged) | Weekdays at 9am Pacific | `--cron weekdays\|daily\|weekly\|6h\|never` |
| How many PRs each sweep may act on | Any whole number | 5; 10 for repos with dozens of open PRs; 3 if dormant | `--max-prs N` |

Then ask this, word for word, as yes or no, with no as the default:

> Auto-adjust setup based on agent reading the target repo? The agent
> would read the repo's code, docs, workflows, merged PRs, and closed
> issues, and tune the setup to them: who maintains what, risk areas,
> protected files, and contribution rules. (@ardunn strong recommendation:
> no)

- **If no,** don't read the target repo to change the setup. Skip
  "Gather facts" and the fill-ins in step 3, and leave every default in
  `autotriage_rules.md` and `autotriage.conf` as `setup.sh` wrote it. Use
  only maintainer handles the person gives; if they give none, leave out
  `--maintainer` so `setup.sh` uses its default. Still ask the style
  question.
- **If yes,** follow every step below.

Then always ask who the bot escalates to, and who else maintains the repo,
unless the person already named maintainers. First show this, word for word, so the person knows the list doesn't
decide who can use the bot:

> The handles you give are who the bot escalates to and @-mentions. They
> don't decide who can trigger it: anyone with write or admin access to
> the repo can tag "@claude" or ask for "@claude fix". GitHub checks this
> each time someone comments.
>
> | Repo role | Can trigger the bot? |
> |---|---|
> | Admin, including org owners | yes |
> | Maintain (reported as `write`) | yes |
> | Write | yes |
> | Triage (reported as `read`) | no |
> | Read, outside contributors, the public | no |
> | Bots | no |
>
> Access through a team counts the same as direct access.

Offer a default and accept "keep the default":
- **If no to auto-adjust:** the person running this
  (`gh api user --jq .login`), which is what `setup.sh` uses without
  `--maintainer`.
- **If yes:** the person who merged the most of others' PRs in the last 12
  months, with the next few as other maintainers (see `--maintainer` in
  step 2). Show the counts you based this on.

Pass each handle they confirm as `--maintainer` in step 2, the escalation
contact first.

### The final question: style

Unless the person skipped the questions, always end with this one, even
when the files already exist or the person seems in a hurry:

> Last question: is there any style, or any particular change, you want in
> how the bot writes its comments or its code? Here are the defaults;
> "keep the defaults" is fine.

Show both tables. Show the code table only if "@claude fix" is on for
issues or PRs; otherwise the bot never writes code.

| Comments | Default |
|---|---|
| Tone | Concise and friendly |
| Length | A one-sentence bottom line; everything else in collapsed Core issues, Fixes, and Questions sections |
| Contributors | Assume many are first-time contributors |
| Language and spelling | English, matching the repo's docs |
| Formulas and code | Formulas in LaTeX; code in fenced blocks |
| Emoji | None |
| Sign-off | One line saying it is an automated review a person should check, plus any wording the AI policy requires |
| Terms to use or avoid | The repo's own names for its parts, e.g. what it calls its plug-ins |
| Anything maintainers dislike in bot comments | Nothing listed |

| Code ("@claude fix") | Default |
|---|---|
| Size | The smallest change that fixes the issue; on a PR, only what was asked |
| Tests | A regression test for each issue fix, in the repo's test layout |
| Dependencies | Never added or upgraded |
| Formatting, naming, docstrings, type hints, comments | Nothing listed |
| Anything maintainers dislike in bot code | Nothing listed |

Step 3 says where the answers go.

Stop instead if the repo is archived, a fork, or a template, or its or its
organization's AI policy forbids AI bots.

## 2. Run setup.sh

In this directory:

```sh
./setup.sh --repo OWNER/REPO --mode MODE --maintainer @DEFAULT \
  --cron WHEN --max-prs N --mentions on|off
```

Add these as needed:
- **`--maintainer @HANDLE`, repeated.** The handles the person confirmed
  in step 1. The first is who the bot escalates to; with auto-adjust, the
  default is the person who merged the most of others' PRs in the last 12
  months. The rest are other maintainers. Only list people with write
  access (`gh api repos/OWNER/REPO/collaborators/HANDLE/permission`). If
  the person answered no to auto-adjust, use only the handles they give.
- **`--pip-tools`** only if the repo keeps pip-tools lock files in
  `requirements/`.
- **`--allow-no-ci`** if the repo has no CI at all and the person still
  wants the bot to merge, on its own review. It has no effect once the repo
  has any CI.

Only run `setup.sh` when there is no output yet, or to switch between
conservative and normal or mayhem. That switch changes which files exist;
normal to mayhem and back is just the `mode` line.
A rerun moves the old folder to `output/REPO/.github.previous/`. Copy any
sections you or the person filled in back from there.

Then write the answers to questions 1-5a into
`output/REPO/.github/autotriage.conf`, so the file says exactly what was
chosen. If the person skipped the questions, leave the file as `setup.sh`
wrote it.

| Answer | Line |
|---|---|
| 1, 2, 3 | `merge = deps`, `merge = docs`, `merge = tested`: one line per yes. In mayhem, also `merge = reviewed`. If all are no, `merge = none`. |
| 4 | `autofix_prs = on` or `off` |
| 5 | `autofix_issues = on` or `off` |
| 5a | `merge_own_fixes = yes` or `no` |

`setup.sh` prints the setup checklist; put it in your report.

## 3. Fill in the repo-specific sections

If the person skipped the questions, skip this step and go on to step 5.
If they answered no to auto-adjust, skip to "Write the style answers".

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

### Write the style answers

Write the answers to the style question from step 1:
- **Comments:** each answer that differs from a default is one bullet
  under "Style for this repo", in "Writing comments" in
  `output/REPO/.github/autotriage_rules.md`. Both bots follow that
  section. The bottom line up front is fixed: style can change what goes
  in it, not remove it.
- **Code:** each answer that differs from a default is one bullet under
  "Code style for this repo", in "Make the change" in
  `output/REPO/.github/autofix_rules.md`. The "Never" list there still
  wins.

Where they kept every default, leave "None listed yet."

## 4. Refine, if the person asks

Each refinement is a line in `.github/autotriage.conf`, except the
schedule. The ones about merging and committing don't apply in conservative
mode, which never merges or commits.

| The person wants | Set |
|---|---|
| The bot to sweep more or less often | The `cron` line in `.github/workflows/autotriage.yml` |
| More or fewer PRs handled per sweep | `max_prs_per_run` |
| Maintainers unable to tag "@claude" | `mentions = off` |
| Different kinds of PR merged | `merge = docs`, `deps`, `tested`, `reviewed`, or `none`. Repeat for several; the list replaces the mode's. |
| No "@claude fix" on PRs, or on issues | `autofix_prs = off`, `autofix_issues = off`. With both off, delete the autofix files. |
| The bot to merge its own issue-fix PRs, or not | `merge_own_fixes = yes` or `no` |
| The bot kept away from more files | More `protected` patterns |
| Bot changes kept to some directories | `autofix_paths` patterns |
| Some branches never merged by the bot | `block_branch` patterns |
| Different size limits | `max_changed_lines`, `autofix_max_files`, `autofix_max_changed_lines` |

Before the files are copied into the repo, they are under
`output/REPO/.github/`; edit them there.

To change the mode itself, between normal and mayhem, edit the `mode` line.
To or from conservative, rerun `setup.sh` (step 2), so the files match the
mode. Switching to conservative by editing the
`mode` line alone also works at once: both gate scripts then refuse
everything.

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
3. What you filled in, with one line of evidence each, and the style they
   chose.
4. The setup checklist `setup.sh` printed, and its "Anthropic API key"
   note. If the key isn't set, give them the link it printed. Don't offer
   to set the key yourself; they paste it in their own terminal.
5. Questions for you: anything you couldn't settle.
