"""Run the actual iOS PNG/disk code on macOS using minimal Flutter transport stubs."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='ballistic-frame-test-') as folder:
    source = (repo / 'ios/Runner/FrameCapture.swift').read_text().replace('import Flutter\n', '')
    original = '''FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("BallisticScans", isDirectory: true)'''
    assert original in source
    source = source.replace(original, f'URL(fileURLWithPath: "{folder}/capture", isDirectory: true)')
    main = Path(folder) / 'main.swift'
    main.write_text(source + '\n' + (repo / 'test/frame_capture_native_harness.swift').read_text())
    binary = Path(folder) / 'native-test'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', folder + '/modules', str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
