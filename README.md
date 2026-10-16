# autotriage-generic

Generate an AI auto-triage configuration for GitHub.


## Step 1: Generate files

<details>
<summary><b>Option A. Generate files entirely with an agent</b></summary>

Run `setup.sh` through your agent, from this directory:

```markdown
Read CUSTOMIZE.md and walk me through setting up autotriage for OWNER/REPO
```

</details>

<details>
<summary><b>Option B. Generate manually and refine with an agent/manually</b></summary>

#### Step B1:

Run

```sh
./setup.sh --repo OWNER/REPO --mode normal --maintainer @someone
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

## Step 3: Put in your repo

Copy the contents of `output/REPO/.github/` into your repository's `.github/`,
and merge it into your default branch (usually `main`). Nothing runs until it
is there.

Ensure your key `ANTHROPIC_API_KEY` is set as a repository secret. `setup.sh`
checks this and offers to set it. In `normal` and `mayhem` modes, also install
the [Claude GitHub App](https://github.com/apps/claude) on the repo and add a
`PAT` secret. `setup.sh` prints the full checklist, with links.

## How does it work?

This configurator creates

1. Workflows for GitHub Actions
2. deterministic gates (scripts) which prevent the agent from doing crazy stuff
   (e.g., merging or committing what the mode doesn't allow).
3. agent behavior in an md file.
4. settings, including the mode, in `autotriage.conf`.

The agent takes code-changing action (merges and commits) through the scripts.
The rest of the agent's behavior, such as when it takes action, how, and what
it says, is set in the `md` file. Change the mode and settings later in
`autotriage.conf`.
