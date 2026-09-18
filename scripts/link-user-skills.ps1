#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Link every skill in this repo's `anthropic-skills` submodule into the global
  DSH skill root, so every DSH profile and every project discovers them.

.DESCRIPTION
  DSH's filesystem skill provider scans `<DSH_HOME>/skills` (rank 400) among its
  default roots, and discovery is exactly one level deep: it only recognises
  `<root>/<name>/SKILL.md`. The submodule layout is already `skills/<name>/SKILL.md`,
  so one link per skill is what makes it visible — a single link to the whole
  `skills/` directory would sit one level too deep and be ignored.

  On Windows a directory junction is used, which needs no administrator rights
  and no Developer Mode. On other platforms a relative-free symlink is used.

.EXAMPLE
  pwsh ./scripts/link-user-skills.ps1
  pwsh ./scripts/link-user-skills.ps1 -WhatIfOnly
  pwsh ./scripts/link-user-skills.ps1 -Remove
  pwsh ./scripts/link-user-skills.ps1 -Root D:/shared/skills
#>
[CmdletBinding()]
param(
  # Destination skill root. Defaults to $env:DSH_HOME/skills, else ~/.dsh/skills.
  [string]$Root,

  # Remove the links this script owns instead of creating them.
  [switch]$Remove,

  # Report what would change without touching the filesystem.
  [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'anthropic-skills/skills'

if (-not (Test-Path -LiteralPath $source)) {
  throw "Skill source not found: $source`nRun: git submodule update --init --recursive"
}

if (-not $Root) {
  $dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }
  $Root = Join-Path $dshHome 'skills'
}

$sourceFull = (Resolve-Path -LiteralPath $source).Path.TrimEnd('\', '/')

$skills = Get-ChildItem -LiteralPath $sourceFull -Directory |
  Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') }

if ($skills.Count -eq 0) {
  throw "No <name>/SKILL.md found under $sourceFull"
}

if (-not $WhatIfOnly -and -not (Test-Path -LiteralPath $Root)) {
  New-Item -ItemType Directory -Path $Root -Force | Out-Null
}

$created = 0
$removed = 0
$kept = 0

foreach ($skill in $skills) {
  $link = Join-Path $Root $skill.Name
  $existing = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue

  if ($Remove) {
    if (-not $existing) { continue }
    # Only ever remove links this script plausibly owns: reparse points whose
    # target lives inside our submodule. Never a real directory of user skills.
    $target = @($existing.Target)[0]
    if ($existing.LinkType -and $target -and $target.TrimEnd('\', '/').StartsWith($sourceFull, [StringComparison]::OrdinalIgnoreCase)) {
      if ($WhatIfOnly) { "remove  $link"; $removed++; continue }
      [System.IO.Directory]::Delete($link, $false)
      "removed $link"
      $removed++
    } else {
      "skip    $link (not a link into this repo)"
    }
    continue
  }

  if ($existing) {
    "keep    $link"
    $kept++
    continue
  }

  if ($WhatIfOnly) { "create  $link -> $($skill.FullName)"; $created++; continue }

  if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    New-Item -ItemType Junction -Path $link -Target $skill.FullName | Out-Null
  } else {
    New-Item -ItemType SymbolicLink -Path $link -Target $skill.FullName | Out-Null
  }
  "created $link -> $($skill.FullName)"
  $created++
}

""
"root    : $Root"
"source  : $sourceFull"
"skills  : $($skills.Count)"
if ($Remove) { "removed : $removed" } else { "created : $created, kept: $kept" }
""
"DSH picks these up without a restart: the provider watches the root and probes a"
"missing root until it appears, then replaces the session catalog."
