# PulsoMinero API

Backend para enviar y verificar códigos de correo de registro y recuperación.

## Configuración

1. Instala Node.js 20 o superior.
2. Instala MongoDB local o crea una base en MongoDB Atlas.
3. Copia `.env.example` como `.env`.
4. Configura `MONGODB_URI` y las credenciales SMTP. Para Gmail usa una contraseña de aplicación, no la contraseña normal.
4. Ejecuta:

```powershell
npm install
npm start
```

La API queda en `http://localhost:3000`.

## Endpoints

- `GET /health`
- `POST /auth/request-code` con `{ "email": "...", "purpose": "registration|passwordRecovery" }`
- `POST /auth/verify-code` con `{ "email": "...", "purpose": "...", "code": "123456" }`
- `POST /auth/register` con `{ "email": "...", "password": "...", "verificationToken": "..." }`
- `POST /auth/reset-password` con `{ "email": "...", "password": "...", "verificationToken": "..." }`

Los usuarios se guardan en `users`. Los códigos se guardan con hash en `verification_codes` y MongoDB los elimina automáticamente después de su vencimiento. El código nunca se devuelve por la API.

Para el correo `ibarguenmurillob84@gmail.com`, el usuario debe registrarse con ese correo y tener acceso a su bandeja. El servidor SMTP enviará el código al destinatario indicado.
