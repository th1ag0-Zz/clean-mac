#!/usr/bin/env python3
"""Cria uma home fictícia sob .fixtures, sem acessar arquivos do usuário."""

from datetime import datetime, timedelta
from pathlib import Path
import os
import plistlib


ROOT = Path(__file__).resolve().parents[1] / ".fixtures" / "sample-home"


def make_file(relative_path: str, content: bytes, days_old: int = 0) -> Path:
    path = ROOT / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    if days_old:
        timestamp = (datetime.now() - timedelta(days=days_old)).timestamp()
        os.utime(path, (timestamp, timestamp))
    return path


def main() -> None:
    # Falha se a fixture já existe: nunca sobrescreve dados preparados por um teste.
    ROOT.mkdir(parents=True, exist_ok=False)
    make_file(".cleanup-mac-fixture", b"cleanup-mac-test-home-v1\n")
    make_file("Library/Logs/old.log", b"old log\n", days_old=45)
    make_file("Library/Logs/recent.log", b"recent log\n")
    make_file("Library/Logs/unknown.data", b"unclassified\n", days_old=45)
    make_file("Library/Caches/CleanupMac/Regenerable/cache.bin", b"regenerable fixture\n", days_old=45)
    make_file("Library/Caches/UnknownApp/state.bin", b"unknown cache\n", days_old=45)
    make_file("Library/Caches/RecognizedApp/cache.bin", b"old cache\n", days_old=45)
    make_file("Library/Logs/DiagnosticReports/old.ips", b"crash report\n", days_old=45)
    make_file("Downloads/old-installer.dmg", b"installer\n", days_old=45)
    make_file("Downloads/new-installer.pkg", b"recent installer\n")
    make_file("Downloads/Archive/nested.dmg", b"nested installer\n", days_old=45)
    make_file("SystemRoot/Library/Caches/sample-system-cache.bin", b"system cache\n", days_old=45)
    make_file("SystemRoot/private/var/tmp/sample-temporary.tmp", b"temporary\n", days_old=45)
    make_file("SystemRoot/Library/Logs/sample-system.log", b"system log\n", days_old=45)
    make_file("SystemRoot/private/var/log/sample-var-system.log", b"system log\n", days_old=45)
    make_file("Library/Developer/Xcode/DerivedData/SampleProject/Build/object.o", b"build output\n", days_old=45)
    old_timestamp = (datetime.now() - timedelta(days=45)).timestamp()
    os.utime(ROOT / "Library/Developer/Xcode/DerivedData/SampleProject/Build",
             (old_timestamp, old_timestamp))
    make_file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/sample.pdf", b"mail download\n", days_old=45)
    make_file("Library/Application Support/MobileSync/Backup/sample-device/Manifest.db", b"backup\n", days_old=45)
    make_file("SystemRoot/Applications/Sample.app/Contents/Info.plist",
              plistlib.dumps({"CFBundleIdentifier": "fixture.sample", "CFBundleDevelopmentRegion": "en"}))
    make_file("SystemRoot/Applications/Sample.app/Contents/Resources/en.lproj/label.strings", b"English\n")
    make_file("SystemRoot/Applications/Sample.app/Contents/Resources/zz.lproj/label.strings", b"Fixture language\n")
    make_file(f"ExternalVolumes/SampleDisk/.Trashes/{os.getuid()}/sample-external.txt", b"external trash\n")
    make_file(".Trash/manual-review.txt", b"trash fixture\n")
    make_file("Documents/keep.txt", b"personal file\n")
    (ROOT / "Library/Logs/link-to-document.txt").symlink_to(
        ROOT / "Documents/keep.txt"
    )
    (ROOT / "Library/Logs/link-to-documents").symlink_to(
        ROOT / "Documents", target_is_directory=True
    )
    print(ROOT)


if __name__ == "__main__":
    main()
