# Changelog
 
Todos los cambios notables serán documentados aquí.
Formato basado en [Keep a Changelog](https://keepachangelog.com/).
 
## [1.2.0] - 2026-03-01
### Added
- Endpoint POST /api/v2/products para crear productos en lote.
- Soporte para autenticación OAuth2 con Google.
 
### Changed
- El límite de paginación se incrementó de 50 a 100.
 
### Fixed
- Corrección de memory leak en el worker de notificaciones.
 
### Deprecated
- Endpoint GET /api/v1/products será removido en v2.0.0.
 
## [1.1.0] - 2026-02-15
### Security
- Parchado vulnerabilidad XSS en formulario de búsqueda.
