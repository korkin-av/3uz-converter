import serial
import time
import json
import os
import subprocess
from tabulate import tabulate
from colorama import init, Fore, Back, Style
import sys
import select
import matplotlib
# Используем Agg для сохранения графика, затем переключаемся на TkAgg для отображения
matplotlib.use('Agg')  # Для сохранения без GUI
import matplotlib.pyplot as plt

# Инициализация colorama для цветного вывода
init()

# Исходная таблица интерполяции (29 точек, исправлена точка {2.190, 86.0})
original_table = [
    (0.650, 8.0), (0.700, 10.0), (1.111, 12.0), (1.565, 23.0), (1.600, 25.0),
    (1.760, 32.0), (1.865, 43.0), (2.010, 60.0), (2.100, 70.0), (2.175, 76.0),
    (2.190, 86.0), (2.270, 105.0), (2.430, 126.0), (2.500, 145.0), (2.562, 165.0),
    (2.675, 200.0), (2.775, 236.0), (2.875, 271.0), (2.925, 288.0), (2.975, 297.0),
    (3.475, 387.0), (3.975, 477.0), (4.475, 567.0), (4.54383, 579.39),
    (4.61266, 591.78), (4.68149, 604.17), (4.75032, 616.56), (4.81915, 628.95),
    (4.888, 641.34)
]

# Функция интерполяции для исходной таблицы
def get_original_frequency(v):
    """Вычисляет частоту для заданного напряжения из исходной таблицы"""
    if v <= 0.690:
        return 7.0
    if v <= original_table[0][0]:
        return original_table[0][1]
    if v >= original_table[-1][0]:
        return original_table[-1][1]
    for i in range(len(original_table) - 1):
        if v >= original_table[i][0] and v < original_table[i + 1][0]:
            v1, f1 = original_table[i]
            v2, f2 = original_table[i + 1]
            t = (v - v1) / (v2 - v1)
            return f1 + t * (f2 - f1)
    return original_table[-1][1]

# Подключение к Arduino
try:
    ser = serial.Serial('/dev/ttyUSB0', 9600, timeout=1)
    time.sleep(2)  # Даём время на установку соединения
    print("Подключено к /dev/ttyUSB0")
except serial.SerialException as e:
    print(f"Ошибка подключения к /dev/ttyUSB0: {e}")
    sys.exit(1)

def get_table():
    """Получить текущую таблицу интерполяции с Arduino"""
    try:
        ser.reset_input_buffer()  # Очищаем буфер
        print("Отправка команды get...")
        ser.write(b"get\n")
        time.sleep(0.5)  # Ждём ответа от Arduino
        table = []
        max_attempts = 100  # Увеличенное количество попыток
        attempts = 0
        while attempts < max_attempts:
            if ser.in_waiting > 0:  # Проверяем наличие данных
                line = ser.readline().decode('utf-8', errors='ignore').strip()
                # Пропускаем отладочные сообщения без вывода
                if not line.startswith("DEBUG"):
                    if line == "END":
                        break
                    if line and ": " in line:
                        try:
                            index, values = line.split(": ")
                            voltage, frequency = values.split(" ")
                            table.append([int(index), float(voltage), float(frequency)])
                        except ValueError:
                            pass  # Пропускаем ошибки парсинга
            attempts += 1
            time.sleep(0.01)  # Небольшая задержка
        if attempts >= max_attempts:
            print("Ошибка: не получен END от Arduino")
        return table
    except Exception as e:
        print(f"Ошибка в get_table: {e}")
        return []

def display_table():
    """Отобразить таблицу компактно с цветным градиентом и старыми частотами"""
    print("Получение таблицы...")
    table = get_table()
    if not table:
        print("Ошибка: Таблица пуста или не получена")
        return

    # Подготовка данных для таблицы
    headers = ["Индекс", "V", "Hz", "Old Hz"]
    table_with_old = []
    for index, voltage, frequency in table:
        old_frequency = get_original_frequency(voltage)  # Частота из исходной таблицы
        table_with_old.append([index, f"{voltage:.3f}", f"{frequency:.2f}", f"{old_frequency:.2f}"])

    # Вывод компактной таблицы
    print("\n=== Таблица интерполяции ===")
    table_str = tabulate(table_with_old, headers=headers, tablefmt="plain")
    # Разделяем строки таблицы для цветного вывода
    lines = table_str.split('\n')
    for i, line in enumerate(lines):
        if i == 0:  # Заголовок без градиента
            print(line)
        else:
            # Рассчитываем цвет на основе индекса (градиент от зелёного к красному)
            index = i - 1  # Смещение, так как первая строка — заголовок
            green = int(255 * (1 - index / (len(table) - 1)))
            red = int(255 * index / (len(table) - 1))
            color_code = f"\033[38;2;{red};{green};0m"
            print(f"{color_code}{line}{Style.RESET_ALL}")

def plot_table():
    """Построить график зависимости частоты от напряжения"""
    print("Получение таблицы для графика...")
    try:
        table = get_table()
        if not table:
            print("Ошибка: Таблица пуста или не получена")
            return

        print("Подготовка данных для графика...")
        # Подготовка данных для графика
        voltages = [row[1] for row in table]  # Напряжения из текущей таблицы
        frequencies = [row[2] for row in table]  # Частоты из текущей таблицы
        orig_voltages = [v for v, _ in original_table]  # Напряжения из исходной таблицы
        orig_frequencies = [f for _, f in original_table]  # Частоты из исходной таблицы

        print("Создание графика...")
        # Создание графика
        plt.figure(figsize=(10, 6))
        # Текущая таблица: точки и линия
        plt.plot(voltages, frequencies, 'b-', label='Текущая таблица (интерполяция)', linewidth=1.5)
        plt.plot(voltages, frequencies, 'bo', label='Текущая таблица (точки)')
        # Исходная таблица: точки
        plt.plot(orig_voltages, orig_frequencies, 'r--', label='Исходная таблица', linewidth=1.5)
        plt.plot(orig_voltages, orig_frequencies, 'ro', alpha=0.5)

        # Настройка графика
        plt.xlabel('Напряжение (В)')
        plt.ylabel('Частота (Гц)')
        plt.title('Зависимость частоты от напряжения')
        plt.grid(True)
        plt.legend()
        plt.tight_layout()

        # Сохранение графика
        try:
            plot_filename = 'interpolation_plot.png'
            plt.savefig(plot_filename)
            print(f"График сохранен как '{plot_filename}'")
            # Пытаемся открыть файл автоматически
            try:
                subprocess.run(['xdg-open', plot_filename], check=True)
                print(f"Открыт файл '{plot_filename}'")
            except subprocess.CalledProcessError:
                print("Не удалось автоматически открыть график. Откройте 'interpolation_plot.png' вручную.")
        except Exception as e:
            print(f"Ошибка при сохранении графика: {e}")

        # Попытка отобразить график
        try:
            # Переключаемся на TkAgg для отображения
            matplotlib.use('TkAgg', force=True)
            plt.show()
            print("График отображен в окне")
        except Exception as e:
            print(f"Ошибка при отображении графика: {e}. Откройте 'interpolation_plot.png' вручную.")
    except Exception as e:
        print(f"Ошибка в plot_table: {e}")

def save_table_to_json():
    """Сохранить таблицу в JSON-файл с запросом имени файла"""
    table = get_table()
    if not table:
        print("Ошибка: Таблица пуста или не получена")
        return

    # Подготовка данных для JSON
    table_with_old = []
    for index, voltage, frequency in table:
        old_frequency = get_original_frequency(voltage)
        table_with_old.append({
            "index": index,
            "voltage": voltage,
            "frequency": frequency,
            "old_frequency": old_frequency
        })

    # Запрос имени файла
    filename = input("Введите имя файла для сохранения (без расширения): ").strip()
    if not filename:
        print("Ошибка: Имя файла не может быть пустым")
        return
    if not filename.endswith(".json"):
        filename += ".json"

    # Сохранение в JSON
    try:
        with open(filename, 'w') as f:
            json.dump(table_with_old, f, indent=4)
        print(f"Таблица успешно сохранена в {filename}")
    except Exception as e:
        print(f"Ошибка при сохранении файла: {e}")

def update_point(index, voltage, frequency):
    """Обновить точку в таблице"""
    try:
        # Форматируем команду с точным контролем пробелов
        command = f"set {index} {voltage:.3f} {frequency:.2f}\n"
        print(f"Отправка команды: '{command.strip()}'")  # Отладочный вывод
        ser.reset_input_buffer()  # Очищаем буфер перед отправкой
        ser.write(command.encode('utf-8'))
        time.sleep(0.2)  # Увеличиваем задержку для надежной обработки
        # Читаем все строки ответа
        response = ""
        max_attempts = 50
        attempts = 0
        while attempts < max_attempts:
            if ser.in_waiting > 0:
                line = ser.readline().decode('utf-8', errors='ignore').strip()
                response += line + "\n"
                if line.startswith("OK") or line.startswith("Ошибка"):
                    break
            time.sleep(0.01)
            attempts += 1
        if response:
            print(response.strip())
        else:
            print("Ошибка: Ответ от Arduino не получен")
    except Exception as e:
        print(f"Ошибка в update_point: {e}")

def display_voltage_realtime():
    """Отображение напряжения A0 в реальном времени"""
    print("\n=== Напряжение A0 в реальном времени ===")
    print("Нажмите Enter для выхода")
    try:
        while True:
            ser.reset_input_buffer()  # Очищаем буфер
            ser.write(b"get_voltage\n")  # Запрашиваем напряжение
            time.sleep(0.1)  # Ждём ответа
            # Читаем все доступные строки
            max_attempts = 50
            attempts = 0
            voltage = None
            while attempts < max_attempts:
                if ser.in_waiting > 0:
                    line = ser.readline().decode('utf-8', errors='ignore').strip()
                    # Пропускаем отладочные сообщения без вывода
                    if not line.startswith("DEBUG"):
                        try:
                            voltage = float(line)
                            break
                        except ValueError:
                            print(f"Ошибка: Неверный формат данных '{line}'")
                    time.sleep(0.01)
                    attempts += 1
            if voltage is not None:
                # Очищаем текущую строку и выводим новое значение
                sys.stdout.write(f"\rНапряжение: {voltage:.3f} В          ")
                sys.stdout.flush()
            else:
                print("\nОшибка: Не удалось получить корректное напряжение")
                break
            time.sleep(0.5)  # Обновление каждые 0.5 секунды
            # Проверка ввода Enter
            if select.select([sys.stdin], [], [], 0.1)[0]:
                sys.stdin.readline()
                print("\nВыход из режима реального времени")
                break
    except KeyboardInterrupt:
        print("\nВыход из режима реального времени")
    except Exception as e:
        print(f"\nОшибка: {e}")

def main_menu():
    """Основное меню"""
    while True:
        print("\n=== Управление таблицей интерполяции ===")
        print("1. Показать таблицу")
        print("2. Изменить частоту точки")
        print("3. Сохранить таблицу в JSON")
        print("4. Показать напряжение A0 в реальном времени")
        print("5. Показать график")
        print("6. Выход")
        choice = input("Выберите опцию (1-6): ")
        
        if choice == "1":
            display_table()
        elif choice == "2":
            try:
                index = int(input("Введите индекс (0-29): "))
                if index < 0 or index > 29:
                    print("Ошибка: Индекс должен быть от 0 до 29")
                    continue
                # Получаем текущую таблицу для извлечения напряжения
                table = get_table()
                if not table:
                    print("Ошибка: Не удалось получить таблицу")
                    continue
                # Находим напряжение для указанного индекса
                voltage = None
                for t_index, t_voltage, _ in table:
                    if t_index == index:
                        voltage = t_voltage
                        break
                if voltage is None:
                    print(f"Ошибка: Индекс {index} не найден в таблице")
                    continue
                frequency = float(input("Введите новую частоту (Hz): "))
                update_point(index, voltage, frequency)
            except ValueError:
                print("Ошибка: Введите корректные числовые значения")
        elif choice == "3":
            save_table_to_json()
        elif choice == "4":
            display_voltage_realtime()
        elif choice == "5":
            plot_table()
        elif choice == "6":
            print("Выход из программы")
            break
        else:
            print("Ошибка: Неверный выбор")

if __name__ == "__main__":
    try:
        main_menu()
    except KeyboardInterrupt:
        print("\nПрограмма завершена пользователем")
    finally:
        ser.close()
        plt.close('all')  # Закрываем все окна matplotlib при выходе
