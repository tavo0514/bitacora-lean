# Bitácora Lean

Plataforma web para seguir ideas de negocio en clases de emprendimiento, inspirada en la metodología Lean Startup y en herramientas como LaunchPad Central.

## Qué hace

- **Cuentas con correo y contraseña** para cada estudiante, mentor y profesor/a. Solo las cuentas de profesor activadas por el administrador pueden crear cursos (con vencimiento opcional).
- **Cursos y equipos**: el profesor/a crea el curso y comparte su código. Cada estudiante elige su equipo o crea uno nuevo (un equipo por curso). Cada equipo tiene además un código para mentores.
- **Cierres semanales** del canvas: cuántos elementos tiene cada componente y cuántos se agregaron, eliminaron, validaron, invalidaron o editaron en la semana. Pueden ser manuales o automáticos (domingo 23:59).
- **Dos herramientas para representar la idea**: Business Model Canvas o Value Lab (Felin, Gambardella y Zenger, 2021: creencias, problemas y acciones). El profesor/a asigna cada equipo a una, a mano o al azar de forma balanceada, con historial de asignación para RCT.
- **Datos para investigación**: registro de cada cambio (quién, cuándo, antes y después), consentimiento informado opcional y exportación seudonimizada en JSON.
- **Entrevistas con clientes** vinculadas a las hipótesis que apoyan o refutan.
- **Bitácora semanal** con aprendizajes, cambios, próximos pasos y pivotes.
- **Retroalimentación** de mentores y profesor/a por bloque del canvas.
- **Versiones del canvas** para comparar cómo evoluciona el modelo.
- **Panel del curso** que compara a todos los equipos y se descarga como CSV.

## Quién puede hacer qué

| | Ver su equipo | Editar canvas, entrevistas y bitácora | Comentar | Ver todos los equipos del curso |
|---|---|---|---|---|
| Estudiante | Sí | Sí | Sí | No |
| Mentor | Sí | No | Sí | No |
| Profesor/a | Sí | Sí | Sí | Sí |

Estas reglas se aplican en la base de datos, así que un equipo no puede ver el trabajo de otro.

## Archivos

- `index.html`: la página completa.
- `config.js`: **el único archivo que hay que editar**, con la URL y la publishable key de Supabase.
- `supabase/schema.sql`: crea o actualiza las tablas y reglas de acceso. Se pega en el SQL Editor de Supabase; se puede ejecutar de nuevo sin perder datos.
- `supabase/cierre-automatico.sql` (opcional): programa el cierre automático de todos los equipos cada domingo.
- `supabase/hacerme-admin.sql`: convierte tu cuenta en administrador de la plataforma (se ejecuta una vez, con tu correo).

## Puesta en marcha (resumen)

1. Crear un proyecto gratuito en [Supabase](https://supabase.com).
2. En Supabase, abrir **SQL Editor**, pegar `supabase/schema.sql` y presionar **Run**.
3. Copiar la URL del proyecto y la publishable key en `config.js`.
4. Activar **GitHub Pages** en este repositorio (Settings → Pages → rama `main`, carpeta `/ (root)`).
5. En Supabase, **Authentication → URL Configuration**, poner la dirección de GitHub Pages como Site URL.

La guía paso a paso detallada está en el documento que acompaña este proyecto.
