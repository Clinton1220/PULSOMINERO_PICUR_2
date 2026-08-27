#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <WiFiServer.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

// =================================================================
// PINES Y HARDWARE
// =================================================================
// 1. MPU6050 (Acelerómetro, Giroscopio, Termómetro e Inclinómetro):
//    SDA -> GPIO 21, SCL -> GPIO 22, VCC -> 3.3V, GND -> GND
Adafruit_MPU6050 mpu;
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
const unsigned long INTERVAL_MS = 100; // 10 muestras por segundo (10 Hz)

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

  // 2. Inicializar I2C e intentar detectar MPU6050 en 0x68 o 0x69
  Wire.begin(21, 22);
  if (mpu.begin(0x68, &Wire) || mpu.begin(0x69, &Wire)) {
    // Máxima sensibilidad para detectar microvibraciones y movimientos sutiles
    mpu.setAccelerometerRange(MPU6050_RANGE_2_G);
    mpu.setGyroRange(MPU6050_RANGE_250_DEG);
    mpu.setFilterBandwidth(MPU6050_BAND_44_HZ);
    mpuOk = true;
    Serial.println("✅ Sensor MPU6050 (Geófono/Inclinómetro): Detectado en I2C | Rango: ±2G | Filtro: 44Hz");
  } else {
    mpuOk = false;
    Serial.println("⚠️ MPU6050 no detectado en I2C -> Modo Simulación de Respaldo activo.");
  }

  // 3. Crear Punto de Acceso Wi-Fi
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.println("✅ Red Wi-Fi Creada:");
  Serial.print("   📡 SSID: "); Serial.println(AP_SSID);
  Serial.print("   🔑 Clave: "); Serial.println(AP_PASS);
  Serial.print("   👉 IP Servidor ESP32: "); Serial.println(WiFi.softAPIP());

  // 4. Iniciar Servidor TCP en puerto 81
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

    // 1. Lectura del MPU6050
    if (mpuOk) {
      sensors_event_t a, g, t;
      mpu.getEvent(&a, &g, &t);
      ax = a.acceleration.x;
      ay = a.acceleration.y;
      az = a.acceleration.z;
      gx = g.gyro.x;
      gy = g.gyro.y;
      gz = g.gyro.z;
      temp = t.temperature;

      // Inclinación (Pitch y Roll) en grados
      inclination = atan2(ax, az) * 180.0f / PI;
      roll = atan2(ay, sqrt(ax * ax + az * az)) * 180.0f / PI;
    } else {
      // Simulación en caso de desconexión accidental de cable
      float tSim = now / 1000.0f;
      float noise = ((rand() % 100) - 50) / 250.0f;
      ax = 0.7f * sin(2.0f * PI * 2.0f * tSim) + noise;
      ay = 0.3f * cos(2.0f * PI * 1.5f * tSim) + (noise * 0.5f);
      az = 9.81f + 0.35f * sin(2.0f * PI * 3.0f * tSim);
      inclination = 2.0f + 1.2f * sin(tSim * 0.5f);
      roll = 1.0f + 0.8f * cos(tSim * 0.5f);
      temp = 26.5f;
    }

    // 2. Lectura del Sensor de Gas MQ-135
    int gasRaw = analogRead(PIN_MQ135);
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
  }
}
