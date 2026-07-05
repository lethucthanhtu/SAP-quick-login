# SAP Quick Logon

A PowerShell script for quickly logging into multiple SAP systems (SAP GUI) through a selection menu, without manually opening SAP Logon Pad.
> Mainly use for system that not enable (or support) SSO

## Requirements

- Windows with SAP GUI installed (the script auto-detects `sapshcut.exe`).
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
| `user`, `password` | ✔        | Used for automatic login                                           |
| `host`             | ✔        | Application Server                                                 |
| `port`             | ✘        | SAP connection details                                             |
| `language`         | ✘        | Leave as `""` or omit the field if not needed                      |
| `sapRouter`        | ✘        | Leave as `""` if no router is used                                 |
| `favoriteClient`   | ✘        | Array of client numbers to highlight in the menu, defaults to `[]` |
| `hidden`           | ✘        | Boolean, hide system from list, default to `false`                 |

⚠️ **Security note**: passwords in this file are currently stored in plain text. Do not commit `sap-systems.json` to Git, and do not share this file over an unsecured channel.

## Using the menu

- Type the corresponding number to log into that system/client.
- Type `/<keyword>` to filter systems by name (e.g. `/ID1`).
- Type `/` alone to clear the filter.
- Type `0`, `q`, or `exit` to quit.
- Clients marked with ⭐ (green) are in the `favoriteClient` list.
