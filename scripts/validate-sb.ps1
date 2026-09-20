<#
.SYNOPSIS
  在 DSH 沙箱内运行 pptx 技能的 validate.py（零 submodule 改动）。

.DESCRIPTION
  DSH 沙箱不允许子进程写入"由子进程新建"的目录，而 validate.py 会把 pptx 解包进
  tempfile.mkdtemp() 新建的目录，因此在受限会话里必然失败。本包装器：
    1. 用 shell 预创建一个工作目录（沙箱允许写入"调用方预建"的目录）；
    2. 通过 OFFICE_TMP_DIR 把它交给 scripts/validate_sb.py；
    3. 由该驱动以猴子补丁方式把 TemporaryDirectory 指向预建目录，
       validate.py 原文件零改动。

  同时设置 PYTHONUTF8=1，规避 validate.py 在中文 Windows 上的 gbk 编码问题。

.EXAMPLE
  ./validate-sb.ps1 deck.pptx
  ./validate-sb.ps1 deck.pptx --original template.pptx -v
  ./validate-sb.ps1 deck.pptx -Python C:\Users\me\.venv\x\Scripts\python.exe
#>
param(
    [Parameter(Mandatory, Position = 0)][string]$Deck,
    # Python 解释器；默认依次取 DSH_PYTHON、PATH 上的 python
    [string]$Python,
    # 技能 scripts 目录（junction 路径即可）
    [string]$SkillScripts = (Join-Path $env:DSH_HOME 'skills\pptx\scripts'),
    # 透传给 validate.py 的其余参数（--original / -v / --auto-repair / --author ...）
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'

if (-not $Python) {
    $Python = if ($env:DSH_PYTHON) { $env:DSH_PYTHON } else { 'python' }
}
if (-not (Test-Path -LiteralPath $Deck)) { throw "文件不存在: $Deck" }
if (-not (Test-Path -LiteralPath $SkillScripts)) { throw "找不到技能脚本目录: $SkillScripts" }

# 关键：工作目录由本 shell 预创建（沙箱允许写入"调用方预建"的目录）
$work = Join-Path ([IO.Path]::GetTempPath()) (
    'office-validate-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
)
New-Item -ItemType Directory -Path $work -Force | Out-Null

$env:OFFICE_TMP_DIR     = $work
$env:PYTHONUTF8         = '1'
$env:PPTX_SKILL_SCRIPTS = $SkillScripts

try {
    & $Python (Join-Path $PSScriptRoot 'validate_sb.py') $Deck @Rest
    exit $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
