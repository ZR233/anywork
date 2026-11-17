"""将同一份 canonical 协议打包到 wheel 和可独立重建的源码发行包。"""

from pathlib import Path

from hatchling.builders.hooks.plugin.interface import BuildHookInterface


class CustomBuildHook(BuildHookInterface):
    def initialize(self, version, build_data):
        root = Path(self.root)
        packaged = root / "_anywork_run_export_schema/v3"
        canonical = root / "../../code/pl-studio-runtime/schemas/run-export/v3"
        source = packaged if packaged.is_dir() else canonical
        if not source.is_dir():
            raise FileNotFoundError("缺少原生版本 3 canonical schema")
        build_data["force_include"][str(source.resolve())] = "_anywork_run_export_schema/v3"
