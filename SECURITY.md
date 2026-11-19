# security

report problems privately through github's **report a vulnerability** button on this repo (security tab), not in a public issue.

in scope:

- anything that lets a file operation escape its root through `native/` (symlinks, `..`, races, hard links)
- a way to get `build.sh` to accept a file that isn't anthropic's signed release
- the launcher or installer doing something unsafe with paths or permissions

out of scope: bugs in the claude app itself. report those to anthropic at https://www.anthropic.com/responsible-disclosure-policy

only the latest commit on `main` is supported.
