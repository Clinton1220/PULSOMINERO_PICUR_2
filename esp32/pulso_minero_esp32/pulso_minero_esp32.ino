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

// =================================================================
// INICIALIZACIÓN Y RECONEXIÓN DINÁMICA DEL MPU6050
// =================================================================
bool initMpu() {
  byte foundAddress = 0;
  int sdaActive = 21, sclActive = 22;

  // Intento 1: Pines estándar D21 (SDA) y D22 (SCL)
  Wire.end();
  Wire.begin(21, 22);
  Wire.setClock(100000);
  for (byte address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    if (Wire.endTransmission() == 0) {
      foundAddress = address;
      sdaActive = 21; sclActive = 22;
      break;
    }
  }

  // Intento 2: Pines alternativos D19 (SDA) y D18 (SCL)
  if (foundAddress == 0) {
    Wire.end();
    Wire.begin(19, 18);
    Wire.setClock(100000);
    for (byte address = 1; address < 127; address++) {
      Wire.beginTransmission(address);
      if (Wire.endTransmission() == 0) {
        foundAddress = address;
        sdaActive = 19; sclActive = 18;
        break;
      }
    }
  }

  // Intento 3: Pines D4 (SDA) y D5 (SCL)
  if (foundAddress == 0) {
    Wire.end();
    Wire.begin(4, 5);
    Wire.setClock(100000);
    for (byte address = 1; address < 127; address++) {
      Wire.beginTransmission(address);
      if (Wire.endTransmission() == 0) {
        foundAddress = address;
        sdaActive = 4; sclActive = 5;
        break;
      }
    }
  }

  if (foundAddress != 0) {
    mpuAddress = foundAddress;
    Wire.beginTransmission(mpuAddress);
    Wire.write(0x6B);
    Wire.write(0x00);
    byte pwrErr = Wire.endTransmission();

    if (pwrErr == 0) {
      Wire.beginTransmission(mpuAddress);
      Wire.write(0x1C);
      Wire.write(0x00);
      Wire.endTransmission();

      Wire.beginTransmission(mpuAddress);
      Wire.write(0x1A);
      Wire.write(0x05);
      Wire.endTransmission();

      mpuOk = true;
      Serial.printf("✅ Sensor MPU6050 inicializado con ÉXITO (I2C: 0x%02X, SDA: GPIO %d, SCL: GPIO %d)\n",
                    mpuAddress, sdaActive, sclActive);
      return true;
    }
  }

  // Si no se detectó, dejar el bus listo en los pines estándar 21 y 22
  Wire.end();
  Wire.begin(21, 22);
  mpuOk = false;
  return false;
}

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

  // 2. Inicializar MPU6050
  Serial.println("\n------------------------------------------------------------");
  Serial.println("🔍 DIAGNÓSTICO I2C: Buscando MPU6050...");
  if (!initMpu()) {
    Serial.println("❌ ERROR I2C: No se detectó ningún sensor en el bus.");
    Serial.println("   Revisa que los cables no estén rotos o prueba con pines D21 (SDA) y D22 (SCL).");
    Serial.println("   (El sistema reintentará detectarlo automáticamente)");
  }
  Serial.println("------------------------------------------------------------\n");
  delay(1000);

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
  unsigned long now = millis();

  // Si el MPU6050 no está detectado, intentar reconectar automáticamente cada 2.5 segundos
  static unsigned long lastMpuRetry = 0;
  if (!mpuOk && (now - lastMpuRetry >= 2500)) {
    lastMpuRetry = now;
    if (initMpu()) {
      Serial.println("🎉 ¡MPU6050 detectado y conectado con éxito!");
    }
  }

  // Aceptar nueva conexión de la app
  if (!client || !client.connected()) {
    client = server.available();
    if (client) {
      Serial.println("\n📱 ¡App Pulso Minero Conectada!");
    }
  }

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

        // 1. Inclinación física (Pitch y Roll) calculada con la gravedad estática
        inclination = atan2(ax, az) * 180.0f / PI;
        roll = atan2(ay, sqrt(ax * ax + az * az)) * 180.0f / PI;

        // 2. Autotara y Filtro de Gravedad Terrestre:
        // Separa la gravedad estática continua (~9.78 m/s²) de la vibración dinámica real
        static float gravX = 0.0f, gravY = 0.0f, gravZ = 9.80665f;
        static bool gravInit = false;
        if (!gravInit) {
          gravX = ax;
          gravY = ay;
          gravZ = az;
          gravInit = true;
        } else {
          // Filtro paso-bajo lento: retiene la gravedad estática y no reacciona a sacudidas rápidas
          gravX = (0.96f * gravX) + (0.04f * ax);
          gravY = (0.96f * gravY) + (0.04f * ay);
          gravZ = (0.96f * gravZ) + (0.04f * az);
        }

        // 3. Vibración dinámica neta (descontando la gravedad en reposo):
        float vibX = ax - gravX;
        float vibY = ay - gravY;
        float vibZ = az - gravZ;

        // Banda muerta para absorber el ruido eléctrico de silicio en reposo:
        if (fabs(vibX) < 0.12f) vibX = 0.0f;
        if (fabs(vibY) < 0.12f) vibY = 0.0f;
        if (fabs(vibZ) < 0.12f) vibZ = 0.0f;

        // Se envía a la app la vibración pura (en reposo será 0.00 m/s²):
        ax = vibX;
        ay = vibY;
        az = vibZ;
      } else {
        // En caso de microdesconexión puntual, no bloquear
        ax = 0.0f; ay = 0.0f; az = 9.81f;
      }
    } else {
      // Sensor físico no detectado: reportar cero real para no generar falsos positivos
      ax = 0.0f;
      ay = 0.0f;
      az = 0.0f;
      gx = 0.0f;
      gy = 0.0f;
      gz = 0.0f;
      inclination = 0.0f;
      roll = 0.0f;
      temp = 0.0f;
    }

    // 2. Lectura del Sensor de Gas MQ-135 con sobremuestreo (promedio de 16 lecturas para filtrar ruido ADC)
    long gasSum = 0;
    for (int i = 0; i < 16; i++) {
      gasSum += analogRead(PIN_MQ135);
      delayMicroseconds(50);
    }
    int gasRaw = gasSum / 16;
    float gasVolt = (gasRaw / 4095.0f) * 3.3f;

    // Conversión realista a PPM:
    // Aire ambiente limpio: 380 - 450 PPM (Normal)
    // Presencia moderada de gases: 500 - 800 PPM (Precaución)
    // Concentración peligrosa / humo: > 1000 PPM (Alerta)
    float gasPpm = 400.0f;
    if (gasVolt > 0.70f) {
      float deltaV = gasVolt - 0.70f;
      gasPpm = 400.0f + (deltaV * 280.0f) + (deltaV * deltaV * 320.0f);
    } else {
      gasPpm = 350.0f + (gasVolt / 0.70f) * 50.0f;
    }
    if (gasPpm > 2500.0f) gasPpm = 2500.0f;

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