# Kali en QEMU/KVM: corrección del puntero desalineado (spice-vdagent 0.23)

[English](README.md)

En Kali Linux sobre QEMU/KVM con SPICE (virt-manager, GNOME Boxes), el puntero
del mouse puede desalinearse **después de un cambio de resolución de la VM**: la
flecha se dibuja en un lugar y el clic cae en otro. Este repositorio contiene
una solución pequeña, a nivel de usuario, que lo mantiene alineado de forma
automática, y la documentación de cómo se encontró la causa.

> **Estado (octubre de 2026): corregido en `spice-vdagent 0.23.0-4` de Debian y Kali.**
> Si tu distribución ya lo ofrece, actualiza y **reinicia la VM**; no necesitas
> esta solución:
>
> ```bash
> sudo apt update && sudo apt install spice-vdagent && sudo reboot
> ```
>
> La solución sigue siendo útil donde el paquete corregido aún no llega, por
> ejemplo Ubuntu 26.04 LTS (`0.23.0-1ubuntu0.1`) o un Kali que no se puede
> actualizar (`0.23.0-3`).

## Síntomas

- Seleccionar texto o hacer clic en menús y botones no acierta al objetivo.
- En resoluciones pequeñas que caben en la ventana del visor (1024x768,
  1280x800) el puntero funciona.
- El desfase aparece al maximizar, pasar a pantalla completa, redimensionar la
  ventana o fijar una resolución como 1920x1080.
- Cambiar el visor a X11 o el modelo de video de Virtio a QXL no lo arregla.

Comprueba tu versión dentro de la VM:

```bash
dpkg-query -W spice-vdagent
```

| Paquete | Estado |
|---|---|
| Debian stable 0.22.1 (compilado con GTK3) | No afectado |
| Debian y Kali compilados con GTK4, anteriores a 0.23.0-4 (p. ej. Kali 0.23.0-3) | Afectado |
| Ubuntu 26.04 LTS 0.23.0-1ubuntu0.1 | Afectado: compilado con GTK4 y sin el parche ([LP #2168964](https://bugs.launchpad.net/bugs/2168964)) |
| Debian y Kali 0.23.0-4 o posterior | **Corregido** (verificado en Kali 2026.2) |

## Corrección rápida (una vez)

Reiniciar el agente de sesión realinea el puntero hasta el siguiente cambio de
resolución. No requiere sudo:

```bash
pkill -x spice-vdagent
spice-vdagent
```

## Solución permanente

`vdagent-watch` escucha los eventos de cambio de pantalla de X (RandR) y
reinicia el agente cuando la resolución realmente cambia.

- **Basado en eventos:** espera bloqueado en `xev`, sin sondeo, así que no usa
  CPU ni batería mientras no pasa nada.
- **Un reinicio por cambio:** agrupa la ráfaga de eventos de un mismo
  redimensionado e ignora eventos repetidos con la misma resolución. Además
  reinicia el agente una vez al arrancar, por si ya estaba desfasado.
- **Solo a nivel de usuario:** dos archivos en tu home; no modifica paquetes
  del sistema.
- **Una sola instancia**, registra en el journal y **te avisa cuando Kali
  actualiza spice-vdagent**, para que sepas cuándo retirarlo.

### Instalación

Dentro de la VM Kali, desde una terminal en la sesión gráfica, con tu usuario
normal (no root):

```bash
git clone https://github.com/JorgeXern/kali-spice-vdagent-pointer-fix.git
cd kali-spice-vdagent-pointer-fix
./install.sh
```

El instalador agrega los paquetes que falten (`x11-utils`, `x11-xserver-utils`,
`spice-vdagent`), copia el script a `~/.local/bin/vdagent-watch`, crea
`~/.config/autostart/vdagent-watch.desktop` y lo inicia. Si tu spice-vdagent
ya trae la corrección, lo indica y se detiene (`--force` lo omite). Al arrancar reinicia
el agente una vez, así que si el puntero ya estaba desalineado se corrige de
inmediato, sin tener que cambiar la resolución.

### Comprobar que funciona

```bash
journalctl -t vdagent-watch -f
```

Cambia la resolución, por ejemplo con
`xrandr --output Virtual-1 --mode 1280x1024`, o redimensiona la ventana del
visor si tienes activado *Redimensionar automáticamente la MV con la ventana*.
Cada cambio registra una línea
como `resolution 1920x1080: agent restarted` y el puntero se alinea en uno o
dos segundos.

### Desinstalación

Cuando spice-vdagent se actualice, el script lo registra y muestra una
notificación. Si el puntero se mantiene alineado sin él:

```bash
./uninstall.sh
```

## Por qué ocurre

Con el agente SPICE activo, el puntero funciona en modo *client*: el visor
envía la posición absoluta del mouse y el agente la inyecta en Xorg mediante
un dispositivo virtual (`spice vdagent tablet` en `xinput list`). Para
traducir esa posición necesita la geometría actual de la pantalla.

El agente lee el tamaño de la pantalla al arrancar y debería actualizarlo con
cada evento RandR. En `src/vdagent/x11-randr.c` ese refresco estaba dentro de
`#ifndef USE_GTK_FOR_MONITORS`:

```c
void vdagent_x11_randr_handle_root_size_change(...)
{
#ifndef USE_GTK_FOR_MONITORS     /* se elimina al compilar con GTK4 */
    update_randr_res(x11, 0);
    ...
    x11->width[screen]  = width;
    x11->height[screen] = height;
#endif
```

Desde la 0.22.1-5, Debian compila el paquete con `--with-gtk4=yes`, que
define esa macro. La API de monitores de GTK solo responde en Wayland, así
que en X11 el agente se queda con la geometría inicial, la tableta virtual
conserva ese tamaño y las coordenadas absolutas se desfasan. Al reiniciarlo
vuelve a leer la geometría, que es justamente lo que esta solución automatiza.

No es código nuevo de la 0.23.0: `x11-randr.c` es idéntico en 0.22.1 y
0.23.0; lo expuso la compilación con GTK4. La corrección upstream
([MR !58](https://gitlab.freedesktop.org/spice/linux/vd_agent/-/merge_requests/58), [issue #47](https://gitlab.freedesktop.org/spice/linux/vd_agent/-/work_items/47)) elimina esas guardas y Debian la incluye
en la 0.23.0-4 (1 de octubre de 2026).

### Cómo se diagnosticó

| Prueba | Resultado | Conclusión |
|---|---|---|
| Resolución pequeña, escalado del visor en "Nunca" | Puntero OK | El desfase depende de la resolución |
| virt-manager forzado a X11 (`GDK_BACKEND=x11`) | Sigue desfasado | No es el visor en Wayland |
| Modelo de video Virtio → QXL | Sigue desfasado | No es el modelo de video |
| `xinput list` | QEMU USB Tablet y spice vdagent tablet presentes | Puntero absoluto bien configurado |
| Reiniciar el agente de sesión a 1920x1080 | **Puntero OK** | **Es el agente** (bug #9653) |
| Comparar el código de 0.22.1 y 0.23.0 | `x11-randr.c` idéntico; refresco excluido con GTK4 | Causa raíz: la compilación con GTK4 |
| Actualizar a 0.23.0-4 y reiniciar, sin el script | **Puntero OK** | **Corrección oficial verificada** |

## Corrección oficial

Actualizar a la 0.23.0-4 es la solución de fondo. Reinicia después: el agente
en ejecución sigue usando el binario anterior hasta que se reinicia (mientras
tanto, `ls -l /proc/$(pgrep -xo spice-vdagent)/exe` termina en `(deleted)`).
Para confirmar que tu paquete trae el parche:

```bash
zcat /usr/share/doc/spice-vdagent/changelog.Debian.gz | head -10   # cita LP: #2168964
```

## Consejos

- En virt-manager, deja **Vista → Escalar monitor → Nunca**, para que el
  visor muestre la VM 1:1 en lugar de estirarla.
- Instala los agentes en la VM: `sudo apt install -y spice-vdagent qemu-guest-agent`.
- Elige una forma de manejar la resolución. En ambos casos vdagent-watch
  realinea el puntero tras cada cambio.
  - **Seguir la ventana:** activa **Vista → Escalar monitor → Redimensionar
    automáticamente la MV con la ventana**. La resolución de la VM se ajusta
    al tamaño de la ventana del visor; no hace falta nada más.
  - **Resolución fija** (por ejemplo 1920x1080): desactiva *Redimensionar
    automáticamente la MV con la ventana*; si no, al cambiar el tamaño de la
    ventana se reemplaza tu resolución. Si Xfce no la restaura tras reiniciar,
    agrega una entrada de inicio automático que la fije. Cambia `Virtual-1` y
    `1920x1080` por el nombre de tu salida y un modo que aparezca en `xrandr`:

    ```bash
    cat > ~/.config/autostart/set-resolution.desktop <<'EOF'
    [Desktop Entry]
    Type=Application
    Name=Set resolution
    Exec=sh -c "sleep 3; xrandr --output Virtual-1 --mode 1920x1080"
    EOF
    ```

## Probado en

| Componente | Versión |
|---|---|
| Host | Fedora 44 Workstation, GNOME 50 (Wayland) |
| Virtualización | virt-manager 5.1.0, QEMU 10.2.2, libvirt 12.0.0 |
| VM | Q35, UEFI (OVMF), disco y red virtio, SPICE, tableta USB, video QXL o Virtio |
| Invitado | Kali Linux 2026.2, Xfce sobre X11, spice-vdagent 0.23.0-3 (bug) y 0.23.0-4 (corrección) |

Debería aplicar a cualquier invitado basado en Debian con spice-vdagent 0.23 en
X11. Los reportes de otras configuraciones son bienvenidos en los issues.

## Documentación

Guía completa con el detalle del diagnóstico, en PDF:
[Español](docs/kali-kvm-puntero-desalineado-spice-vdagent.pdf) ·
[English](docs/kali-kvm-misaligned-pointer-spice-vdagent.pdf)

## Referencias

- Kali Linux Bug Tracker #9653: spice-vdagent, possible regression, mouse
  pointer misaligns with cursor. <https://bugs.kali.org/view.php?id=9653>
- Ubuntu Discourse: Mouse pointer desync/offset on fresh Lubuntu 26.04
  (SPICE + VirtIO) after monitor size change. <https://discourse.ubuntu.com/t/82365>
- spice-vdagent upstream, MR !58: x11-randr: keep cache current on X11+GTK4
  builds. <https://gitlab.freedesktop.org/spice/linux/vd_agent/-/merge_requests/58>
- Launchpad #2168964 (Ubuntu). <https://bugs.launchpad.net/bugs/2168964>
- Debian Package Tracker: spice-vdagent. <https://tracker.debian.org/pkg/spice-vdagent>

## Licencia

[MIT](LICENSE) © 2026 JorgeXern
