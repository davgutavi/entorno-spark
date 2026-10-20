# Entorno de prácticas de Spark

**Ingeniería de Datos: Big Data** · Máster en Ingeniería del Software · Bloque de Spark (sesiones 5 a 8)

Un clúster Spark 4.2 Standalone en tu ordenador, con Docker Compose:

| Servicio | Qué hace | Dirección en tu navegador |
|---|---|---|
| `jupyter` | JupyterLab: tus notebooks y el *driver* de Spark | <http://localhost:8888> |
| `spark-master` | Gestor del clúster (Standalone) | <http://localhost:8080> |
| `spark-worker-1`, `spark-worker-2` | Ejecutan los *executors* (2 núcleos y 2 GB cada uno) | <http://localhost:8091>, <http://localhost:8092> |
| — | Spark UI de cada aplicación | <http://localhost:4040> (la siguiente, 4041, 4042…) |
| `kafka` (opcional) | Kafka para *Structured Streaming* (sesión 8) | `kafka:9092` desde los notebooks |

Dentro de los contenedores, el master es `spark://spark-master:7077` y la carpeta `./datos` de tu ordenador es `/datos`: la misma ruta en el driver y en los workers.

Funciona igual en Windows, macOS (Intel y Apple Silicon, de forma nativa) y Linux.

---

## 1. Requisitos

- **Docker Desktop** (en Linux vale también Docker Engine con el plugin `docker compose`).
- **Memoria para Docker: 8 GB como mínimo.** En Docker Desktop: *Settings → Resources → Memory* (en Windows con WSL 2, ver el apartado 8). El entorno usa unos 3 GB en marcha, pero Spark necesita margen cuando hay dos aplicaciones a la vez.
- Unos 3 GB de disco libres (imagen de 1,3 GB y datos de 370 MB).
- Python 3 en tu ordenador, solo para preparar los datos (paso 2.2).

## 2. Primera puesta en marcha

Hazlo **antes de la primera clase**, con buena conexión: descarga unos 600 MB y tarda unos minutos. Después, todo funciona sin internet.

### 2.1. Descargar esta carpeta

Clona el repositorio o descárgalo como zip y descomprímelo. Todos los comandos se escriben **en un terminal abierto en esta carpeta** (la que contiene `docker-compose.yml`): PowerShell en Windows, Terminal en macOS o Linux.

### 2.2. Preparar los datos

Descarga de Enseñanza Virtual el zip con los datos del curso y ejecuta, indicando dónde lo has guardado:

```bash
# Windows (PowerShell)
python preparar_datos.py $HOME\Downloads\datos_spark.zip

# macOS o Linux
python3 preparar_datos.py ~/Downloads/datos_spark.zip
```

El script coloca `endesaAgregada` (364 MB) y `quixote.txt` en `./datos`, crea `datos/apps` y `datos/salida` y comprueba que los ficheros están completos:

```
  datos/endesaAgregada: correcto
  datos/quixote.txt: correcto
```

### 2.3. Descargar la imagen y arrancar

```bash
docker compose pull         # solo la primera vez: descarga la imagen
docker compose up -d
```

Comprueba que los cuatro servicios están `healthy` (tarda unos 20 segundos):

```bash
docker compose ps
```

Abre <http://localhost:8080>: deben aparecer **2 workers ALIVE** con 2 núcleos y 2 GB cada uno. Después abre JupyterLab en <http://localhost:8888>.

> La imagen está publicada en `ghcr.io/davgutavi/spark-bd` para Intel/AMD (`amd64`) y para ARM (`arm64`, incluido Apple Silicon), y Docker descarga la de tu procesador. Si no puedes descargarla, constrúyela en tu ordenador con `docker compose build` (de 5 a 10 minutos).

## 3. Uso diario

| Para… | Comando |
|---|---|
| Arrancar | `docker compose up -d` |
| Ver el estado | `docker compose ps` |
| Ver los mensajes de un servicio | `docker compose logs spark-master` (o `jupyter`, `spark-worker-1`…) |
| Parar (sin perder nada) | `docker compose down` |
| Parar también Kafka | `docker compose --profile streaming down` |
| Actualizar la imagen (si se anuncia una nueva) | `docker compose pull` |
| Borrarlo todo, incluida la imagen | `docker compose --profile streaming down --rmi all` |

**Tus notebooks y tus datos están en tu ordenador**, en `./notebooks` y `./datos`: no se pierden al parar ni al borrar los contenedores. En JupyterLab, la carpeta `./notebooks` es la carpeta de trabajo.

## 4. Spark desde un notebook

```python
import os
from pyspark.sql import SparkSession

spark = (SparkSession.builder
         .appName("mi-aplicacion")
         .master(os.environ["SPARK_MASTER_URL"])     # spark://spark-master:7077
         .getOrCreate())

df = spark.read.text(f"{os.environ['DATOS']}/quixote.txt")   # DATOS = /datos
```

- La Spark UI de la aplicación está en <http://localhost:4040>; `spark.sparkContext.uiWebUrl` te da la dirección exacta. Si ya hay otra aplicación abierta, será 4041, 4042… (el entorno publica de la 4040 a la 4045).
- Cada aplicación recibe **2 de los 4 núcleos** del clúster, salvo que pida otra cantidad con `spark.cores.max` (o `--total-executor-cores` en `spark-submit`). Así caben dos aplicaciones a la vez: por ejemplo, un notebook y un `spark-submit`.
- **Al terminar, cierra la sesión** con `spark.stop()` o apaga el kernel (*Kernel → Shut Down Kernel*). En Standalone, una aplicación abierta retiene sus núcleos aunque no esté calculando.

## 5. `spark-submit` desde un terminal de JupyterLab

En JupyterLab: *File → New → Terminal*. Los ficheros de la aplicación van en `/datos/apps` (`./datos/apps` en tu ordenador):

```bash
# En local, sin usar el clúster
spark-submit --master "local[2]" \
  --py-files /datos/apps/endesa.py \
  /datos/apps/consumo_por_mercado.py /datos/endesaAgregada /datos/salida/consumo_mercado_local

# Contra el clúster
spark-submit --master spark://spark-master:7077 \
  --executor-memory 1g --total-executor-cores 2 \
  --py-files /datos/apps/endesa.py \
  /datos/apps/consumo_por_mercado.py /datos/endesaAgregada /datos/salida/consumo_mercado
```

Mientras corre, la aplicación aparece en <http://localhost:8080> (*Running Applications*) y su Spark UI en <http://localhost:4040> (o 4041). El resultado queda en `./datos/salida` de tu ordenador.

## 6. Kafka (perfil `streaming`)

Kafka solo arranca si lo pides:

```bash
docker compose --profile streaming up -d
```

- Desde los notebooks y desde `spark-submit`, el servidor es **`kafka:9092`**. El conector de Spark para Kafka ya está en la imagen, así que **no hace falta `--packages`** ni conexión a internet:

  ```python
  df = (spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", "kafka:9092")
        .option("subscribe", "mi-topic")
        .load())
  ```

- Las herramientas de Kafka se usan dentro de su contenedor:

  ```bash
  docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --create --topic mi-topic
  docker compose exec kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:9092 --topic mi-topic
  ```

- Un programa que corra en tu ordenador, fuera de Docker, se conecta a `localhost:29092`.
- Para pararlo todo: `docker compose --profile streaming down`.

## 7. Problemas típicos

### `port is already allocated` (puerto ocupado)

```
Error response from daemon: ... Bind for 0.0.0.0:8080 failed: port is already allocated
```

Hay otro entorno usando el puerto. Normalmente es uno de los del bloque de Hadoop (sesiones 2 y 3, Airflow, Kafka Connect) o el entorno antiguo de Spark con Zeppelin. **Páralo antes**, en un terminal abierto en su carpeta:

```bash
docker compose down
```

Si no sabes cuál es, `docker ps` muestra los contenedores en marcha y sus puertos; `docker stop <nombre>` para uno concreto. Después, en esta carpeta:

```bash
docker compose down        # quita los contenedores que se quedaron a medio arrancar
docker compose up -d
```

Este entorno usa 8080, 8091, 8092, 8888, 4040-4045 y, con `streaming`, 29092.

### Una aplicación se queda en `WAITING`

En <http://localhost:8080>, la aplicación aparece en *WAITING* con 0 núcleos: otras aplicaciones tienen los 4 núcleos del clúster. Suele ser algún notebook que sigue abierto. Ciérralo con `spark.stop()` o apaga su kernel: en JupyterLab, en el panel *Running Terminals and Kernels* (icono del cuadrado con un círculo), *Shut Down All*. La aplicación en espera arranca en cuanto quedan núcleos libres.

### Poca memoria en Docker Desktop

Síntomas: un worker o `jupyter` se reinicia o desaparece (`docker compose ps`), el kernel muere o aparece `OutOfMemoryError` o `exit code 137`. Sube la memoria de Docker a 8 GB como mínimo (*Settings → Resources → Memory*), cierra lo que no uses y vuelve a arrancar. Puedes ver el consumo real con `docker stats`.

### Apple Silicon (M1, M2, M3…)

La imagen existe para `arm64` y corre de forma nativa, sin emulación. Si te va muy lento, comprueba que no estás usando una imagen para Intel: `docker compose exec jupyter uname -m` debe decir `aarch64`. Si dice `x86_64`, vuelve a descargarla con `docker compose pull`.

### Linux: `Permission denied` al guardar un notebook o `Mkdirs failed` en Spark

Los contenedores usan el UID 1000, que es el del primer usuario en casi todas las distribuciones. Si `id -u` te da otro número, los contenedores no pueden escribir en `./notebooks` ni en `./datos`. Construye la imagen con tu UID en lugar de descargarla (de 5 a 10 minutos):

```bash
docker compose build --build-arg UID=$(id -u) --build-arg GID=$(id -g)
docker compose up -d
```

A partir de ahí, no uses `docker compose pull`, porque volvería a dejar la imagen con el UID 1000. Para actualizarla, repite el `build`.

### Windows

- Docker Desktop debe usar el motor de WSL 2 (la opción por defecto).
- La memoria se configura en el fichero `%UserProfile%\.wslconfig`: en la sección `[wsl2]`, escribe `memory=8GB` y después ejecuta `wsl --shutdown` en PowerShell para que se aplique.
- Si al ejecutar `python` se abre la Microsoft Store, prueba con `py preparar_datos.py ...`.

### Empezar de cero

Si algo se ha quedado en un estado raro, esto no borra ni tus notebooks ni tus datos:

```bash
docker compose --profile streaming down
docker compose pull
docker compose up -d
```

Si construiste la imagen en tu ordenador (Linux con otro UID), cambia `pull` por `build --no-cache` y añade los `--build-arg` del apartado anterior.

## Licencia

[MIT](LICENSE) © 2026 David Gutiérrez Avilés
