import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'platform.dart';
import 'state.dart' show AppEntry;

/// Implementación de las funciones "nativas" para Windows, sin código C++:
/// usa PowerShell y programas del sistema.
class Desk {
  static final Map<String, String> _iconPaths = {};

  /// Se llama cuando termina de leerse el menú Inicio en segundo plano.
  static void Function(List<AppEntry>)? onAppsUpdated;

  static const _script = r'''
param([string]$Out)
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
$icons = Join-Path $Out 'icons'
New-Item -ItemType Directory -Force -Path $icons | Out-Null
$sh = New-Object -ComObject WScript.Shell
$lnk = @{}
foreach ($root in @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")) {
  Get-ChildItem -Path $root -Recurse -Filter *.lnk | ForEach-Object { if (-not $lnk.ContainsKey($_.BaseName)) { $lnk[$_.BaseName] = $_.FullName } }
}
function IconOf($src, $n) {
  try {
    $ic = [System.Drawing.Icon]::ExtractAssociatedIcon($src)
    if ($ic) { $p = Join-Path $icons ("$n.png"); $ic.ToBitmap().Save($p, [System.Drawing.Imaging.ImageFormat]::Png); return $p }
  } catch {}
  return ''
}
$res = New-Object System.Collections.ArrayList
$i = 0
$apps = @(Get-StartApps)
if ($apps.Count -gt 0) {
  foreach ($a in $apps) {
    $name = $a.Name
    if ($name -match '(?i)uninstall|desinstalar|readme|release notes') { continue }
    $src = $null
    if ($lnk.ContainsKey($name)) {
      $t = $sh.CreateShortcut($lnk[$name]).TargetPath
      if ($t -and (Test-Path $t)) { $src = $t } else { $src = $lnk[$name] }
    } elseif ($a.AppID -match '^[A-Za-z]:\\' -and (Test-Path $a.AppID)) { $src = $a.AppID }
    $icon = ''
    if ($src) { $i++; $icon = IconOf $src $i }
    [void]$res.Add([pscustomobject]@{ name = $name; id = ('app:' + $a.AppID); icon = $icon })
  }
} else {
  foreach ($k in $lnk.Keys) {
    if ($k -match '(?i)uninstall|desinstalar|readme') { continue }
    $i++
    [void]$res.Add([pscustomobject]@{ name = $k; id = ('lnk:' + $lnk[$k]); icon = (IconOf $lnk[$k] $i) })
  }
}
ConvertTo-Json -InputObject @($res) -Compress
''';

  static List<AppEntry> _parse(String s) {
    final out = <AppEntry>[];
    try {
      final data = jsonDecode(s);
      final list = data is List ? data : [data];
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        final name = (m['name'] ?? '') as String;
        final id = (m['id'] ?? '') as String;
        if (name.isEmpty || id.isEmpty) continue;
        final icon = (m['icon'] ?? '') as String;
        if (icon.isNotEmpty) _iconPaths[id] = icon;
        out.add(AppEntry(name, id));
      }
    } catch (_) {}
    final seen = <String>{};
    final unique = out.where((a) => seen.add(a.label.toLowerCase())).toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return unique;
  }

  static Future<List<AppEntry>> apps() async {
    final dir = await getApplicationSupportDirectory();
    final cache = File('${dir.path}/apps.json');
    if (await cache.exists()) {
      final list = _parse(await cache.readAsString());
      // Se actualiza en segundo plano por si has instalado algo nuevo.
      _scan(dir, cache).then((fresh) {
        if (fresh.isNotEmpty) onAppsUpdated?.call(fresh);
      });
      if (list.isNotEmpty) return list;
    }
    return _scan(dir, cache);
  }

  static Future<List<AppEntry>> _scan(Directory dir, File cache) async {
    try {
      final script = File('${dir.path}/leer_apps.ps1');
      await script.writeAsString(_script);
      final r = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script.path, '-Out', dir.path],
        stdoutEncoding: utf8,
      );
      final txt = (r.stdout as String).trim();
      final list = _parse(txt);
      if (list.isNotEmpty) await cache.writeAsString(txt);
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<Uint8List?> icon(String id) async {
    final p = _iconPaths[id];
    if (p == null) return null;
    try {
      return await File(p).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> launch(String id) async {
    try {
      if (id.startsWith('app:')) {
        await Process.start('explorer.exe', ['shell:AppsFolder\\${id.substring(4)}']);
      } else if (id.startsWith('lnk:')) {
        await Process.start('explorer.exe', [id.substring(4)]);
      } else {
        await Process.start('explorer.exe', [id]);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openUrl(String url, String? exe) async {
    try {
      if (exe != null && exe.isNotEmpty && File(exe).existsSync()) {
        await Process.start(exe, [url]);
      } else {
        await Process.start('rundll32.exe', ['url.dll,FileProtocolHandler', url]);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openPath(String path) async {
    try {
      await Process.start('explorer.exe', [winPath(path)]);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openUri(String uri) async {
    try {
      await Process.start('explorer.exe', [uri]);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Navegadores habituales que estén instalados.
  static Future<List<AppEntry>> browsers() async {
    final env = Platform.environment;
    final pf = env['ProgramFiles'] ?? 'C:\\Program Files';
    final pf86 = env['ProgramFiles(x86)'] ?? 'C:\\Program Files (x86)';
    final local = env['LOCALAPPDATA'] ?? '';
    final candidates = <(String, List<String>)>[
      ('Google Chrome', ['$pf\\Google\\Chrome\\Application\\chrome.exe', '$pf86\\Google\\Chrome\\Application\\chrome.exe', '$local\\Google\\Chrome\\Application\\chrome.exe']),
      ('Microsoft Edge', ['$pf86\\Microsoft\\Edge\\Application\\msedge.exe', '$pf\\Microsoft\\Edge\\Application\\msedge.exe']),
      ('Firefox', ['$pf\\Mozilla Firefox\\firefox.exe', '$pf86\\Mozilla Firefox\\firefox.exe']),
      ('Brave', ['$pf\\BraveSoftware\\Brave-Browser\\Application\\brave.exe', '$local\\BraveSoftware\\Brave-Browser\\Application\\brave.exe']),
      ('Opera', ['$local\\Programs\\Opera\\opera.exe']),
      ('Opera GX', ['$local\\Programs\\Opera GX\\opera.exe']),
      ('Vivaldi', ['$local\\Vivaldi\\Application\\vivaldi.exe', '$pf\\Vivaldi\\Application\\vivaldi.exe']),
    ];
    final out = <AppEntry>[];
    for (final c in candidates) {
      for (final p in c.$2) {
        if (File(p).existsSync()) {
          out.add(AppEntry(c.$1, p));
          break;
        }
      }
    }
    return out;
  }
}
