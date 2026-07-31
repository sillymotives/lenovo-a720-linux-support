# Desktop polish notes

## Picom shutdown ghost rectangle

On Xfce/X11 with the XRender backend, Picom fading could leave a blank translucent rectangle visible briefly while the session was shutting down. The stale surface disappeared completely when Picom was stopped before shutdown.

The minimal fix was to keep compositing and opacity enabled, but disable fading:

```conf
backend = "xrender";
fading = false;
```

This preserves transparent windows while preventing the cached fade-out surface from lingering as Xfce tears down the desktop.

A typical configuration can retain settings such as:

```conf
active-opacity = 0.94;
inactive-opacity = 0.88;
inactive-opacity-override = false;
```

Restart Picom after editing:

```bash
pkill -x picom || true
picom --config "$HOME/.config/picom/picom.conf" --daemon
```

Confirm the process is running:

```bash
pgrep -a picom
```

The observed user-session warnings from `xfce4-notifyd` and `xdg-desktop-portal-gtk` occurred during teardown, but there was no GPU reset, Xorg crash, kernel panic, or shutdown failure. The visual artefact was cosmetic.
