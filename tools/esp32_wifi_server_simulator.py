"""
Servidor Simulador de ESP32 para Pruebas en PC (Python).
Permite probar la aplicación móvil Pulso Minero desde tu computadora
a través de Wi-Fi local sin necesidad de tener el ESP32 conectado.

Uso:
  python tools/esp32_wifi_server_simulator.py
"""

import socket
import time
import math
import random
import json

HOST = '0.0.0.0'  # Escuchar en todas las interfaces de red
PORT = 81         # Puerto TCP usado por la app

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def run_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(1)

    local_ip = get_local_ip()
    print("=" * 60)
    print("  SIMULADOR ESP32 PULSO MINERO (MODO WI-FI EN PC)")
    print("=" * 60)
    print(f"👉 Tu computadora está en la IP: {local_ip}")
    print(f"👉 En la App móvil, toca 'Wi-Fi' y escribe esta IP: {local_ip}")
    print(f"👉 Puerto: {PORT}")
    print("Esperando conexión de la aplicación móvil...")
    print("=" * 60)

    while True:
        try:
            client, addr = server.accept()
            print(f"\n📱 ¡App móvil conectada desde {addr[0]}:{addr[1]}!")
            seq = 0
            start_time = time.time()

            while True:
                now_ms = int((time.time()) * 1000)
                t = time.time() - start_time
                noise = (random.random() - 0.5) * 0.2

                # Generar datos de vibración simulados
                ax = round(0.75 * math.sin(2.0 * math.pi * 2.0 * t) + noise, 4)
                ay = round(0.25 * math.cos(2.0 * math.pi * 1.5 * t) + (noise * 0.5), 4)
                az = round(9.81 + 0.35 * math.sin(2.0 * math.pi * 3.0 * t), 4)
                inclination = round(2.0 + 1.2 * math.sin(t * 0.5), 3)

                payload = json.dumps({
                    "timestamp": now_ms,
                    "x": ax,
                    "y": ay,
                    "z": az,
                    "inclination": inclination,
                    "sequence": seq
                }) + "\n"

                client.sendall(payload.encode('utf-8'))
                seq += 1
                time.sleep(0.1)  # 10 muestras por segundo (100 ms)

        except (ConnectionResetError, BrokenPipeError):
            print("\n⚠️ La app móvil se ha desconectado. Esperando nueva conexión...")
        except KeyboardInterrupt:
            print("\nServidor simulador detenido.")
            break
        except Exception as e:
            print(f"Error: {e}")
            break

    server.close()

if __name__ == '__main__':
    run_server()
