# SAP Quick Logon

A PowerShell script for quickly logging into multiple SAP systems (SAP GUI) through a selection menu, without manually opening SAP Logon Pad.
> Mainly use for system that not enable (or support) SSO

## Requirements

- Windows with SAP GUI installed (the script auto-detects `sapshcut.exe`).
- Windows PowerShell 5.1 or PowerShell 7+.
- A configuration file `sap-systems.json` located at:
  ```
  %APPDATA%\SAP\Common\sap-systems.json
  ```
  (e.g. `C:\Users\<your-username>\AppData\Roaming\SAP\Common\sap-systems.json`)

  If this file does not exist, the script will report an error and will not create it automatically — you need to copy/create this file beforehand.

## How to run (no download needed)

Open **PowerShell** (Win + X → Windows PowerShell, or search "PowerShell" in the Start Menu), paste the following command, and press Enter:

```powershell
irm https://cdn.lttt.dev/sap/quicky.ps1 | iex
```

`irm | iex` runs whatever the server returns at that moment. To review it first, download it,
read it, then run the local copy:

```powershell
irm https://cdn.lttt.dev/sap/quicky.ps1 -OutFile quicky.ps1
notepad .\quicky.ps1
Get-FileHash .\quicky.ps1 -Algorithm SHA256   # compare with the reviewed commit on GitHub
powershell -ExecutionPolicy Bypass -File .\quicky.ps1
```

Or pin to a reviewed commit:
`irm https://raw.githubusercontent.com/lethucthanhtu/SAP-quick-login/<commit>/quicky.ps1 | iex`.
See [SECURITY.md](./SECURITY.md).

## Configuration file `sap-systems.json` — format

```json
[
  {
    "client": ["100", "110", "120"],
    "name": "display_name",
    "system": "system_id",
    "user": "your_user",
    "password": "your_password",
    "host": "application_server",
    "port": "system_port",
    "language": "EN",
    "sapRouter": "sap_router",
    "favoriteClient": ["100", "120"],
    "hidden": false
  },
  ...
]
```

| Field              | Required | Notes                                                              |
|--------------------|----------|--------------------------------------------------------------------|
| `client`           | ✔        | Array of client numbers, or a single string                        |
| `name`             | ✔        | Display name shown in the menu                                     |
| `user`             | ✔        | SAP user name                                                      |
| `password`         | ✘        | Leave as `""` or omit it and SAP GUI will ask for it (recommended)  |
| `host`             | ✔        | Application Server                                                 |
| `port`             | ✘        | SAP connection details                                             |
| `language`         | ✘        | Leave as `""` or omit the field if not needed                      |
| `sapRouter`        | ✘        | Leave as `""` if no router is used                                 |
| `favoriteClient`   | ✘        | Array of client numbers to highlight in the menu, defaults to `[]` |
| `hidden`           | ✘        | Boolean, hide system from list, default to `false`                 |

⚠️ **Security note**: a `password` in this file is stored in plain text, and it is passed to
`sapshcut.exe` as `-pw=...` on the command line, where other programs running as your user can
read it. Prefer leaving `password` empty (SAP GUI then asks for it) or using SSO where your
system supports it. Never commit `sap-systems.json` to Git or share it.

## Uninstall

Nothing is installed. Delete `%APPDATA%\SAP\Common\sap-systems.json` (it may contain passwords)
and any downloaded copy of `quicky.ps1`.

## Using the menu

- Type the corresponding number to log into that system/client.
- Type `/<keyword>` to filter systems by name (e.g. `/ID1`).
- Type `/` alone to clear the filter.
- Type `0`, `q`, or `exit` to quit.
- Clients marked with ⭐ (green) are in the `favoriteClient` list.
