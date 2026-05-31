[CmdletBinding()]
param(
  [switch]$CheckRemote
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$dataPath = Join-Path $root "js/site-data.js"
$exportScriptPath = Join-Path $root "scripts/export-chrome-bookmarks.ps1"
$expectedPages = @("home", "common", "develop", "tools")
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$siteData = $null

function Add-Problem {
  param(
    [System.Collections.Generic.List[string]]$Target,
    [string]$Message
  )

  $Target.Add($Message) | Out-Null
}

function Test-RemoteLink {
  param([string]$Url)

  try {
    Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 5 -TimeoutSec 10 -UseBasicParsing | Out-Null
    return
  } catch {
    try {
      Invoke-WebRequest -Uri $Url -Method Get -MaximumRedirection 5 -TimeoutSec 10 -UseBasicParsing | Out-Null
      return
    } catch {
      Add-Problem $warnings "Remote link check failed: $Url ($($_.Exception.Message))"
    }
  }
}

if (-not (Test-Path -LiteralPath $dataPath)) {
  Add-Problem $errors "Missing data file: $dataPath"
} else {
  $rawData = Get-Content -Raw -Encoding UTF8 -LiteralPath $dataPath

  if ($rawData -notmatch '(?s)^\s*window\.SITE_DATA\s*=\s*(?<json>.*);\s*$') {
    Add-Problem $errors "Could not extract SITE_DATA JSON from js/site-data.js."
  } else {
    try {
      $siteData = $Matches["json"] | ConvertFrom-Json
    } catch {
      Add-Problem $errors "js/site-data.js does not contain valid JSON: $($_.Exception.Message)"
    }
  }
}

if (-not (Test-Path -LiteralPath $exportScriptPath)) {
  Add-Problem $errors "Missing Chrome bookmark export script: $exportScriptPath"
} else {
  $parseErrors = $null
  [System.Management.Automation.PSParser]::Tokenize(
    (Get-Content -Raw -Encoding UTF8 -LiteralPath $exportScriptPath),
    [ref]$parseErrors
  ) | Out-Null

  if ($parseErrors -and $parseErrors.Count -gt 0) {
    foreach ($parseError in $parseErrors) {
      Add-Problem $errors "Bookmark export script parse error at line $($parseError.Token.StartLine): $($parseError.Message)"
    }
  }
}

if ($siteData) {
  foreach ($pageId in $expectedPages) {
    $page = $siteData.PSObject.Properties[$pageId].Value

    if (-not $page) {
      Add-Problem $errors "Missing page data: $pageId"
      continue
    }

    if (-not $page.sections -or $page.sections.Count -eq 0) {
      Add-Problem $errors "Page has no section data: $pageId"
      continue
    }

    foreach ($section in $page.sections) {
      foreach ($item in $section.items) {
        $label = "$pageId/$($item.name)"

        if (-not $item.name) {
          Add-Problem $errors "$label is missing name."
        }

        try {
          $uri = [Uri]$item.url
          if (-not $uri.IsAbsoluteUri) {
            Add-Problem $errors "$label URL is not absolute: $($item.url)"
          }
          if ($uri.Scheme -eq "http") {
            Add-Problem $warnings "$label still uses http: $($item.url)"
          }
        } catch {
          Add-Problem $errors "$label URL is invalid: $($item.url)"
        }

        if (-not $item.icon) {
          Add-Problem $errors "$label is missing icon."
        } else {
          $iconPath = Join-Path $root $item.icon
          if (-not (Test-Path -LiteralPath $iconPath)) {
            Add-Problem $errors "$label icon does not exist: $($item.icon)"
          }
        }

        if ($CheckRemote -and $item.url) {
          Test-RemoteLink $item.url
        }
      }
    }
  }
}

if ($warnings.Count -gt 0) {
  Write-Host "WARNINGS"
  $warnings | ForEach-Object { Write-Host " - $_" }
}

if ($errors.Count -gt 0) {
  Write-Host "ERRORS"
  $errors | ForEach-Object { Write-Host " - $_" }
  exit 1
}

Write-Host "OK: project structure, data, URLs, and local icon references passed."
