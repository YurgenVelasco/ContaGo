# ContaGo — Decisión de arquitectura tecnológica

**Estado:** Arquitectura objetivo seleccionada  
**Proyecto:** ContaGo  
**Fecha:** Noviembre de 2026

## Objetivo

Construir ContaGo como una plataforma web de gestión financiera para pequeños negocios, priorizando tecnologías abiertas, portabilidad, mantenibilidad e independencia de proveedores de infraestructura.

## Stack seleccionado

| Componente | Tecnología |
|---|---|
| Lenguaje principal | TypeScript |
| Frontend | React + Vite |
| Backend | Node.js + Express |
| Base de datos | PostgreSQL |
| Comunicación | API REST sobre HTTPS |
| Validación | Zod |
| Pruebas | Vitest |
| Despliegue | Linux y contenedores OCI |

## Justificación

La elección busca unificar el desarrollo mediante TypeScript, facilitar la separación entre frontend y backend y evitar dependencias obligatorias de servicios exclusivos de un proveedor.

PostgreSQL permitirá trabajar con un sistema de base de datos relacional de código abierto.

La aplicación deberá poder ejecutarse localmente y desplegarse en diferentes infraestructuras compatibles.

## Principios arquitectónicos

1. Separación de responsabilidades.
2. Validación de datos en el servidor.
3. Autenticación y autorización seguras.
4. Transacciones para operaciones financieras.
5. Portabilidad de infraestructura y datos.
6. Configuración mediante variables de entorno.
7. Pruebas automatizadas.
8. Documentación actualizada.

## Alcance de esta decisión

Este documento establece la arquitectura objetivo de las próximas versiones de ContaGo.

**No implica que todos los componentes estén implementados actualmente.**

Las etapas anteriores desarrolladas con C# y .NET se conservan como antecedentes del proyecto.

## Próximos pasos

- [ ] Definir la estructura de carpetas del proyecto.
- [ ] Seleccionar el ORM.
- [ ] Diseñar el modelo relacional en PostgreSQL.
- [ ] Establecer el sistema de autenticación.
- [ ] Construir la API REST.
- [ ] Desarrollar la interfaz en React.
- [ ] Implementar pruebas automatizadas.
- [ ] Preparar el despliegue portable.
