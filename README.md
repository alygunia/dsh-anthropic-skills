# dsh-anthropic-skills

在 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）中使用
[anthropics/skills](https://github.com/anthropics/skills) 官方技能包。

本仓库本身**不是** dsh 插件包，只是一个 wrapper：`anthropic-skills/` 是 anthropics/skills 的 git submodule。
真正把它接进 dsh 的是下面的三种挂载方式之一，都**不需要**写代码、不需要重启 dsh。

## 原理

dsh 的技能发现由 `@deepseek-ai/dsh-base` 里挂载的三个插件完成：

| 插件 | 作用 |
|---|---|
| `@deepseek-ai/dsh-skill` | 技能注册表（rank 合并多个 provider） |
| `@deepseek-ai/dsh-skill-filesystem` | 扫描磁盘上的技能根目录 |
| `@deepseek-ai/dsh-tool-skill` | 把技能目录暴露给模型（`skill` 工具 + 会话目录） |

`dsh-skill-filesystem` 扫描的默认根目录（rank 越大优先级越低）：

| Rank | 来源 | 路径 | 作用范围 |
|---|---|---|---|
| 100 | `project-dsh` | `<projectRoot>/.dsh/skills` | 当前仓库（projectRoot = 最近的含 `.git` 的祖先目录） |
| 200 | `project-agents` | `<projectRoot>/.agents/skills` | 当前仓库 |
| 300 | `custom` | `customSkillDirs` 配置项 | 由 profile 配置决定 |
| 400 | `user-dsh` | `~/.dsh/skills` | 全局（所有 profile / 项目） |
| 500 | `user-agents` | `~/.agents/skills` | 全局 |
| 600 | `bundled` | `$DSH_BUNDLED_SKILL_DIR` | 打包内置 |

**关键约束：发现只下一层深度**，只认 `<root>/<name>/SKILL.md` 或 `<root>/<name>.md`。
anthropics/skills 的实际布局是 `skills/<name>/SKILL.md`，检出到本仓库后完整路径为
`anthropic-skills/skills/<name>/SKILL.md`（仓库根 → submodule `anthropic-skills/` → 上游 `skills/` → 技能名），
比 dsh 期望的深一层，所以**必须把扫描根指向 `<repo>/anthropic-skills/skills`**，或用软链把它"压平"。

## 方式一：项目级软链（可选，默认不预置）

在仓库根创建 `.dsh/skills/<name>` → `../../anthropic-skills/skills/<name>` 的**相对**软链后，只要 dsh 的
工作目录在本仓库内，19 个技能就会出现在技能目录里（rank 100，文件监听热生效，**无需改配置、无需重启**）。
本仓库**默认不**创建这些软链（`.dsh/skills` 不存在），需要时执行：

```bash
cd /mnt/md/liz/src/dsh-ext/dsh-anthropic-skills
git submodule update --init --recursive
mkdir -p .dsh/skills
for d in anthropic-skills/skills/*/; do
  n=$(basename "$d")
  [ -f "$d/SKILL.md" ] && ln -sfn "../../anthropic-skills/skills/$n" ".dsh/skills/$n"
done
```

相对软链（而非绝对路径）可以安全提交进 git：clone + 初始化 submodule 后即可复现，方便团队共享。

## 方式二：用户级软链（全局生效，推荐日常使用）

想在任何项目里都能用，把软链放进用户根目录 `~/.dsh/skills`（rank 400），无需改 profile：

```bash
mkdir -p ~/.dsh/skills
for d in /mnt/md/liz/src/dsh-ext/dsh-anthropic-skills/anthropic-skills/skills/*/; do
  n=$(basename "$d")
  [ -f "$d/SKILL.md" ] && ln -sfn "$d" ~/.dsh/skills/"$n"
done
ls ~/.dsh/skills
```

同一个仓库也可以挂到 `~/.agents/skills`（rank 500），那是给多个 agent 工具共享的目录。

## 方式三：profile 配置 `customSkillDirs`（不改动技能目录）

用 `dsh-overlay.yml` 覆盖 `skill-filesystem` 的 `customSkillDirs`（rank 300）。
因为 provider 的 schema 里 `includeDefaultRoots` 默认 `true`，覆盖 config 不会丢掉默认根目录。

单次启动生效：

```bash
dsh --profile web --patch /mnt/md/liz/src/dsh-ext/dsh-anthropic-skills/dsh-overlay.yml
```

永久生效：把下面这段追加到 `~/.dsh/profiles/web/cordis.patch.yml`（tui 同理改 `~/.dsh/profiles/tui/cordis.patch.yml`）：

```yaml
- id: skill-filesystem
  config:
    customSkillDirs:
      - /mnt/md/liz/src/dsh-ext/dsh-anthropic-skills/anthropic-skills/skills
```

三种方式可以叠加，rank 小的先赢（同名技能以更靠前的根为准）。

## 验证

- 三种方式任一挂载后，19 个技能会出现在会话的 available skills 目录中，模型可直接调用 `skill` 工具加载。
- 想确认 wiring 而不启动服务：`dsh --profile web --patch ./dsh-overlay.yml --dump-config`。
  注意该命令会重写 `$DSH_HOME/profiles/<profile>/cordis.yml`，需要写权限。
- 新增/删除/改 frontmatter 由文件监听自动感知；**只改技能正文（body）由每次加载时重读**，都不需要重启。

## 说明与限制

- 19 个技能全部通过 dsh 的 frontmatter 校验：`name` 为 kebab-case、`description` 必填。
  Anthropic 附加的 `license:` 字段被忽略，不影响加载。
- submodule 未初始化时 `anthropic-skills/skills` 为空，技能目录会静默为空。先跑 `git submodule update --init --recursive`。
- 技能里的 `scripts/`、`references/` 等资源按相对路径解析到真实技能目录，需要自行准备运行环境
  （如 docx/pdf/pptx/xlsx 依赖 Python 库），dsh 不会自动安装。
- 许可证：仓库内多数技能为 Apache-2.0；`docx` / `pdf` / `pptx` / `xlsx` 为 source-available
  （非开源，见各自 `LICENSE.txt`），使用前请确认符合你的场景。
