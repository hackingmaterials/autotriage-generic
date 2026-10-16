# Where the rules come from

These are the patterns found in PRs, and in issues closed by PRs, across
these repos: hackingmaterials/matminer, robocrystallographer and amset;
materialsproject/atomate2, matbench and pymatgen; and DuraMAT/pvpro. They
also cover two private team repos (an agent harness and a multi-agent
service). Researched October 2026. Numbers are PR or issue numbers in the
named repo.

## Who decides, and on what evidence

- **One domain owner per area settles disputes, and other reviewers defer to them.**
  - pymatgen has a single merger, who routes energy-correction questions to
    their original author (#4538, #4694) and VASP input sets to others.
  - In matminer #948, a reviewer without domain knowledge accepted the change
    because it came with a failing-then-passing test and a domain user
    vouched for it.
  - CODEOWNERS was missing (5 of 8 repos) or stale: pymatgen's paths predate
    its move to `src/`.
- **The evidence that ended arguments:**
  - **A minimal reproducer:** atomate2 #1530; matminer #921.
  - **A test that fails before the fix:** matminer #948.
  - **A paper or DOI:** matminer #967 and #969; pymatgen #4435.
  - **A reference code's default:** atomate2 #1568 matched phonopy; pymatgen
    #4268 used spglib.
  - **A quantified before/after:** matminer #969, where γ moved from 1.189 to
    1.362 and crossed a threshold.
  - **A convergence study:** atomate2 #1586; amset #167.
- **Defaults and breaking changes needed several people to agree,** plus a
  warning or changelog note: atomate2 #1389 and #1576.
  - pymatgen keeps legacy import paths forever, because saved database
    objects refer to them (#4633).
  - matminer proposed a versioned property name rather than changing values
    that trained models depend on (#927).
- **Data provenance:** regenerating a data file once overwrote hand-verified
  values (pymatgen #4370 → #4372). Git history beat generated metadata in a
  private repo.

## What gets merged fast, slow, or not at all

- **Fast:**
  - Bot dependency bumps: pymatgen's median is 1.1 days; amset and atomate2
    auto-merge Dependabot PRs.
  - Maintainer housekeeping.
  - Small fixes with tests: pymatgen PRs under 50 lines have a median of
    0.8 days; matminer #921, #937 and #942 merged in 0–10 days.
- **Slow:** physics or default changes take 60–80 days (amset #931, #938),
  and new workflows take months to years (atomate2 #1063, 663 days).
- **Closed unmerged:**
  - superseded or split into smaller PRs (matminer #904 → #903/#905/#906);
  - redirected after code moved repos (pymatgen #4598, #4504);
  - no tests (pymatgen #3911);
  - an upstream root cause (atomate2 #1221);
  - an unreviewable AI mega-PR (atomate2 #1517, +441k lines);
  - an unsolicited AI bot PR (pymatgen #4381).
- **Failing bot dependency bumps sit open for months** (amset #981, #985;
  robocrys #611), because they need porting work rather than a merge.

## Traps a bot fell into or nearly did

- **Who opened a PR doesn't describe its diff.**
  - A Dependabot PR later got maintainer commits touching workflows and
    source (robocrys #603).
  - Benchmark "submissions" also changed CI (matbench #358, #366).
- **Zero checks doesn't mean green.**
  - First-time fork PRs wait for approval (matminer #967; pymatgen #4694).
  - Workflows may run on `push` only, so fork PRs merged with no CI
    (robocrys #488, #565).
  - PRs opened with `GITHUB_TOKEN` trigger no workflows (matminer #884).
  - Path filters skip docs PRs (pymatgen).
- **Failing CI isn't always the PR's fault.** matbench's default branch is
  permanently red (#367). Network services flake (robocrys #606).
- **GitHub author association misidentifies maintainers.** COLLABORATOR
  includes read-only users, and a frequent matminer merger shows up as
  CONTRIBUTOR.
- **Prompt and skill files are behavior, not docs.** In a private agent
  repo, a wrong default in a skill file changed what jobs ran. An agent once
  launched jobs without consent because of a stale skill copy.
- **Stacked PRs merged into intermediate branches never reached main** (a
  private repo).
- **An action contradicted the latest comment.** pvpro #16 was merged
  minutes after a maintainer wrote they were closing it as unresolvable.
  Master now pins conflicting versions.
- **AI review loops.** Repeated reviews of an unchanged large PR annoyed the
  contributor, and one review admitted reading about 900 lines of a much
  larger diff (pymatgen #4700).
- **Org AI policies exist.** Materials Project forbids contributions from
  autonomous AI agents and requires AI text to be labeled
  (`materialsproject/.github`).

## Settings worth checking per repo

- **No branch protection:** matminer, robocrys and amset. The guard is the
  only gate.
- **Free-plan private repos can't enforce protection at all.**
- **amset auto-merges GitHub Actions version bumps** and publishes with
  `pypa/gh-action-pypi-publish@master`, so workflow changes land with no
  human review.
- **matminer lets Actions approve PRs** (`can_approve_pull_request_reviews: true`).
- **A since-deleted `claude.yml` in pvpro** ran on any `@claude` comment,
  with no permission check and with merge rights.
