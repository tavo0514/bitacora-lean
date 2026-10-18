# Bitácora Lean

Plataforma web para seguir ideas de negocio en clases de emprendimiento, inspirada en la metodología Lean Startup y en herramientas como LaunchPad Central.

## Qué hace

- **Cuentas con correo y contraseña** para cada estudiante, mentor y profesor/a.
- **Cursos y equipos**: el profesor/a crea un curso y sus equipos. Cada equipo tiene un código para estudiantes y otro para mentores.
- **Business Model Canvas** con hipótesis por bloque y su estado: por validar, validada o invalidada.
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
- `supabase/schema.sql`: crea las tablas y reglas de acceso. Se pega una vez en el SQL Editor de Supabase.

## Puesta en marcha (resumen)

1. Crear un proyecto gratuito en [Supabase](https://supabase.com).
2. En Supabase, abrir **SQL Editor**, pegar `supabase/schema.sql` y presionar **Run**.
3. Copiar la URL del proyecto y la publishable key en `config.js`.
4. Activar **GitHub Pages** en este repositorio (Settings → Pages → rama `main`, carpeta `/ (root)`).
5. En Supabase, **Authentication → URL Configuration**, poner la dirección de GitHub Pages como Site URL.

La guía paso a paso detallada está en el documento que acompaña este proyecto.
