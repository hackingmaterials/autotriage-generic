# Autotriage preferences for {{REPO}}

Made by `setup.sh` in autotriage-generic at commit {{VERSION}}.

Keep this file in the repository's `.github/`, with the other autotriage
files. When autotriage-generic changes, it makes new files from these
preferences instead of asking again. In autotriage-generic, either:

- ask your agent: "Read CUSTOMIZE.md and update the autotriage files for
  {{REPO}} from its MY_PREFERENCES.md", or
- run `./setup.sh --preferences path/to/MY_PREFERENCES.md`. This reuses
  the setup options, but not the customizations: make those again from
  the list below.

## Setup options

`setup.sh --preferences` reads this block. Each line is a `setup.sh`
option without its `--`, then `=` and a value. `maintainer` repeats,
escalation contact first. Edit a line to change what the next run uses.

```text
{{OPTIONS}}
```

## Files

What this setup made, in the repository's `.github/`. Copying newer files
over these doesn't remove the ones an update no longer makes, so
`setup.sh --preferences` lists those for you to delete.

{{FILES}}

## Customizations

Answers and changes beyond the setup options: what an agent following
`CUSTOMIZE.md` did to these files. An update makes them again. `setup.sh`
only carries this section over.

Nothing recorded yet.
