# Security policy

## Reporting a vulnerability

Please report security issues privately through GitHub's **Report a vulnerability** button on this repository's Security tab, not in a public issue.

## Scope

In scope:

- Anything that lets a file operation escape its root through `native/` (symlinks, `..`, races, hard links)
- A way to make `build.sh` accept a file that is not Anthropic's signed release
- The launcher or installer doing something unsafe with paths or permissions

Out of scope: bugs in the Claude app itself. Report those to Anthropic through their [responsible disclosure policy](https://www.anthropic.com/responsible-disclosure-policy).

## Supported versions

Only the latest commit on `main` is supported.
