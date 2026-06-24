#Requires -Version 5.0
<#
.SYNOPSIS
    SAP Quick Logon — launch SAP GUI sessions from a JSON system list without
    manually filling the SAP Logon Pad every time.

.DESCRIPTION
    Reads system definitions from a JSON file, presents an interactive TUI menu,
    and calls sapshcut.exe with the correct -guiparm / -system flags so the
    connection string is built exactly the way SAP expects it.

    Connection string logic (matches sapshcut.exe behaviour):
      • No SAP Router  → -guiparm="/H/<host>/S/<port>"
      • With SAP Router → -guiparm="<router>/H/<host>/S/<port>"

    The -system flag carries the SID (e.g. H23), NOT the connection string.

.NOTES
    Backward-compatible with PowerShell 5.x (Windows PowerShell).
    JSON path: %APPDATA%\SAP\Common\sap-systems.json
#>

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$JsonFile = "$env:APPDATA\SAP\Common\sap-systems.json"

# ---------------------------------------------------------------------------
# Script-scope parallel arrays used by Show-Menu and the main loop.
#
# WHY PARALLEL ARRAYS instead of array-of-hashtables:
#   Constrained Language Mode (common in corporate environments via GPO/AppLocker)
#   blocks [PSCustomObject], New-Object, and generic types like List[T].
#   Returning an array-of-hashtables from a function also causes a double-wrap
#   bug: "return ,$items" makes $menuItems.Count = 1 always, so every choice
#   resolves to the last item. Parallel script-scope arrays sidestep both issues
#   entirely — no return value, no type restrictions.
# ---------------------------------------------------------------------------
$script:MenuSystems = @()   # parallel: SAP system object at index i
$script:MenuClients = @()   # parallel: client string at index i

# ---------------------------------------------------------------------------
# Helper: Resolve a .lnk shortcut to its target executable path
# ---------------------------------------------------------------------------
function Get-PathFromShortcut {
    param([string]$LnkPath)
    try {
        $shell    = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($LnkPath)
        return $shortcut.TargetPath
    } catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# Helper: Locate sapshcut.exe using several discovery strategies
# ---------------------------------------------------------------------------
function Find-SapShcut {

    # Strategy 1 — well-known default install paths (64-bit and 32-bit)
    $candidates = @(
        "${env:ProgramFiles}\SAP\FrontEnd\SAPgui\sapshcut.exe",
        "${env:ProgramFiles(x86)}\SAP\FrontEnd\SAPgui\sapshcut.exe"
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) { return $found }

    # Strategy 2 — resolve via Start Menu shortcuts under "SAP Front End"
    $shortcutFolder = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SAP Front End"
    if (Test-Path $shortcutFolder) {
        $lnkFiles = Get-ChildItem -Path $shortcutFolder -Filter "*.lnk" -ErrorAction SilentlyContinue
        foreach ($lnk in $lnkFiles) {
            $targetPath = Get-PathFromShortcut -LnkPath $lnk.FullName
            if (-not $targetPath) { continue }

            # Shortcut may point directly to sapshcut.exe
            if ($targetPath -match 'sapshcut\.exe$' -and (Test-Path $targetPath)) {
                return $targetPath
            }

            # Or it may point to saplogon.exe; sapshcut.exe lives in the same folder
            $installDir = Split-Path -Path $targetPath -Parent
            $candidate  = Join-Path $installDir "sapshcut.exe"
            if (Test-Path $candidate) { return $candidate }
        }
    }

    # Strategy 3 — registry (SAP GUI installer writes InstallDir here)
    $regPaths = @(
        "HKLM:\SOFTWARE\SAP\SAP Shared\SAPGUI Frontend",
        "HKLM:\SOFTWARE\WOW6432Node\SAP\SAP Shared\SAPGUI Frontend"
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $installDir = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstallDir
            if ($installDir) {
                $candidate = Join-Path $installDir "sapshcut.exe"
                if (Test-Path $candidate) { return $candidate }
            }
        }
    }

    # Strategy 4 — fall back to PATH
    $inPath = Get-Command "sapshcut.exe" -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }

    return $null
}

# ---------------------------------------------------------------------------
# Helper: Build the -guiparm connection string for sapshcut.exe
#
#   Without router : /H/<host>/S/<port>
#   With router    : <router>/H/<host>/S/<port>
#
# The router string already starts with /H/ (e.g. /H/azrap001.eastus2.cloudapp.azure.com),
# so we simply prepend it — no extra separator is needed.
# ---------------------------------------------------------------------------
function Build-GuiParm {
    param($sys)

    # Cannot build a connection string without a host; return $null so the
    # caller can detect the invalid state and skip or warn instead of passing
    # an empty -guiparm argument to sapshcut.exe.
    if (-not $sys.host -or $sys.host.Trim() -eq "") { return $null }

    $hostPart = "/H/$($sys.host)/S/$($sys.port)"

    if ($sys.sapRouter -and $sys.sapRouter.Trim() -ne "") {
        # Concatenate: <router>/H/<host>/S/<port>
        return "$($sys.sapRouter.Trim())$hostPart"
    }

    return $hostPart
}

# ---------------------------------------------------------------------------
# Helper: Check whether a client value is in the system's favoriteClients list
# ---------------------------------------------------------------------------
function Test-IsFavoriteClient {
    param($sys, [string]$clientValue)

    if (-not $sys.favoriteClients) { return $false }
    return $sys.favoriteClients -contains $clientValue
}

# ---------------------------------------------------------------------------
# UI: Render the system/client selection menu.
#     Populates $script:MenuSystems and $script:MenuClients (parallel arrays)
#     instead of returning a collection, avoiding all Constrained Language Mode
#     type restrictions and the array double-wrap return bug.
# ---------------------------------------------------------------------------
function Show-Menu {
    param([string]$FilterText = "")

    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║       SAP Quick Logon        ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Reset parallel arrays on every render so numbering is always consistent
    $script:MenuSystems = @()
    $script:MenuClients = @()
    $i = 1

    foreach ($sys in $systems) {
        # Skip hidden systems
        if ($sys.hidden -eq $true) { continue }

        # Normalise client to array (JSON may have a single string value)
        $clients  = if ($sys.client -is [array]) { $sys.client } else { @($sys.client) }
        $anyShown = $false

        foreach ($c in $clients) {
            $label = "{0} [{1}]" -f $sys.name, $c

            # Apply search filter (case-insensitive substring match)
            if ($FilterText -and ($label -notmatch [regex]::Escape($FilterText))) { continue }

            $isFav  = Test-IsFavoriteClient -sys $sys -clientValue $c
            $marker = if ($isFav) { "★ " } else { "  " }
            $color  = if ($isFav) { "Green" } else { "White" }

            Write-Host ("  {0,2}.  {1}{2}" -f $i, $marker, $label) -ForegroundColor $color

            # Store system and client at the same index in parallel arrays.
            # Array-of-hashtables or PSCustomObject are avoided here because
            # both are blocked in Constrained Language Mode.
            $script:MenuSystems += $sys
            $script:MenuClients += $c

            $i++
            $anyShown = $true
        }

        # Visual separator between system groups
        if ($anyShown) { Write-Host "" }
    }

    if ($script:MenuSystems.Count -eq 0) {
        Write-Host "  (no matching systems)" -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host "  ──────────────────────────────" -ForegroundColor DarkGray
    Write-Host "   0.  Exit          /text = search" -ForegroundColor DarkGray
    Write-Host "  ──────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Startup: locate sapshcut.exe
# ---------------------------------------------------------------------------

$SapShcut = Find-SapShcut

if (-not $SapShcut) {
    Write-Host "  sapshcut.exe could not be found automatically." -ForegroundColor Red
    Write-Host "  Please enter the full path to sapshcut.exe, or press Enter to exit." -ForegroundColor Yellow
    $manualPath = Read-Host "  Path"

    if (-not $manualPath -or -not (Test-Path $manualPath)) {
        Write-Host "  Invalid path. Exiting." -ForegroundColor Red
        exit 1
    }
    $SapShcut = $manualPath
}

# ---------------------------------------------------------------------------
# Startup: load system definitions from JSON
# ---------------------------------------------------------------------------

if (-not (Test-Path $JsonFile)) {
    Write-Host "  JSON file not found: $JsonFile" -ForegroundColor Red
    exit 1
}

$systems = Get-Content $JsonFile -Raw | ConvertFrom-Json

# ---------------------------------------------------------------------------
# Main interaction loop
# ---------------------------------------------------------------------------

$filter = ""

while ($true) {
    # Render menu — populates $script:MenuSystems and $script:MenuClients
    Show-Menu -FilterText $filter

    $prompt    = if ($filter) { "  Logon (filter: '$filter')" } else { "  Logon" }
    $userInput = (Read-Host $prompt).Trim()

    # Exit commands
    if ($userInput -match '^(0|q|exit)$') {
        Clear-Host
        break
    }

    # Filter command: /text sets filter, / alone clears it
    if ($userInput.StartsWith('/')) {
        $filter = $userInput.Substring(1).Trim()
        continue
    }

    # Validate numeric selection against the parallel arrays populated by Show-Menu
    $choiceNum = 0
    if (-not [int]::TryParse($userInput, [ref]$choiceNum) `
        -or $choiceNum -lt 1 `
        -or $choiceNum -gt $script:MenuSystems.Count) {
        Write-Host "  Invalid choice." -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }

    # Retrieve system and client from parallel arrays using the same index
    $sys    = $script:MenuSystems[$choiceNum - 1]
    $client = $script:MenuClients[$choiceNum - 1]

    # Build the guiparm connection string (host/port + optional SAP Router prefix)
    $guiParm = Build-GuiParm -sys $sys

    # # Check guiparm — skip launch if host is not configured in JSON
    # if (-not $guiParm) {
    #     Write-Host "  Skipping $($sys.name): host is not configured." -ForegroundColor Yellow
    #     Start-Sleep -Milliseconds 800
    #     continue
    # }

    # Assemble sapshcut.exe arguments
    # -guiparm  : full RFC connection string (replaces the old -system for direct connections)
    # -system   : SID, used by SAP for session title and system identification
    # -maxgui   : start SAP GUI window maximized
    $argParts = @(
        "-guiparm=`"$guiParm`"",
        "-system=$($sys.system)",
        "-client=$client",
        "-user=`"$($sys.user)`"",
        "-pw=`"$($sys.password)`"",
        "-maxgui"
    )

    # Language is optional — only pass it when defined
    if ($sys.language -and $sys.language.Trim() -ne "") {
        $argParts += "-language=$($sys.language)"
    }

    $argString = $argParts -join " "

    try {
        Start-Process -FilePath $SapShcut -ArgumentList $argString -ErrorAction Stop
        Write-Host ""
        Write-Host ("  Launching {0} [{1}] ..." -f $sys.name, $client) -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host ("  Failed to launch {0}: {1}" -f $sys.name, $_.Exception.Message) -ForegroundColor Red
    }

    Start-Sleep -Milliseconds 800
}