import crypto from 'node:crypto';
import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import { MongoClient } from 'mongodb';
import nodemailer from 'nodemailer';

const port = Number(process.env.PORT ?? 3000);
const codeTtlMs = Number(process.env.CODE_TTL_MINUTES ?? 10) * 60 * 1000;
const resendMs = Number(process.env.CODE_RESEND_SECONDS ?? 60) * 1000;
const maxAttempts = Number(process.env.MAX_CODE_ATTEMPTS ?? 5);
const sessionTtlMs = Number(process.env.SESSION_TTL_MINUTES ?? 15) * 60 * 1000;
const mongoClient = new MongoClient(requiredEnv('MONGODB_URI'));
const database = mongoClient.db(process.env.MONGODB_DB ?? 'pulso_minero');
const users = database.collection('users');
const verificationCodes = database.collection('verification_codes');
const app = express();

app.use(cors({ origin: process.env.APP_ORIGIN?.split(',') ?? true }));
app.use(express.json({ limit: '20kb' }));

const mailer = nodemailer.createTransport({
  host: requiredEnv('SMTP_HOST'),
  port: Number(process.env.SMTP_PORT ?? 465),
  secure: String(process.env.SMTP_SECURE ?? 'true') === 'true',
  auth: { user: requiredEnv('SMTP_USER'), pass: requiredEnv('SMTP_PASSWORD') },
});

app.get('/health', async (_request, response) => {
  try {
    await database.command({ ping: 1 });
    response.json({ ok: true, database: 'connected' });
  } catch {
    response.status(503).json({ ok: false, database: 'disconnected' });
  }
});

app.post('/auth/request-code', async (request, response) => {
  const email = normalizeEmail(request.body?.email);
  const purpose = request.body?.purpose;
  if (!isEmail(email) || !isPurpose(purpose)) return response.status(400).json({ error: 'Correo o propósito inválido.' });

  if (purpose === 'registration' && await users.findOne({ email })) return response.status(409).json({ error: 'Ese correo ya está registrado.' });
  if (purpose === 'passwordRecovery' && !(await users.findOne({ email }))) return response.status(404).json({ error: 'No existe una cuenta con ese correo.' });

  const key = `${purpose}:${email}`;
  const previous = await verificationCodes.findOne({ key });
  if (previous && Date.now() - previous.sentAt.getTime() < resendMs) return response.status(429).json({ error: 'Espera antes de solicitar otro código.' });

  const code = crypto.randomInt(100000, 1000000).toString();
  const expiresAt = new Date(Date.now() + codeTtlMs);
  await verificationCodes.updateOne({ key }, { $set: { key, email, purpose, codeHash: hashCode(code), sentAt: new Date(), expiresAt, attempts: 0 }, $unset: { verificationTokenHash: '', tokenExpiresAt: '' } }, { upsert: true });

  try {
    await mailer.sendMail({
      from: process.env.MAIL_FROM,
      to: email,
      subject: purpose === 'registration' ? 'Verifica tu cuenta PulsoMinero' : 'Recupera tu cuenta PulsoMinero',
      text: `Tu código de verificación es ${code}. Expira en ${process.env.CODE_TTL_MINUTES ?? 10} minutos. Si no solicitaste este código, ignora este correo.`,
      html: `<p>Tu código de verificación es:</p><h1 style="letter-spacing: 6px">${code}</h1><p>Expira en ${process.env.CODE_TTL_MINUTES ?? 10} minutos.</p>`,
    });
  } catch (error) {
    await verificationCodes.deleteOne({ key });
    console.error('No se pudo enviar el correo:', error.message);
    return response.status(502).json({ error: 'No se pudo enviar el correo.' });
  }
  return response.status(202).json({ expiresAt: expiresAt.toISOString() });
});

app.post('/auth/verify-code', async (request, response) => {
  const email = normalizeEmail(request.body?.email);
  const purpose = request.body?.purpose;
  const code = String(request.body?.code ?? '').trim();
  const key = `${purpose}:${email}`;
  const record = await verificationCodes.findOne({ key });
  if (!isEmail(email) || !isPurpose(purpose) || !/^\d{6}$/.test(code) || !record) return response.status(400).json({ verified: false, error: 'Código inválido.' });
  if (Date.now() > record.expiresAt.getTime() || record.attempts >= maxAttempts) {
    await verificationCodes.deleteOne({ key });
    return response.status(400).json({ verified: false, error: 'Código vencido.' });
  }
  await verificationCodes.updateOne({ key }, { $inc: { attempts: 1 } });
  if (!safeEqual(record.codeHash, hashCode(code))) return response.status(400).json({ verified: false, error: 'Código incorrecto.' });

  const verificationToken = crypto.randomBytes(32).toString('hex');
  await verificationCodes.updateOne({ key }, { $set: { verificationTokenHash: hashCode(verificationToken), tokenExpiresAt: new Date(Date.now() + sessionTtlMs) }, $unset: { codeHash: '' } });
  return response.json({ verified: true, verificationToken });
});

app.post('/auth/register', async (request, response) => {
  const email = normalizeEmail(request.body?.email);
  const displayName = normalizeName(request.body?.displayName);
  const password = String(request.body?.password ?? '');
  const token = String(request.body?.verificationToken ?? '');
  if (!isEmail(email) || !displayName || !isStrongPassword(password)) return response.status(400).json({ error: 'Datos inválidos.' });
  if (!(await consumeVerificationToken(email, 'registration', token))) return response.status(401).json({ error: 'Verificación requerida o vencida.' });
  try {
    await users.insertOne({ email, displayName, passwordHash: hashPassword(password), createdAt: new Date(), verifiedAt: new Date() });
  } catch (error) {
    if (error.code === 11000) return response.status(409).json({ error: 'Ese correo ya está registrado.' });
    throw error;
  }
  return response.status(201).json({ created: true });
});

app.post('/auth/login', async (request, response) => {
  const email = normalizeEmail(request.body?.email);
  const password = String(request.body?.password ?? '');
  const user = await users.findOne({ email });
  if (!user || !verifyPassword(password, user.passwordHash)) {
    return response.status(401).json({ error: 'Correo o contraseña incorrectos.' });
  }
  return response.json({ email: user.email, displayName: user.displayName ?? null });
});

app.post('/auth/reset-password', async (request, response) => {
  const email = normalizeEmail(request.body?.email);
  const password = String(request.body?.password ?? '');
  const token = String(request.body?.verificationToken ?? '');
  if (!isEmail(email) || !isStrongPassword(password)) return response.status(400).json({ error: 'Datos inválidos.' });
  if (!(await consumeVerificationToken(email, 'passwordRecovery', token))) return response.status(401).json({ error: 'Verificación requerida o vencida.' });
  const result = await users.updateOne({ email }, { $set: { passwordHash: hashPassword(password), updatedAt: new Date() } });
  if (!result.matchedCount) return response.status(404).json({ error: 'Cuenta no encontrada.' });
  return response.json({ updated: true });
});

async function consumeVerificationToken(email, purpose, token) {
  if (!token) return false;
  const result = await verificationCodes.findOneAndDelete({ key: `${purpose}:${email}`, verificationTokenHash: hashCode(token), tokenExpiresAt: { $gt: new Date() } });
  return Boolean(result);
}
function requiredEnv(name) { if (!process.env[name]) throw new Error(`Falta configurar ${name} en backend/.env`); return process.env[name]; }
function normalizeEmail(value) { return String(value ?? '').trim().toLowerCase(); }
function normalizeName(value) { return String(value ?? '').trim().replace(/\s+/g, ' ').slice(0, 80); }
function isEmail(value) { return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value); }
function isPurpose(value) { return value === 'registration' || value === 'passwordRecovery'; }
function isStrongPassword(value) { return value.length >= 8 && /[A-Z]/.test(value) && /[a-z]/.test(value) && /[0-9]/.test(value) && /[^A-Za-z0-9]/.test(value); }
function hashCode(value) { return crypto.createHash('sha256').update(value).digest('hex'); }
function hashPassword(value) {
  const salt = crypto.randomBytes(16).toString('hex');
  return `${salt}:${crypto.scryptSync(value, salt, 64).toString('hex')}`;
}
function verifyPassword(value, storedHash) {
  if (!storedHash?.includes(':')) return false;
  const [salt, hash] = storedHash.split(':');
  const candidate = crypto.scryptSync(value, salt, 64).toString('hex');
  return safeEqual(hash, candidate);
}
function safeEqual(left, right) { const a = Buffer.from(left); const b = Buffer.from(right); return a.length === b.length && crypto.timingSafeEqual(a, b); }

async function start() {
  await mongoClient.connect();
  await users.createIndex({ email: 1 }, { unique: true });
  await verificationCodes.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
  await verificationCodes.createIndex({ key: 1 }, { unique: true });
  app.listen(port, () => console.log(`PulsoMinero API escuchando en http://localhost:${port}`));
}

start().catch((error) => {
  console.error('No se pudo iniciar el backend:', error.message);
  process.exit(1);
});
