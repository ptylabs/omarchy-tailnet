# Tailnet (ptylabs.tailnet)

Widget de barra para Omarchy, basado en el plugin integrado `omarchy.tailscale`
(MIT, Omarchy; `TailscaleIcon.qml` se reutiliza tal cual).

- Nombre del tailnet, sufijo MagicDNS y dispositivos en línea
- Lista de dispositivos (online y offline, con "visto hace…")
- Servicios detectados en cada dispositivo: sondeo TCP de una lista de puertos
  configurable a través del tailnet, más Tailscale Serve/Funnel de este equipo
- Subir y descargar archivos y carpetas por SSH/scp:
  - Subir: eliges "Archivos" (varios) o "Carpeta", y después la carpeta remota
    de destino navegando con fzf (`Ctrl-S` sube a la carpeta actual)
  - Descargar: navegas el remoto con fzf (`Tab` marca varios, `Ctrl-S` toda la
    carpeta actual) y eliges dónde guardar; si cancelas, va a `~/Downloads`
- SSH a cada dispositivo en un terminal nuevo (usa `tailscale ssh` cuando el
  peer ejecuta Tailscale SSH, `ssh` en caso contrario)

## Uso

Cada dispositivo muestra solo su nombre y los servicios detectados. A la
derecha de cada fila:

- 󰣀 SSH
- 󰓢 transferir: abre una caja con **Subir** (izquierda) y **Descargar** (derecha)
- 󰆏 copiar: abre una tarjeta para elegir la IP o el alias MagicDNS

Pasa el ratón por un dispositivo offline para ver cuándo se vio por última vez.
Pulsa `?` (o el icono de ayuda) para ver todos los atajos de teclado.

En la barra: clic izquierdo abre el panel, clic derecho activa/desactiva
Tailscale y clic central actualiza y reescanea.

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
