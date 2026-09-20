"""在 DSH 沙箱内运行 pptx 技能的 validate.py，而不修改 submodule 中的任何文件。

原理
----
validate.py 的解包目录来自 `tempfile.TemporaryDirectory()`。DSH 的文件沙箱不允许
子进程写入"由子进程新建"的目录，但允许写入"调用方预先创建"的目录。本驱动在
import validate 之前把 `tempfile.TemporaryDirectory` 替换为指向预建目录的替身，
使 validate.py 的全部校验逻辑原样运行；submodule 保持零改动。

用法（一般通过同目录的 validate-sb.ps1 调用）
---------------------------------------------
    python validate_sb.py <deck.pptx> [validate.py 的其余参数...]

环境
----
OFFICE_TMP_DIR       必填。调用方预先创建好的工作目录（本脚本不新建、不清理）。
PPTX_SKILL_SCRIPTS   可选。技能 scripts 目录，默认 ~/.dsh/skills/pptx/scripts。
"""

import os
import sys
import tempfile
from pathlib import Path


class PreCreatedTempDir:
    """``TemporaryDirectory`` 的沙箱友好替身。

    复用调用方预创建的 ``OFFICE_TMP_DIR``；``cleanup`` 刻意为 no-op——目录与
    内容的生命周期归调用方（包装器负责删除）。接口只需覆盖 validate.py 实际
    用到的 ``name`` / ``cleanup`` / 上下文管理器协议。
    """

    def __init__(self, suffix=None, prefix=None, dir=None):
        base = os.environ.get("OFFICE_TMP_DIR", "")
        if not base or not Path(base).is_dir():
            raise RuntimeError(
                "OFFICE_TMP_DIR 必须指向一个已存在的目录"
                "（由调用方预创建；本脚本不新建目录，以兼容 DSH 沙箱）"
            )
        self.name = str(Path(base).resolve())

    def cleanup(self):
        return None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__ or "usage: python validate_sb.py <deck> [validate.py args...]")
        return 2

    deck = Path(sys.argv[1])
    if not deck.exists():
        print(f"deck not found: {deck}")
        return 2

    default_scripts = Path.home() / ".dsh" / "skills" / "pptx" / "scripts"
    skill_scripts = Path(os.environ.get("PPTX_SKILL_SCRIPTS") or default_scripts)
    office_dir = skill_scripts / "office"
    if not (office_dir / "validate.py").is_file():
        print(f"validate.py not found under: {office_dir}")
        return 2

    # 关键：先替换 tempfile.TemporaryDirectory，再 import validate。
    # validate.py 在 main() 内部才调用它，因此这里替换对它生效；
    # 默认不启用（OFFICE_TMP_DIR 未设置时保持原行为），便于随时回退。
    if os.environ.get("OFFICE_TMP_DIR"):
        tempfile.TemporaryDirectory = PreCreatedTempDir

    sys.path.insert(0, str(office_dir))
    sys.argv = ["validate.py", *sys.argv[1:]]

    import validate  # noqa: E402  （技能原文件，零改动）

    try:
        validate.main()
    except SystemExit as exc:  # validate.py 以 sys.exit() 退出
        return int(exc.code or 0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
