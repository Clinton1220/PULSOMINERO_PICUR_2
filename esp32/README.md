# ESP32 PulsoMinero

## Hardware de referencia

- ESP32 con BLE.
- MPU6050 por I2C.
- `VCC -> 3V3`, `GND -> GND`, `SDA -> GPIO 21`, `SCL -> GPIO 22`.

## Arduino IDE

1. Instala el soporte de placas ESP32.
2. Instala las librerías `Adafruit MPU6050`, `Adafruit Unified Sensor`.
3. Selecciona tu placa ESP32 y el puerto COM.
4. Abre `pulso_minero_esp32.ino` y súbelo.
5. Abre el monitor serial a `115200`.

El ESP32 anuncia `PulsoMinero-ESP32` por BLE y notifica una muestra JSON cada 100 ms.

## Protocolo BLE

- Servicio: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
- Característica de lectura/notificación: `6e400003-b5a3-f393-e0a9-e50e24dcca9e`
- Una línea JSON por muestra:

```json
{"timestamp":12345,"x":0.12,"y":0.04,"z":9.81,"inclination":1.2,"sequence":10}
```

Las lecturas son aceleración en `m/s²`, no velocidad de vibración calibrada en `mm/s`. Antes de la demostración final hay que calibrar el sensor y definir la conversión/unidad con el asesor.
