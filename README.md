# autotriage-generic

Generate an AI auto-triage configuration for GitHub.

It has three presets which may make it easier to use, these are:

- conservative (bot just reviews)
- normal (bot reviews everything, automerges small things)
- mayhem (bot merges its own code)

All are adjustable thru script or agent setup.

<details>
<summary><b>What the bot can do</b></summary>

| Ability                                           | Bot able, if configured | Script gate | `.md` guidance | In preset by default               |
|---------------------------------------------------|-------------------------|-------------|----------------|------------------------------------|
| Review PRs: comment, label, escalate              | ✅                      | ❌          | ✅             | $\color{green}\text{conservative}$ |
| Answer "@claude" mentions                         | ✅                      | 🟡          | ✅             | $\color{green}\text{conservative}$ |
| Auto-merge dependency upgrades                    | ✅                      | ✅          | ✅             | $\color{yellow}\text{normal}$      |
| Auto-merge docs and typo fixes                    | ✅                      | ✅          | ✅             | $\color{yellow}\text{normal}$      |
| Auto-merge small code changes with tests          | ✅                      | ✅          | ✅             | $\color{yellow}\text{normal}$      |
| Auto-merge anything that passes CI and review     | ✅                      | ✅          | ✅             | $\color{orange}\text{mayhem}$      |
| `"@claude fix"` on a PR commits to it               | ✅                      | ✅          | ✅             | $\color{yellow}\text{normal}$      |
| `"@claude fix"` on an issue opens a PR              | ✅                      | ✅          | ✅             | $\color{yellow}\text{normal}$      |
| Merge its own fixes                               | ✅                      | ✅          | ✅             | $\color{orange}\text{mayhem}$      |
| Hand risky PRs to a maintainer instead of merging | ✅                      | ❌          | ✅             | $\color{green}\text{conservative}$ |
| Close PRs or issues                               | 🟡  (only thru own PRs) | ✅          | ✅             | $\color{orange}\text{mayhem}$      |
| Fix code on a cron schedule                       | ❌                      | ✅          | ❌             |                                    |
| Run code or tests (outside of CI)                 | ❌                      | ✅          | ❌             |                                    |
| Merge PRs with failing CI                         | ❌                      | ✅          | ✅             |                                    |
| Merge or commit protected files                   | ❌                      | ✅          | ✅             |                                    |
| Commit to fork PRs or the default branch          | ❌                      | ✅          |                |                                    |
| Act on requests from non-maintainers              | ❌                      | 🟡          | ✅             |                                    |
| Approve PRs                                       | ❌                      | ❌          | ✅             |                                    |
| Add or upgrade dependencies in its fixes          | ❌                      | 🟡          | ✅             |                                    |

</details>

## Step 1: Generate files

<details>
<summary><b>Option A. Generate files entirely with an agent</b></summary>

Run `setup.sh` through your agent, from this directory, for your repo e.g.:

```markdown
Read CUSTOMIZE.md and walk me through setting up autotriage for
hackingmaterials/my_repo
```

</details>

<details>
<summary><b>Option B. Generate manually and refine with an agent/manually</b></summary>

#### Step B1:

Run

```sh
./setup.sh --repo hackingmaterials/my_repo --mode normal --maintainer @someone
```

`setup.sh --help` will tell you more. Important parameters are

- `--repo OWNER/REPO` (required): Example, `hackingmaterials/matminer`.
- `--mode`: A preset list of options and scripts that can be set easily, refined
  later. Values are `conservative`, `normal`, and `mayhem`.
- `--maintainer`: Maintainers the bot tags when it escalates. The first is the
  default; repeat the option to list more.

The files go to `output/REPO/.github/`.

##### Step B2: Customize further

Either:

- have your agent guide you through `CUSTOMIZE.md`, using the prompt `setup.sh`
  prints at the end
- edit `output/REPO/.github/autotriage_rules.md` (and `autotriage.conf` for
  settings) yourself

</details>

## Step 2: Put in your repo

Copy the contents of `output/REPO/.github/` into your repo's `.github/` and
merge to `main`. Nothing runs until it's there.

If the API key isn't set yet: `gh secret set ANTHROPIC_API_KEY -R OWNER/REPO`

Run `/install-github-app` in Claude Code, from your repo, so the bot posts as
`claude[bot]`. Skip its own workflows.

## How does it work?

This configurator creates

1. Workflows for GitHub Actions
2. deterministic gates (scripts) which prevent the agent from doing crazy stuff
   (e.g., merging or committing what the mode doesn't allow).
3. agent behavior in an md file.
4. settings, including the mode, in `autotriage.conf`.

The agent takes code-changing action (merges and commits) through the scripts.
The rest of the agent's behavior, such as when it takes action, how, and what it
says, is set in the `md` file. Change the mode and settings later in
`autotriage.conf`.

