#!/usr/bin/env python3
"""Compile and run local safety checks. Mutations are confined to the marked fixture."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / ".fixtures/sample-home"
if not FIXTURE.exists():
    subprocess.run([sys.executable, str(ROOT / "scripts/create_fixtures.py")], check=True)
marker = FIXTURE / ".cleanup-mac-fixture"
if marker.read_text() != "cleanup-mac-test-home-v1\n" or FIXTURE.is_symlink():
    raise SystemExit("Invalid fixture; refusing test execution")
env = dict(os.environ, CLEANUP_MAC_FIXTURE_HOME=str(FIXTURE))
cache = Path("/private/tmp/clean-mac-test-cache")
cache.mkdir(exist_ok=True)
common = ["ScanScope", "AnalysisModels", "AnalysisCatalog", "AnalysisExclusions", "AnalysisEngine", "CleanupModels", "CleanupEngine", "TrashEngine", "AdvancedCleanupEngine", "ApplicationsEngine", "PersonalFileActions", "OrganizationEngine", "LargeFilesEngine", "SpaceLensEngine", "ProtectionEngine", "ProtectionFolderMonitor", "AnalysisViewModel", "SystemHealth", "ToolboxEngine", "PhotosClutterEngine", "AppSlimmingEngine"]
sources = [str(ROOT / "clean-mac" / (name + ".swift")) for name in common]
selected = sys.argv[1:] or [p.stem for p in sorted((ROOT / "tests").glob("*Smoke.swift"))]
for test in selected:
    target = ROOT / "tests" / (test + ".swift")
    if not target.is_file():
        raise SystemExit(f"Unknown test: {test}")
    executable = Path("/private/tmp") / ("clean-mac-" + test)
    print(f"Building {test}…", flush=True)
    extra = ["-D", "SMARTCARE_TESTING", str(ROOT / "clean-mac/SmartCareView.swift")] if test == "SmartCareSmoke" else []
    subprocess.run(["swiftc", "-D", "DEBUG", "-module-cache-path", str(cache), *sources, *extra, str(target), "-o", str(executable)], check=True, cwd=ROOT)
    subprocess.run([str(executable)], check=True, env=env, cwd=ROOT)
print(f"PASS: {len(selected)} local checks", flush=True)
