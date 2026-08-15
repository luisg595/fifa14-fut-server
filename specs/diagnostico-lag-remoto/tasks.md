# Tasks — Diagnóstico + paridad de rendimiento (split remoto)

> Los fixes se aplican **por repositorio separado** y se commitean/pushean por
> separado: `fifa14-fut-client` (PARITY-1) y `fifa14-fut-server`
> (PARITY-3/4, spec). Ver `deploy.md` para el pull en cada máquina.

## 1. Confirmar hipótesis (diagnóstico previo)

- [ ] H1 (cliente): en `fifa14-fut-client/artifacts/frida.log`, alinear
      timestamps de `cards-match-bridge-enter/leave-beta222` con las ventanas de
      freeze/UI lenta.
- [ ] H2 (server): reproducir una compra; en `docker compose logs fifa14-fut`,
      localizar `blaze-unhandled-command`/`easfc-command-debug` en la ventana
      del gap de 17-19 s.
- [ ] H3 (red): medir RTT a `192.168.1.2:8099`, `:42128` y `:44125` desde la
      laptop; comparar cadencia de requests HTTP local vs remoto.

## 2. FIX-P1 (cliente — helper Frida)

- [ ] `frida_pc_fut_nav_route_patch_trace.py`: `MATCH_BRIDGE_TRACE_ENABLED =
      false` por defecto (el trace match-bridge no se instala en juego normal).
- [ ] Añadir flag `--diagnose` (default off) que gatea `hookLongWaits`,
      per-socket I/O (`client-socket-io`) y los emits `client-connect-any`/
      `client-connect-result`/`client-dns-any`.
- [ ] El rewrite funcional de `connect()` (`REDIRECT_PORTS`) permanece siempre
      activo (no depende de `--diagnose`).
- [ ] `run_fifa14_remote_beta.ps1`: switch `-Diagnose` que pasa `--diagnose` al
      helper.
- [ ] `python -m py_compile` del helper + commit + push en `fifa14-fut-client`.

## 3. FIX-P3 (server — TCP_NODELAY)

- [ ] `probe.py`: `TCP_NODELAY` en los sockets aceptados (Blaze/redirector
      TLS/HTTP).
- [ ] `python -m py_compile` de `probe.py`.

## 4. FIX-P4 (server — gate de debug logs)

- [ ] `probe.py`: flag `--debug` (default off) que gatea `easfc-command-debug`
      (`:1778`) y `blaze-unhandled-command` (`:1803`).
- [ ] `python -m py_compile` de `probe.py` + commit + push en
      `fifa14-fut-server`.

## 5. Verificación post-fix (PARITY-2 diferido)

- [ ] Reproducir una compra de packs tras PARITY-1/3/4: confirmar que el gap de
      17-19 s desaparece.
- [ ] Si persiste: SC-2 captura de UTIL 9/4 y 9/10 reales → reintroducir
      handlers con el TDF correcto **sin** romper el login (regresión prohibida).

## 6. Cierre

- [ ] Regresión: login completo, navegación de FUT y partido funcionan con el
      trace off por defecto.
- [ ] Redactar en `spec.md` el veredicto por hipótesis (confirmada/refutada) y
      el resultado de PARITY-1/3/4.