# PulsoMinero PICUR 2

Aplicación Flutter para monitorear vibraciones de maquinaria pesada, diferenciar ruido ambiental y registrar ensayos con reglas explicables.

## Aplicación Flutter

```powershell
flutter pub get
flutter test
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
```

## Backend

El backend usa Node.js, MongoDB y SMTP para usuarios, códigos de verificación y recuperación de cuentas.

```powershell
Copy-Item backend/.env.example backend/.env
cd backend
npm install
npm start
```

Configura `backend/.env` con `MONGODB_URI` y las credenciales SMTP antes de enviar correos reales. Nunca publiques `.env` ni credenciales.

Consulta [backend/README.md](backend/README.md) para los endpoints y la configuración detallada.
