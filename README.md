# Abanico

Escritorio (launcher) para Android con cajones que se despliegan en abanico circular.

## Cómo se instala

1. Cada vez que se sube código a `main`, GitHub compila la app sola (pestaña **Actions**).
2. El APK aparece en **Releases**. Ábrelo desde el móvil, descárgalo e instálalo (Android pedirá permitir instalar apps de esta fuente).
3. Para usarlo como pantalla de inicio: en Abanico, botón de ajustes → «Usar Abanico como pantalla de inicio».

Las actualizaciones se instalan encima sin perder la configuración, porque todas las versiones se firman con la misma clave (`ci/debug.keystore`).

## Qué hay dentro

- `lib/main.dart` — escritorio, reloj y cuadrícula de cajones.
- `lib/fan.dart` — el abanico circular (mantener pulsado, deslizar y soltar).
- `lib/pages.dart` — cajones: Apps, Fotos, Documentos, Internet e IA.
- `lib/explorer.dart` — explorador de archivos con doble panel para el plegable.
- `lib/settings.dart` — fondo, iconos, cajones, IA.
- `lib/state.dart` — configuración guardada y datos del móvil.
- `android/app/src/main/kotlin/.../MainActivity.kt` — lista de apps, iconos, abrir apps y permisos de archivos.
