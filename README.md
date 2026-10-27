# Tailnet (ptylabs.tailnet)

Widget de barra para Omarchy, basado en el plugin integrado `omarchy.tailscale`
(MIT, Omarchy; `TailscaleIcon.qml` se reutiliza tal cual).

- Nombre del tailnet, sufijo MagicDNS y dispositivos en línea
- Lista de dispositivos (online y offline, con "visto hace…")
- Servicios detectados en cada dispositivo: sondeo TCP de una lista de puertos
  configurable a través del tailnet, más Tailscale Serve/Funnel de este equipo
- Subir y descargar archivos por SSH/scp: eliges ficheros locales y navegas
  las carpetas remotas con fzf (`Ctrl-S` sube/descarga en la carpeta actual,
  `Tab` marca varios). Las descargas van a `~/Downloads` por defecto
- SSH a cada dispositivo en un terminal nuevo (usa `tailscale ssh` cuando el
  peer ejecuta Tailscale SSH, `ssh` en caso contrario)

## Uso

- Clic izquierdo: abrir panel · clic derecho: activar/desactivar Tailscale ·
  clic central: actualizar y escanear
- Dentro del panel: `j`/`k` mover, `↵` SSH, `u` subir, `b` bajar (descargar), `c` copiar IP, `d` copiar DNS,
  `o` abrir el primer servicio web, `r` reescanear, `t` on/off, `esc` cerrar
- Clic en un servicio: web → navegador, ssh → terminal, resto → copia `host:puerto`

## Ajustes

Desde los ajustes del widget en la barra: intervalo de refresco, intervalo de
escaneo, puertos a sondear, usuario SSH, destino SSH (MagicDNS o IP) y mostrar
dispositivos offline.

## Instalar / actualizar

Desde GitHub:

    omarchy plugin add https://github.com/ptylabs/omarchy-tailnet --enable

Desde una copia local:

    ./install.sh

Copia el plugin a `~/.config/omarchy/plugins/ptylabs.tailnet/` y lo activa.
Ejecútalo de nuevo tras cada cambio en este directorio (reinicia el shell
para que se carguen los cambios).
