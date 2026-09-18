# dsh-anthropic-skills

在 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）中使用
[anthropics/skills](https://github.com/anthropics/skills) 官方技能包（19 个技能）。

本仓库本身**不是** dsh 插件包，只是一个 wrapper：`anthropic-skills/` 是 anthropics/skills 的 git submodule。
真正把它接进 dsh 的是下面的挂载方式之一，都**不需要**写代码、不需要重启 dsh。

## 结论速览

| 挂载方式 | 生效范围 | 本机（Windows）状态 |
|---|---|---|
| 方式一：项目根 `<projectRoot>/.dsh/skills` | 仅该仓库 | ⬜ 未建，需要时按下面命令建 |
| **方式二：用户根 `$DSH_HOME/skills`** | **所有 profile × 所有项目** | ✅ **已落地**（19 个 junction），实测实时生效 |
| 方式三：patch `customSkillDirs` | 仅宿主行未被禁用的 profile（headless / sdk / acp / sdk-minimal） | ❌ 在 `web` / `dsh-tui` 下**无效**（配了也不出现技能） |

下面各节按**编号顺序**（方式一 → 方式二 → 方式三）介绍；日常使用**推荐方式二**——
它是唯一在所有 profile 下都生效的位置，原因见「注册表是分层的」一节，那是本仓库踩完后最值得记的一条。

## 原理

### 三个插件

dsh 的技能发现由 `@deepseek-ai/dsh-base` 里挂载的三个插件完成：

| 插件 | 作用 |
|---|---|
| `@deepseek-ai/dsh-skill` | 技能注册表（分层、合并多个 provider） |
| `@deepseek-ai/dsh-skill-filesystem` | 扫描磁盘上的技能根目录（provider） |
| `@deepseek-ai/dsh-tool-skill` | 把技能目录暴露给模型（`skill` 工具 + 会话目录） |

### 技能根与优先级

`dsh-skill-filesystem` 的默认根（rank 越大优先级越低；用户根会跳过其 `.system` 子目录）：

| Rank | 来源 | 路径 | 作用范围 |
|---|---|---|---|
| 100 | `project-dsh` | `<projectRoot>/.dsh/skills` | 当前仓库（projectRoot = 最近的含 `.git` 的祖先目录） |
| 200 | `project-agents` | `<projectRoot>/.agents/skills` | 当前仓库 |
| 300 | `custom` | `customSkillDirs` 配置项 | 取决于该 provider 行挂在哪一层 |
| 400 | `user-dsh` | `$DSH_HOME/skills`（默认 `~/.dsh/skills`） | 全局 |
| 500 | `user-agents` | `$DSH_AGENTS_HOME/skills`（默认 `~/.agents/skills`） | 全局 |
| 600 | `bundled` | `$DSH_BUNDLED_SKILL_DIR` | 打包内置 |

### 关键约束：发现只下一层

只认 `<root>/<name>/SKILL.md` 或 `<root>/<name>.md` 这两种**直接子项**，不递归
（嵌套的 `**/SKILL.md` 有意不被发现）。

上游布局是 `skills/<name>/SKILL.md`，检出后完整路径为 `anthropic-skills/skills/<name>/SKILL.md`
（仓库根 → submodule `anthropic-skills/` → 上游 `skills/` → 技能名），比 dsh 期望的深一层。只有两条出路：

- 把**扫描根指到** `<repo>/anthropic-skills/skills`（方式三，走 `customSkillDirs`）；或
- **一个技能一个链接**，把它们"压平"到某个默认根（方式一 / 方式二）。

> ⚠️ 把整个 `skills/` 目录只做**一层**链接，结果仍然深一层，会被**静默忽略**（无任何报错）。
> 这是本仓库最容易踩的坑。

### 注册表是分层的：宿主层 vs preset 层

`dsh-skill` 的注册表在宿主组合里，但**按 scope 分层**：

- 部署级 provider（仓库插件、**宿主层**的 `skill-filesystem` 行）注册进 **global layer**；
- 每个 agent preset 在自己的 `agent.cordis.yml` 里挂的 `skill-filesystem` 注册进**该 preset 的 layer**；
- 读取时合并 global layer 与查看者 scope 的链：**同一层内 provider 重名直接抛错**，
  **跨层重名则近层整体覆盖远层**（`dsh-skill` 的 `NamedEntries` / `ScopedLayers`），
  rank 只在同一层内决定优先级。

直接后果：**只要 preset 自己挂了 `skill-filesystem`，宿主那一行对该 agent 就是隐形的**。
本机读 shipped bundle 的 patch 后得到的实际情况：

| profile | 宿主层 `skill-filesystem` | 真正做发现的是 | `$DSH_HOME/skills` 可用？ |
|---|---|---|---|
| `web` | `disabled: true`（被 `@deepseek-ai/dsh-web-app` 禁用） | preset（默认 `standard`）自挂的行，**默认 config** | ✅ |
| `dsh-tui` | `disabled: true`（被 `@deepseek-harness-tui/dsh-tui` 禁用） | preset（roster 同样默认 `standard`）自挂的行，**默认 config** | ✅ |
| `headless` / `sdk` / `acp` / `sdk-minimal` | 启用（`dsh-base` 默认，这些 bundle 没动它） | 宿主行本身 | ✅ |

`web` 与 `dsh-tui` 还同时禁用了 `tool-skill`（目录注入由 preset 自己提供）。
preset 的来源有两处：随 bundle 附带的 presets 目录（`standard` / `ptc` / `minimal` / `cordis`），
以及用户根 `$DSH_HOME/.agent-presets/<name>/`（本机有一个自定义 preset `liangshen`，
它同样以**默认 config** 挂 `skill-filesystem`）。

所以：**默认根（含 rank 400 的用户根）在所有 profile 下都会被扫到**，方式二因此跨 profile 通用；
而方式三改的那一行在 `web` / `dsh-tui` 下根本没被挂载，配置写对了也不会出现技能。

### patch 层与组合顺序

profile 树按下面的顺序合成：

```
空根 → 各 bundle 的 cordis.patch.yml（按 dsh.profile.bundles 顺序）
     → profile 自己的 $DSH_HOME/profiles/<profile>/cordis.patch.yml
     → home 级 $DSH_HOME/cordis.patch.yml        ← 对所有 profile 生效，优先级更高
     → 命令行 --patch 覆盖（按 argv 顺序）
```

每个 patch 条目**替换**目标行的整个 `config`（不是深合并），未写的字段回到 schema 默认值；
`skill-filesystem` 的 `includeDefaultRoots` 默认 `true`，所以只写 `customSkillDirs` 不会丢掉默认根。
profile 的 `patchReload: live` 时，profile 层与 home 层两个 patch 文件都被监听，改完即时生效
（随附的 `web` 模板是 live；其他模板可能只在启动时应用）。

## 方式一：项目级挂载

只在 dsh 的工作目录位于本仓库内时生效（rank 100 压过用户根）。用**相对**链接可以提交进 git，
clone + 初始化 submodule 后即可复现，方便团队共享：

```bash
cd <repo>
git submodule update --init --recursive
mkdir -p .dsh/skills
for d in anthropic-skills/skills/*/; do
  n=$(basename "$d")
  [ -f "$d/SKILL.md" ] && ln -sfn "../../anthropic-skills/skills/$n" ".dsh/skills/$n"
done
```

```powershell
# Windows 等价做法（junction 的目标必须是绝对路径，不能照搬上面的相对软链）
$repo = 'E:\Project\dsh-ext\dsh-anthropic-skills'
$dst  = Join-Path $repo '.dsh\skills'
New-Item -ItemType Directory -Path $dst -Force | Out-Null
Get-ChildItem -Directory "$repo\anthropic-skills\skills" |
  Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } |
  ForEach-Object { New-Item -ItemType Junction -Path (Join-Path $dst $_.Name) -Target $_.FullName | Out-Null }
```

本仓库**默认不**创建 `.dsh/skills`。

## 方式二：用户级挂载（推荐，跨 profile 通用）

挂进用户根 `$DSH_HOME/skills`（rank 400），不改任何配置文件：

```powershell
# Windows：目录 junction，不需要管理员权限、不需要开发者模式
$src = 'E:\Project\dsh-ext\dsh-anthropic-skills\anthropic-skills\skills'
$dst = Join-Path $(if ($env:DSH_HOME) { $env:DSH_HOME } else { "$HOME\.dsh" }) 'skills'
New-Item -ItemType Directory -Path $dst -Force | Out-Null
Get-ChildItem -Directory $src |
  Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } |
  ForEach-Object { New-Item -ItemType Junction -Path (Join-Path $dst $_.Name) -Target $_.FullName | Out-Null }
Get-ChildItem $dst | Select-Object Name, LinkType, Target
```

```bash
# Linux / WSL
R=/mnt/md/liz/src/dsh-ext/dsh-anthropic-skills      # 换成你的检出路径
mkdir -p ~/.dsh/skills
for d in "$R"/anthropic-skills/skills/*/; do
  n=$(basename "$d")
  [ -f "$d/SKILL.md" ] && ln -sfn "$d" ~/.dsh/skills/"$n"
done
ls ~/.dsh/skills
```

本仓库附带幂等脚本，做同样的事：

```powershell
pwsh ./scripts/link-user-skills.ps1                          # 创建 / 同步（已存在的跳过）
pwsh ./scripts/link-user-skills.ps1 -WhatIfOnly              # 只预览，不动文件系统
pwsh ./scripts/link-user-skills.ps1 -Remove                  # 只删本仓库建的链接
pwsh ./scripts/link-user-skills.ps1 -Root D:/shared/skills   # 换目标根
```

submodule 更新后重跑一次即可同步上游新增的技能。

### 为什么 Windows 上 junction 可行（实测，不是碰巧）

- Node 对 junction 报 `Dirent.isSymbolicLink() === true`、`isDirectory() === false`；
  provider 的 `nodeEntryKind` 会对这类条目 `stat` 跟随，跟到目录就按 directory 处理。
- 走 `ctx.fs` 时同理：`dsh-fs-local` 的 `listDirectory` 对每个子项做 `probe()`，而 `probe` 用 `stat`（跟随链接）。
  `dsh-fs-sandbox` 的 containment 只作用于 `write` / `edit` 等变更路径，**读取技能文件不受限**。
- 因此 junction 与 POSIX 软链在这个 provider 面前行为一致。

同一个仓库也可以挂到 `~/.agents/skills`（rank 500），那是给多个 agent 工具共享的目录。

## 方式三：patch `customSkillDirs`（只对宿主行启用的 profile 有效）

用 `dsh-overlay.yml` 覆盖 `skill-filesystem` 的 `customSkillDirs`（rank 300）。

> ⚠️ **在 `web` 和 `dsh-tui` 下不要用这种方式。** 这两个 profile 的 bundle 把宿主层那行设成
> `disabled: true`，patch 改的是一行**没被挂载**的插件，技能不会出现。
> 更坑的是 `--dump-config` 会**骗你**：它打印的是**合成结果**，你会看到同一行上既有
> `disabled: true` 又有你的 `customSkillDirs`，看起来"配好了"。合成成功 ≠ 被挂载。
> 这条 patch 也**够不着 preset 层**——preset 的 `agent.cordis.yml` 是另一套组合。
> 在 web / dsh-tui 下请用方式一 / 方式二。

适用场景：`headless` / `sdk` / `acp` / `sdk-minimal` 等保留宿主行的 profile。

```bash
# 单次启动生效
dsh --profile headless --patch <repo>/dsh-overlay.yml "<job>"
```

永久生效——追加到 profile 自己的 patch 层 `$DSH_HOME/profiles/<profile>/cordis.patch.yml`，
或追加到**对所有 profile 生效**的 home 层 `$DSH_HOME/cordis.patch.yml`：

```yaml
- id: skill-filesystem
  config:
    customSkillDirs:
      - E:/Project/dsh-ext/dsh-anthropic-skills/anthropic-skills/skills
```

（provider 会对该值做 `path.resolve`，所以正斜杠写法在 Windows 上可用。）

三种挂载方式可以叠加，rank 小的先赢（同名技能以更靠前的根为准）；
但**在 web / dsh-tui 下方式三无效**，可用的只有方式一 / 方式二。
若确实想在 web / dsh-tui 下用 patch，只能改 **preset 组合**：把 preset 复制到
`$DSH_HOME/.agent-presets/<name>/` 再挂 `customSkillDirs`——本仓库未验证这条路。

## 本机落地记录（2026-09-18）

- 创建了 19 个目录 junction：`C:\Users\alygu\.dsh\skills\<name>` →
  `E:\Project\dsh-ext\dsh-anthropic-skills\anthropic-skills\skills\<name>`（方式二）。
- 期间先按方式三在 home 层 `C:\Users\alygu\.dsh\cordis.patch.yml` 配了 `customSkillDirs`：
  `--dump-config` 显示合成成功，但那行同时是 `disabled: true`，**一个技能都没出现**。
  该文件已删除，避免留下"看起来配好了"的死配置。
- 验证：junction 建好后，**运行中的 web 会话无需重启**即收到替换后的技能目录，
  academy-guide、canvas-design、docx、pdf、pptx、xlsx、mcp-builder、skill-creator 等 19 个技能
  当场进入可用技能列表。

## 验证与排错

- 预览将要创建的链接：`pwsh ./scripts/link-user-skills.ps1 -WhatIfOnly`。
- 看组合结果：`dsh --profile web --dump-config`（会重写 `$DSH_HOME/profiles/<profile>/cordis.yml`，
  需要写权限）。**只用来确认合成，不要用来确认挂载**——务必同时看该行的 `disabled`。
- 技能目录是热更新的：provider 监听每个已存在的根，并对尚不存在的根做轮询探测；
  新增 / 删除 / 改 frontmatter 会被自动感知，**只改技能正文（body）则每次加载时重读**。都不需要重启。

| 症状 | 原因与处理 |
|---|---|
| 一个技能都不出现 | submodule 未初始化（`anthropic-skills/skills` 为空）→ `git submodule update --init --recursive` |
| 配了 `customSkillDirs` 却无效 | 该 profile（web / dsh-tui）禁用了宿主行 → 改用方式二 |
| 整目录链接没反应 | 深了一层被忽略 → 一个技能一个链接 |
| 同名技能行为不符合预期 | 同层 provider 重名会抛错；跨层由更近的层覆盖；同层内 rank 小者优先 |

## 说明与限制

- 19 个技能全部通过 dsh 的 frontmatter 校验：`name` 为 kebab-case、`description` 必填。
  Anthropic 附加的 `license:` 字段被忽略，不影响加载。
- 技能里的 `scripts/`、`references/` 等资源按相对路径解析到真实技能目录，需要自行准备运行环境
  （如 docx / pdf / pptx / xlsx 依赖 Python 库），dsh 不会自动安装。
- 许可证：仓库内多数技能为 Apache-2.0；`docx` / `pdf` / `pptx` / `xlsx` 为 source-available
  （非开源，见各自 `LICENSE.txt`），使用前请确认符合你的场景。

## 附：pptx 技能在本机（Windows）的落地记录（2026-09-18）

已装好三样，端到端验证通过（生成 → 校验 → 渲染 → 肉眼检查都过）：

| 组件 | 位置 / 内容 | 说明 |
|---|---|---|
| Python venv 3.12.13 | `C:\Users\alygu\.venvs\dsh312` | `python-pptx 1.0.2`、`python-docx 1.2.0`、`markitdown[pptx]`、`defusedxml`、`lxml`、`Pillow` |
| pptxgenjs | 在生成脚本所在目录 `npm i pptxgenjs` | 创建 deck 的唯一依赖 |
| 渲染 | 本机 **PowerPoint 16.0**（COM 可用） | **不需要装 LibreOffice** |

**为什么要单独建 3.12**：本机 `python` / `python3` 指向 miniconda base 的 3.9，而技能自带的
`validate.py` / `thumbnail.py` / `clean.py` / `add_slide.py` 用了 `str | None` 与 `match`（需 ≥ 3.10），
在 3.9 下直接报 `TypeError` / `SyntaxError`。`DSH_PYTHON` 已设为用户级环境变量指向该 venv
（`dsh-plugin-writing-guard` 也读这个变量）。

> ⚠️ `DSH_PYTHON` **不能**写进 `$DSH_HOME/.env`。`DSH_` 是 DSH 的 bootstrap-only 前缀
> （`dsh-app-boot` 的 `BOOTSTRAP_PREFIXES`），启动时读到会直接抛错拒绝启动。
> 只能放进启动环境：用户级环境变量，或在终端里 export 后再启动 dsh。

### 三个 Windows 特有的坑（均已实测）

1. **必须设 `PYTHONUTF8=1`**：`validate.py` 读 `slideMaster1.xml` / `notesMaster1.xml` 时没指定 encoding，
   中文 Windows 默认用 `gbk`，于是报 `'gbk' codec can't decode byte ...`。设了就是 `All validations PASSED!`。
2. **DSH 沙箱下 `tempfile.mkdtemp()` 建的目录不可写**，而 `validate.py` 正是把 pptx 解包进 mkdtemp 目录，
   所以在受限会话里必然 `PermissionError: [WinError 5]`；事后连那个目录都删不掉（要提权才能删）。
   → 结构校验这一步要么在提权会话里跑，要么在普通终端里跑。
3. **npm 默认缓存被沙箱挡住**（`...\scoop\persist\nodejs-lts\cache\_logs` 拒绝访问），
   装 node 依赖要加 `--cache <可写目录>`，否则 `npm i` 直接失败。

### 各步骤的可用性

| 步骤 | 命令 | 受限会话 | 提权 / 普通终端 |
|---|---|---|---|
| 生成 deck | `node gen.cjs`（pptxgenjs） | ✅ | ✅ |
| 内容 QA | `markitdown deck.pptx` | ✅ | ✅ |
| 视觉 QA | PowerPoint COM `$pres.Export($dir,"JPG",1600,900)` | ✅ | ✅ |
| 结构校验 | `python scripts/office/validate.py deck.pptx` | ❌ | ✅ |

`soffice.py` / `thumbnail.py` 依赖 LibreOffice（本机未装）。**视觉 QA 用 PowerPoint COM 导出 JPG 可以完全替代**，
而且字体保真度更高——不再有 LibreOffice 字体替换造成的假溢出（技能文档里那一长串"QA 不可靠字体"警告因此不适用）。

## 附：dsh-plugin-writing-guard 的修复记录（2026-09-18）

该插件的 Word 工具链原本处于**完全不可用**状态，两个既有缺陷（与本机 Python 版本无关）：

**缺陷 1：pnpm 跳过了它的 postinstall。** `package.json` 声明了
`"postinstall": "node scripts/install-extras.mjs"`，但 pnpm 默认不执行未经批准的构建脚本，于是
`$DSH_HOME/skills/writing-guard`（技能）和 `$DSH_HOME/plugins/dsh-plugin-writing-guard/word_guard`
（Python 模块）从来没被安装过。手动补跑：

```powershell
node "C:\Users\alygu\.dsh\profiles\web\node_modules\dsh-plugin-writing-guard\scripts\install-extras.mjs"
```

**缺陷 2：运行时路径指向 `lib/`，文件却在 `src/`。** `lib/index.js` 用
`path.join(PLUGIN_DIR, 'word_guard', 'cli.py')`，而 `PLUGIN_DIR` = 包的 `lib/`；但 `package.json` 的
`files` 把模块放在 `src/word_guard`。所以即使 postinstall 跑了，Word 工具仍然报
`can't open file '...\lib\word_guard\cli.py'`。桥接（已做，幂等）：

```powershell
$pkg = "C:\Users\alygu\.dsh\profiles\web\node_modules\dsh-plugin-writing-guard"
New-Item -ItemType Junction -Path "$pkg\lib\word_guard" -Target "$pkg\src\word_guard"
```

> 插件升级会覆盖 `lib/`，这个 junction 会丢，重跑一次即可。上游最新版仍是 2.0.1，尚未修复。

修复后 `writing_word_scan` 正常返回结构扫描结果；`$DSH_HOME/skills/writing-guard` 的落地也让
`writing-guard` 技能自动进入技能目录（技能总数 19 → 20）。

### 一个关于 `DSH_*` 环境变量的观察

在 DSH 的 pwsh 工具里读 `$env:DSH_PYTHON` 是**空的**，但插件进程确实拿到了它（错误信息显示它调用的就是
`C:\Users\alygu\.venvs\dsh312\Scripts\python.exe`）。也就是说沙箱 shell 看到的环境变量与宿主进程并不同源——
**不要用 shell 里的 `$env:` 去判断宿主是否读到了某个变量**。

