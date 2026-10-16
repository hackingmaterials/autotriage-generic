# autotriage-generic

Generate an AI auto-triage configuration for github.

### Step 1. Generate files

Run `setup.sh` (either with your agent or as a script):

`setup.sh --help` will tell you more. Important parameters are

- `--repo OWNER/REPO` (required): Example, `hackingmaterials/matminer`.
- `--mode`: A preset list of options and scripts that can be set easily, refined
  later. Values are `conservative`, `normal`, and `mayhem`.
- `--maintainer`: Maintainers which will be tagged in issues.

### Step 2: Customize further

Either:

- have your agent guide you through `CUSTOMIZE.md`
- edit `output/REPO/.github/autotriage_rules.md` yourself

### Step 3: Put in your repo

Copy the resulting `.github` (in `output/REPO/.github/`) to your repository.

Ensure your key `ANTHROPIC_API_KEY` is set.

## How does it work?

This configurator creates

1. A workflow for github
2. deterministic gates (scripts) which prevents the agent from doing crazy stuff
   (e.g., automerging) if desired.
3. agent behavior in an md file.

The agent takes code-changing action through the scripts. The rest of the agents
behavior, such as when it takes action, how, and what is says, is set in the 
`md` file. 

