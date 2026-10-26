# WorldShop 3.2 — Sistema de prueba de juegos en el servidor

## Archivos del proyecto

- `worldshop_server_3_2.lua` — **servidor**, con pruebas remotas, moderación local, tienda, cuentas, deployments y cajero.
- `worldshop_cliente_3_2.lua` — **cliente**: se incorpora la opción **Probar EN EL SERVIDOR** para las previews pendientes, sin necesidad de descargarlas.
- `worldshop_cajero_3_2.lua` — **cajero**. Se conserva la lógica de la versión recibida; solo se actualiza el comentario de versión.
- `ejemplo_juego_prueba.lua` — juego de prueba **opcional**, con controles de flechas y WorldTor.

## Qué cambia

1. El cliente de un desarrollador solicita `TEST_START` al servidor para un deployment **pendiente** de su propiedad. Se verifica la sesión WorldShop y la titularidad.
2. El servidor crea una sesión de prueba de Lua con pantalla de texto virtual, timers y archivos virtuales. El código del juego se ejecuta **en el servidor**, no en el cliente.
3. La pantalla viaja en paquetes `TEST_FRAME` y el teclado/ratón vuelve por `TEST_INPUT`. El cliente recibe actualizaciones y pide refrescos completos. Cierre mediante `TEST_STOP`.
4. El servidor admite **hasta dos pruebas remotas simultáneas**. Se agotan a los **180 segundos** y se pueden cerrar con **F7** o haciendo clic en **SALIR**.
5. La opción `[T] Probar` del servidor (Previews o Historial) se ha rehecho para utilizar el **mismo motor de ejecución** que las pruebas remotas. La barra del moderador conserva `F5` para aprobar, `F6` para rechazar y `F7` para salir.
6. El entorno de prueba no publica ni modifica el deployment: la escritura se queda en **RAM virtual**, con un límite de **64 KiB**. Se bloquea la API de hardware, HTTP y Rednet en el juego. Se conservan funciones útiles de `term`, `fs`, `os`, `shell`, `parallel`, `loadfile`, `require`, `paintutils` básicos y WorldTor.
7. La opción de descargar/ejecutar una preview localmente permanece como alternativa **explícita**, con aviso de falta de aislamiento.

## Instalación en CC:Tweaked

1. **Haz una copia de seguridad** de la carpeta `worldshop_data` del servidor y de tus antiguos scripts antes de sustituir nada.
2. En el ordenador servidor, coloca `worldshop_server_3_2.lua` (puedes renombrarlo a `worldshop_server.lua`) y ejecútalo: `worldshop_server` si lo renombraste o `worldshop_server_3_2` si conservas el nombre. Mantén el módem configurado.
3. En el ordenador cliente, coloca `worldshop_cliente_3_2.lua` y ejecútalo; entra con la cuenta de desarrollador original.
4. El cajero puede seguir funcionando con su archivo anterior; si deseas reemplazarlo, instala `worldshop_cajero_3_2.lua` en el ordenador del cajero. **No borres** `worldshop_cashier.cfg` ni `worldshop_cashier_pending`.
5. No elimines ni recrees la base de datos ni la carpeta `worldshop_data/deployments`.

## Cómo probar un juego remotamente

- En el cliente: **Dev Center** → **Historial de deployments** → `[T] Probar preview` → escribe el número `D` del deployment pendiente → `[1] Probar EN EL SERVIDOR`.
- El cliente muestra el juego mientras el servidor lo ejecuta. Las teclas y clics dentro del área del juego se reenvían; el encabezado de tres filas no llega al programa.
- `F7` o `[X] SALIR` desconectan la prueba.
- En el servidor: panel **`[2] Previews`** → selecciona un deployment → **`[T] Probar`**; `F5/F6/F7` permiten moderar. Desde **`[5] Historial`** puedes probar también versiones antiguas sin que el test cambie la versión publicada.

## Comprobaciones realizadas

- Se analizaron los tres archivos de WorldShop y los dos ejemplos World Shell enviados.
- Los tres archivos finales superaron una comprobación de **sintaxis Lua**.
- Se hicieron pruebas simuladas del motor para `loadfile`, almacenamiento virtual, temporizadores, `term.blit`, `parallel`, el **motor WorldTor real**, transferencia de pantalla, validación de acceso y cierre remoto.
- **No se ha ejecutado una prueba real dentro de Minecraft / CC:Tweaked**; por eso conviene comprobar primero con `ejemplo_juego_prueba.lua` y luego con tus juegos originales.

## Limitaciones y seguridad

**No es una máquina virtual segura para ejecutar código malicioso.** Aunque el entorno de Lua no expone las APIs del sistema operativo anfitrión, de HTTP, Rednet o periféricos, en algunas versiones de CC:Tweaked no se pueden interrumpir bucles Lua infinitos de forma fiable. Un juego hostil o defectuoso todavía podría colgar el ordenador servidor. Para evaluar código de terceros no confiable, usa **un ordenador de pruebas dedicado**, separado del servidor que contiene cuentas, compras y saldos.

Las comunicaciones **Rednet no están cifradas**. Usa una red de confianza y no compartas contraseñas, tokens ni claves del cajero. Los juegos que requieran acceso real a `peripheral`, `http`, `rednet`, `window` o APIs no implementadas pueden no funcionar en el modo de prueba remoto y deberán adaptarse o ejecutarse en un entorno preparado para esos permisos.