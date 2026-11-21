# 💰 ContaGo — Gestión financiera para pequeños negocios

### 📊 Organice sus finanzas. Controle su negocio. Tome mejores decisiones.

**ContaGo** es un proyecto de software orientado a facilitar la gestión financiera de pequeños negocios y emprendimientos mediante una plataforma web intuitiva, organizada y accesible.

Su propósito es ayudar a los emprendedores a mantener un mayor control sobre sus ingresos, gastos y movimientos financieros, ofreciendo herramientas que faciliten el seguimiento de sus operaciones y la toma de decisiones.

---

## 🎯 Objetivo del proyecto

Desarrollar una solución tecnológica que permita a los pequeños negocios gestionar su información financiera de manera sencilla, reduciendo la dependencia de registros manuales y facilitando la organización de sus operaciones económicas.

### ¿Qué problema busca resolver?

Muchos pequeños negocios administran sus ingresos y gastos mediante cuadernos, archivos dispersos o registros manuales, lo que dificulta:

- Identificar los ingresos y gastos del negocio.
- Llevar un control organizado de los movimientos financieros.
- Consultar información histórica.
- Analizar el comportamiento de las finanzas.
- Obtener reportes para apoyar decisiones administrativas.

**ContaGo busca centralizar esta información en una sola plataforma.**

---

## ✨ Funcionalidades del proyecto

El proyecto contempla las siguientes capacidades, implementadas o desarrolladas en sus distintas etapas:

### 📊 Panel de control

- Visualización general de la información financiera.
- Resumen de ingresos y gastos.
- Indicadores para el seguimiento de movimientos.
- Consulta de información relevante del negocio.

### 💵 Gestión de ingresos y gastos

- Registro de movimientos financieros.
- Clasificación de ingresos y egresos.
- Consulta del historial de operaciones.
- Organización de movimientos por categorías.

### 🗂️ Administración de categorías

- Creación y gestión de categorías.
- Clasificación de operaciones financieras.
- Organización de los registros del negocio.

### 📈 Reportes financieros

- Consulta de información financiera.
- Seguimiento de ingresos y gastos.
- Exportación de reportes en formatos como CSV y PDF, según la versión.

### 🔐 Seguridad y administración

- Autenticación de usuarios.
- Validación de información.
- Gestión administrativa.
- Controles de acceso según las funcionalidades de cada versión.

> **Nota:** ContaGo ha tenido diferentes etapas de desarrollo. Las funcionalidades descritas corresponden al alcance trabajado en el proyecto y no implican que todas estén disponibles en el código publicado actualmente en este repositorio.

---

## 🛠️ Tecnologías utilizadas

ContaGo ha sido trabajado con diferentes tecnologías durante su evolución.

### Ecosistema .NET

- **C#**
- **.NET / ASP.NET Core**
- **SQL Server**
- Herramientas de desarrollo de Microsoft

### Evolución hacia tecnologías web

El proyecto también ha explorado una arquitectura basada en:

- **Node.js**
- **Express**
- **React**
- **Vite**
- **JavaScript**
- **SQL Server**

La selección tecnológica definitiva dependerá de la versión que se continúe desarrollando.

---

## 🏗️ Arquitectura del sistema

ContaGo se plantea como una aplicación web que separa las responsabilidades de presentación, lógica de negocio y persistencia.

```text
            USUARIO
               |
               v
      INTERFAZ WEB
               |
               v
      LÓGICA DE NEGOCIO
               |
               v
       ACCESO A DATOS
               |
               v
          SQL SERVER
```

Esta separación busca facilitar el mantenimiento, la escalabilidad y la evolución futura de la aplicación.

---

## 📁 Estado actual del repositorio

La rama principal publicada actualmente contiene:

```text
ContaGo/
├── Contago.slnx
└── README.md
```

El archivo `Contago.slnx` referencia un proyecto .NET ubicado en:

```text
Contago/Contago.csproj
```

Sin embargo, los archivos de implementación de ese proyecto no se encuentran publicados actualmente en la rama principal.

### Estado de disponibilidad

- ✅ Repositorio público disponible.
- ✅ Archivo de solución .NET.
- ✅ Documentación general.
- ⏳ Código fuente completo pendiente de publicación o incorporación.
- ⏳ Instrucciones de instalación pendientes de documentar para una versión ejecutable.

**Actualmente no es posible garantizar la ejecución del sistema utilizando únicamente los archivos públicos del repositorio.**

---

## 🚀 Instalación y ejecución

La instalación se documentará cuando se publique una versión ejecutable de ContaGo.

Para una futura versión .NET, la ejecución podrá incluir herramientas como:

- .NET SDK de la versión correspondiente.
- SQL Server.
- Visual Studio o Visual Studio Code.

Los comandos, variables de entorno, migraciones y configuraciones de base de datos se documentarán de acuerdo con la implementación publicada.

---

## 🔒 Seguridad

La seguridad es un aspecto fundamental de ContaGo debido a la naturaleza financiera de la información.

Entre los objetivos técnicos del proyecto se encuentran:

- Protección de credenciales.
- Validación de entradas.
- Control de acceso por usuario.
- Protección de información financiera.
- Gestión segura de operaciones.
- Separación de configuraciones sensibles y código fuente.

Las medidas de seguridad deben verificarse sobre cada versión ejecutable antes de su uso en entornos reales.

---

## 🗺️ Hoja de ruta

- [ ] Publicar una versión ejecutable y documentada del sistema.
- [ ] Definir y consolidar la arquitectura tecnológica.
- [ ] Documentar la configuración de la base de datos.
- [ ] Incorporar pruebas automatizadas.
- [ ] Mejorar la documentación técnica de los módulos.
- [ ] Crear una demostración visual de la plataforma.
- [ ] Preparar una versión estable para pruebas con pequeños negocios.
- [ ] Evaluar futuras funcionalidades comerciales.

---

## 👥 Público objetivo

ContaGo está dirigido principalmente a:

- Pequeños negocios.
- Emprendedores.
- Comerciantes independientes.
- Personas que necesitan organizar las finanzas de sus actividades económicas.

El objetivo es facilitar el acceso a herramientas de organización financiera sin exigir conocimientos contables avanzados para las operaciones básicas.

---

## 👨‍💻 Autor

**Yurgen Andrey Velasco Rojas**

Aprendiz de Análisis y Desarrollo de Software (ADSO) del SENA.

Desarrollador de software con interés en el desarrollo backend, arquitectura de aplicaciones, bases de datos y tecnologías web.

### Perfil profesional

- GitHub: [@YurgenVelasco](https://github.com/YurgenVelasco)

---

## 📄 Derechos de autor y licencia

**Copyright © 2026 Yurgen Andrey Velasco Rojas.**

El repositorio no tiene actualmente una licencia de software abierta.

La disponibilidad pública del código o de la documentación no implica una autorización general para copiar, modificar, redistribuir o comercializar el software.

Las condiciones de licencia podrán definirse en una versión posterior del proyecto.

---

## 🌟 Visión

Convertir ContaGo en una herramienta útil para pequeños negocios que buscan mayor organización y control sobre su información financiera.

**ContaGo — Sus finanzas, más claras.**

Desarrollado con dedicación, aprendizaje continuo y pasión por la tecnología. 💻
