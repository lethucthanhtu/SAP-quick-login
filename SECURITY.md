# Security policy

## Supported versions

Only the latest `main` is supported.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Report it privately through
GitHub: _Security_ tab -> _Report a vulnerability_
(<https://github.com/lethucthanhtu/SAP-quick-login/security/advisories/new>).
Include what is affected, how to reproduce it, and the impact. Leave out real hosts, users and
passwords.

In scope, for example: the hosted script differing from this repository, the script sending
your credentials anywhere other than the local `sapshcut.exe`, or values from the JSON file
being run as code.

Out of scope: SAP GUI itself, and attacks that need someone who already controls your account.

## Keeping your credentials safe

- `sap-systems.json` is plain text. Prefer an empty `password` so SAP GUI asks for it, or SSO
  where your system supports it. If you do store passwords, keep the file only in your own
  profile, never in Git, a shared or synced folder, or a chat.
- A stored password is passed to `sapshcut.exe` as `-pw=...`. Process command lines can be read
  by other programs running as your user (and by administrators), for example in Task Manager.
- The script needs no administrator rights; do not run it elevated.

## Running the one-liner safely

`irm <url> | iex` runs whatever the server returns at that moment. Download the script, read
it, compare `Get-FileHash` with the reviewed commit on GitHub and run the local copy, or pin the
URL to a commit:
`https://raw.githubusercontent.com/lethucthanhtu/SAP-quick-login/<commit>/quicky.ps1`.
