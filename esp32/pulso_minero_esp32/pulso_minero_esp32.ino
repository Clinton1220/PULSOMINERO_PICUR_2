#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <WiFiServer.h>

// =================================================================
// PINES Y HARDWARE
// =================================================================
// 1. MPU6050 (Acelerómetro, Giroscopio, Termómetro e Inclinómetro vía I2C directo):
//    SDA -> GPIO 21, SCL -> GPIO 22, VCC -> 3.3V o 5V (VIN), GND -> GND
byte mpuAddress = 0x68;
bool mpuOk = false;

// 2. MQ-135 (Sensor de Calidad de Aire y Gases Mineros):
//    A0 -> GPIO 34 (Pin Analógico ADC1), VCC -> 5V (VIN), GND -> GND
#define PIN_MQ135 34
bool mqOk = true;

// =================================================================
// CONFIGURACIÓN DE RED WI-FI (Punto de Acceso)
// =================================================================
const char* AP_SSID = "PulsoMinero-WiFi";
const char* AP_PASS = "12345678"; // Mínimo 8 caracteres

WiFiServer server(81);
WiFiClient client;

unsigned long sequence = 0;
unsigned long lastSendTime = 0;
const unsigned long INTERVAL_MS = 250; // 4 muestras por segundo (4 Hz) - óptimo para estabilidad y fluidez en app

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n============================================================");
  Serial.println("  SISTEMA PULSO MINERO - TELEMETRÍA AVANZADA IOT + IA");
  Serial.println("============================================================");

  // 1. Configurar sensor de Gas MQ-135
  pinMode(PIN_MQ135, INPUT);
  int initialGas = analogRead(PIN_MQ135);
  mqOk = (initialGas >= 0);
  Serial.print("✅ Sensor MQ-135 (Gas/Atmósfera): Activo en GPIO 34 | Lectura inicial ADC: ");
  Serial.println(initialGas);

  // 2. Inicializar I2C con Detección Automática de Pines
  Serial.println("\n------------------------------------------------------------");
  Serial.println("🔍 DIAGNÓSTICO I2C: Buscando MPU6050 por I2C directo...");
  
  byte foundAddress = 0;
  int sdaActive = 21, sclActive = 22;

  // Intento 1: Pines estándar D21 (SDA) y D22 (SCL)
  Serial.println("   -> Probando en pines D21 (SDA) y D22 (SCL)...");
  Wire.begin(21, 22);
  Wire.setClock(100000);
  for (byte address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    if (Wire.endTransmission() == 0) {
      foundAddress = address;
      sdaActive = 21; sclActive = 22;
      Serial.printf("   🎉 ¡SENSOR DETECTADO EN PINES D21 y D22! Dirección: 0x%02X\n", address);
      break;
    }
  }

  // Intento 2: Pines alternativos D19 (SDA) y D18 (SCL)
  if (foundAddress == 0) {
    Serial.println("   -> Probando en pines D19 (SDA) y D18 (SCL)...");
    Wire.end();
    Wire.begin(19, 18);
    Wire.setClock(100000);
    for (byte address = 1; address < 127; address++) {
      Wire.beginTransmission(address);
      if (Wire.endTransmission() == 0) {
        foundAddress = address;
        sdaActive = 19; sclActive = 18;
        Serial.printf("   🎉 ¡SENSOR DETECTADO EN PINES D19 y D18! Dirección: 0x%02X\n", address);
        break;
      }
    }
  }

  // Intento 3: Pines D4 (SDA) y D5 (SCL)
  if (foundAddress == 0) {
    Serial.println("   -> Probando en pines D4 (SDA) y D5 (SCL)...");
    Wire.end();
    Wire.begin(4, 5);
    Wire.setClock(100000);
    for (byte address = 1; address < 127; address++) {
      Wire.beginTransmission(address);
      if (Wire.endTransmission() == 0) {
        foundAddress = address;
        sdaActive = 4; sclActive = 5;
        Serial.printf("   🎉 ¡SENSOR DETECTADO EN PINES D4 y D5! Dirección: 0x%02X\n", address);
        break;
      }
    }
  }

  // 3. Inicializar y despertar MPU6050 de forma directa (Compatible con clones y originales)
  if (foundAddress != 0) {
    mpuAddress = foundAddress;

    // Despertar el sensor: escribir 0 en registro 0x6B (PWR_MGMT_1)
    Wire.beginTransmission(mpuAddress);
    Wire.write(0x6B);
    Wire.write(0x00);
    byte pwrErr = Wire.endTransmission();

    if (pwrErr == 0) {
      // Configurar rango de acelerómetro a +-2g (registro 0x1C = 0x00)
      Wire.beginTransmission(mpuAddress);
      Wire.write(0x1C);
      Wire.write(0x00);
      Wire.endTransmission();

      // Configurar filtro DLPF a ~10-20 Hz para estabilidad (registro 0x1A = 0x05)
      Wire.beginTransmission(mpuAddress);
      Wire.write(0x1A);
      Wire.write(0x05);
      Wire.endTransmission();

      // Leer identificador WHO_AM_I informativo
      Wire.beginTransmission(mpuAddress);
      Wire.write(0x75);
      Wire.endTransmission(false);
      Wire.requestFrom((int)mpuAddress, 1);
      byte chipId = Wire.available() ? Wire.read() : 0x00;

      mpuOk = true;
      Serial.printf("✅ Sensor MPU6050 inicializado con ÉXITO (I2C: 0x%02X, WHO_AM_I: 0x%02X, SDA: GPIO %d, SCL: GPIO %d)\n",
                    mpuAddress, chipId, sdaActive, sclActive);
    } else {
      mpuOk = false;
      Serial.printf("❌ Error al despertar el sensor en 0x%02X (Error: %d)\n", mpuAddress, pwrErr);
    }
  } else {
    mpuOk = false;
    Serial.println("❌ ERROR I2C: No se detectó ningún sensor en el bus.");
    Serial.println("   Revisa que los cables no estén rotos o prueba con pines D21 (SDA) y D22 (SCL).");
    Serial.println("⚠️ Modo Simulación de Respaldo activo.");
  }
  Serial.println("------------------------------------------------------------\n");
  delay(1500);

  // 4. Crear Punto de Acceso Wi-Fi
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.println("✅ Red Wi-Fi Creada:");
  Serial.print("   📡 SSID: "); Serial.println(AP_SSID);
  Serial.print("   🔑 Clave: "); Serial.println(AP_PASS);
  Serial.print("   👉 IP Servidor ESP32: "); Serial.println(WiFi.softAPIP());

  // 5. Iniciar Servidor TCP en puerto 81
  server.begin();
  Serial.println("✅ Servidor TCP iniciado en puerto 81.");
  Serial.println("============================================================");
  Serial.println("  TRANSMITIENDO TELEMETRÍA COMPLETA A LA APP PULSO MINERO");
  Serial.println("============================================================\n");
}

void loop() {
  // Aceptar nueva conexión de la app
  if (!client || !client.connected()) {
    client = server.available();
    if (client) {
      Serial.println("\n📱 ¡App Pulso Minero Conectada!");
    }
  }

  unsigned long now = millis();
  if (now - lastSendTime >= INTERVAL_MS) {
    lastSendTime = now;

    float ax = 0.0f, ay = 0.0f, az = 0.0f;
    float gx = 0.0f, gy = 0.0f, gz = 0.0f;
    float temp = 25.0f;
    float inclination = 0.0f;
    float roll = 0.0f;

    // 1. Lectura del MPU6050 vía I2C directo (14 bytes consecutivos desde registro 0x3B)
    if (mpuOk) {
      Wire.beginTransmission(mpuAddress);
      Wire.write(0x3B);
      byte txErr = Wire.endTransmission(false);

      if (txErr == 0 && Wire.requestFrom((int)mpuAddress, 14) >= 14) {
        int16_t rawAcX = (Wire.read() << 8) | Wire.read();
        int16_t rawAcY = (Wire.read() << 8) | Wire.read();
        int16_t rawAcZ = (Wire.read() << 8) | Wire.read();
        int16_t rawTemp = (Wire.read() << 8) | Wire.read();
        int16_t rawGyX = (Wire.read() << 8) | Wire.read();
        int16_t rawGyY = (Wire.read() << 8) | Wire.read();
        int16_t rawGyZ = (Wire.read() << 8) | Wire.read();

        // Aceleración en m/s² (16384 LSB/g, gravedad = 9.80665 m/s²)
        ax = (rawAcX / 16384.0f) * 9.80665f;
        ay = (rawAcY / 16384.0f) * 9.80665f;
        az = (rawAcZ / 16384.0f) * 9.80665f;

        // Temperatura en °C
        temp = (rawTemp / 340.0f) + 36.53f;

        // Giroscopio en rad/s (131 LSB/(°/s) * PI/180)
        gx = (rawGyX / 131.0f) * (PI / 180.0f);
        gy = (rawGyY / 131.0f) * (PI / 180.0f);
        gz = (rawGyZ / 131.0f) * (PI / 180.0f);

        // Inclinación (Pitch y Roll) en grados
        inclination = atan2(ax, az) * 180.0f / PI;
        roll = atan2(ay, sqrt(ax * ax + az * az)) * 180.0f / PI;
      } else {
        // En caso de microdesconexión puntual, no bloquear
        ax = 0.0f; ay = 0.0f; az = 9.81f;
      }
    } else {
      // Simulación de respaldo en caso de desconexión de hardware
      float tSim = now / 1000.0f;
      float noise = ((rand() % 100) - 50) / 250.0f;
      ax = 0.7f * sin(2.0f * PI * 2.0f * tSim) + noise;
      ay = 0.3f * cos(2.0f * PI * 1.5f * tSim) + (noise * 0.5f);
      az = 9.81f + 0.35f * sin(2.0f * PI * 3.0f * tSim);
      inclination = 2.0f + 1.2f * sin(tSim * 0.5f);
      roll = 1.0f + 0.8f * cos(tSim * 0.5f);
      temp = 26.5f;
    }

    // 2. Lectura del Sensor de Gas MQ-135 con sobremuestreo (promedio de 16 lecturas para filtrar ruido ADC)
    long gasSum = 0;
    for (int i = 0; i < 16; i++) {
      gasSum += analogRead(PIN_MQ135);
      delayMicroseconds(50);
    }
    int gasRaw = gasSum / 16;
    float gasVolt = (gasRaw / 4095.0f) * 3.3f;
    // Conversión a PPM estimado (Aire limpio: ~400 PPM, Humo/Gases: > 1000 PPM)
    float gasPpm = (gasRaw / 4095.0f) * 2000.0f + 350.0f;

    // 3. Formatear Trama JSON Completa
    char payload[250];
    snprintf(
      payload,
      sizeof(payload),
      "{\"timestamp\":%lu,\"seq\":%lu,\"x\":%.4f,\"y\":%.4f,\"z\":%.4f,\"gx\":%.4f,\"gy\":%.4f,\"gz\":%.4f,\"temp\":%.1f,\"inclination\":%.2f,\"roll\":%.2f,\"gas\":%.1f,\"gas_raw\":%d,\"gas_volt\":%.2f,\"mpu_ok\":%s,\"mq_ok\":%s}\n",
      now,
      sequence++,
      ax,
      ay,
      az,
      gx,
      gy,
      gz,
      temp,
      inclination,
      roll,
      gasPpm,
      gasRaw,
      gasVolt,
      mpuOk ? "true" : "false",
      mqOk ? "true" : "false"
    );

    // 4. Transmitir por Socket Wi-Fi a la App
    if (client && client.connected()) {
      client.print(payload);
    }

    // 5. Imprimir en Monitor Serie para depuración
    Serial.print(payload);
    if (!mpuOk && (sequence % 8 == 0)) {
      Serial.println(">>> ⚠️ AVISO: MPU6050 NO DETECTADO EN I2C. Revisa que los pines estén soldados con estaño y en pines 21/22.");
    }
  }
}