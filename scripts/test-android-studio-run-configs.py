#!/usr/bin/env python3
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET


ROOT = pathlib.Path(__file__).resolve().parents[1]
RUN_CONFIG_DIR = ROOT / ".idea" / "runConfigurations"

REQUIRED_CONFIGS = {
    "Android Studio Doctor",
    "Prepare Android Studio",
    "Build Android Receiver",
    "Run Android Receiver",
    "Stage Android Receiver APK",
    "Launch Installed Android Receiver",
    "Uninstall Android Receiver",
    "Replace Android Receiver Dry Run",
    "Audit Receiver Signature",
    "Verify Device Runtime",
    "Verify Installed Device Runtime",
    "Verify Real Device Runtime",
    "Verify Installed Real Device Runtime",
    "Diagnose ADB USB",
}


def gradle_task_exists(task_name: str) -> bool:
    result = subprocess.run(
        ["./gradlew", "help", "--task", task_name, "--console=plain"],
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return result.returncode == 0 and "Task '" not in result.stdout


def run_configs() -> dict[str, list[str]]:
    configs: dict[str, list[str]] = {}
    for path in sorted(RUN_CONFIG_DIR.glob("*.xml")):
        tree = ET.parse(path)
        config = tree.find(".//configuration")
        if config is None:
            raise AssertionError(f"{path} has no configuration element")
        if config.attrib.get("type") != "GradleRunConfiguration":
            continue

        name = config.attrib.get("name")
        if not name:
            raise AssertionError(f"{path} has no configuration name")

        external_path = config.find(".//option[@name='externalProjectPath']")
        if external_path is None or external_path.attrib.get("value") != "$PROJECT_DIR$":
            raise AssertionError(f"{name} does not point at $PROJECT_DIR$")

        task_values = [
            option.attrib["value"]
            for option in config.findall(".//option[@name='taskNames']/list/option")
            if "value" in option.attrib
        ]
        if not task_values:
            raise AssertionError(f"{name} has no Gradle task")
        configs[name] = task_values
    return configs


def main() -> int:
    configs = run_configs()

    missing_configs = sorted(REQUIRED_CONFIGS - configs.keys())
    if missing_configs:
        print("[FAIL] Missing Android Studio run configs:", file=sys.stderr)
        for name in missing_configs:
            print(f"  - {name}", file=sys.stderr)
        return 1

    missing_tasks: list[str] = []
    for name, task_names in sorted(configs.items()):
        for task_name in task_names:
            if not gradle_task_exists(task_name):
                missing_tasks.append(f"{name}: {task_name}")

    if missing_tasks:
        print("[FAIL] Run configs reference missing Gradle tasks:", file=sys.stderr)
        for item in missing_tasks:
            print(f"  - {item}", file=sys.stderr)
        return 1

    for name in sorted(REQUIRED_CONFIGS):
        print(f"[OK] {name}")
    print("[OK] Android Studio run configurations are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
