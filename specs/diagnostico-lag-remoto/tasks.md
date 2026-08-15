# Tasks — Diagnóstico + paridad de rendimiento (split remoto)

> **Estado: COMPLETADO — verificado en runtime.** Sin lag ni pegado en ninguna
> parte del juego; prueba de apertura de sobres simultánea en ambas PC correcta.
> Los fixes se aplicaron **por repositorio separado**: `fifa14-fut-client`
> (PARITY-1, commit `146bf22`) y `fifa14-fut-server` (PARITY-3/4, spec, commit
> `9c7a4f7`).

## 1. Confirmar hipótesis (diagnóstico previo)

- [x] H1 (cliente): en `fifa14-fut-client/artifacts/frida.log`, los bursts de
      `cards-match-bridge-enter/leave-beta222` (193 eventos + cap 1000 en
      matchloop) coinciden con las ventanas de freeze; el comentario del propio
      código describe el stalling del render thread. **Confirmada.**
- [x] H2 (server): los gaps de 17-19 s tienen **cero connects y cero DNS**
      (commit `763b621`); la respuesta `empty-success-observation` a UTIL 9/4 y
      9/10 es idéntica en local y remoto. **Resuelta sin tocar TDF** (ver §5).
- [x] H3 (red): sockets sin `TCP_NODELAY` + RTT real de LAN. **Confirmada como
      causa de lag menor; mitigada por PARITY-3.**

## 2. FIX-P1 (cliente — helper Frida)

- [x] `frida_pc_fut_nav_route_patch_trace.py`: `MATCH_BRIDGE_TRACE_ENABLED =
      false` por defecto (el trace match-bridge no se instala en juego normal).
- [x] Añadir flag `--diagnose` (default off) que gatea `hookLongWaits`,
      per-socket I/O (`client-socket-io`) y los emits `client-connect-any`/
      `client-connect-result`/`client-dns-any`.
- [x] El rewrite funcional de `connect()` (`REDIRECT_PORTS`) permanece siempre
      activo (no depende de `--diagnose`).
- [x] `run_fifa14_remote_beta.ps1`: switch `-Diagnose` que pasa `--diagnose` al
      helper.
- [x] `python -m py_compile` del helper + commit + push en `fifa14-fut-client`
      (v2.40.11, `146bf22`).

## 3. FIX-P3 (server — TCP_NODELAY)

- [x] `probe.py`: `TCP_NODELAY` en los sockets aceptados (Blaze/redirector
      TLS/HTTP).
- [x] `python -m py_compile` de `probe.py`.

## 4. FIX-P4 (server — gate de debug logs)

- [x] `probe.py`: flag `--debug` (default off) que gatea `easfc-command-debug`
      (`:1778`) y `blaze-unhandled-command` (`:1803`).
- [x] `python -m py_compile` de `probe.py` + commit + push en
      `fifa14-fut-server` (`9c7a4f7`).

## 5. Verificación post-fix (PARITY-2 diferido)

- [x] Reproducir compra de packs tras PARITY-1/3/4: el gap de 17-19 s
      **desapareció**; apertura de sobres simultánea en ambas PC sin lag ni
      pegado. **PARITY-2 resuelto por el fix de overhead; no se requirió el
      deep-dive de UTIL 9/4-9/10.**
- [x] Deep-dive UTIL 9/4-9/10: **no necesario** (cancelado por el resultado de
      la prueba). Queda documentado por si un runtime futuro lo reabre.

## 6. Cierre

- [x] Regresión: login completo, navegación de FUT y partido funcionan con el
      trace off por defecto.
- [x] Veredicto redactado en `spec.md` (H1/H2/H3 confirmadas; PARITY-1/3/4
      exitosos).