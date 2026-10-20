"""Prepara la carpeta ./datos del entorno de Spark.

Uso (desde la carpeta del entorno, en Windows, macOS o Linux):

    python preparar_datos.py RUTA_AL_ZIP [OTRAS_RUTAS...]

Acepta el zip de Enseñanza Virtual y también zips o ficheros sueltos:
busca dentro `endesaAgregada` y `quixote.txt` (aunque vengan en
subcarpetas o en un zip dentro del zip), los copia en ./datos y crea
./datos/apps y ./datos/salida. Solo usa la biblioteca estándar de Python.
"""
import io
import shutil
import sys
import zipfile
from pathlib import Path

DATOS = Path(__file__).resolve().parent / "datos"
# Tamaño exacto de cada fichero: si no coincide, el fichero está incompleto o es otra versión
FICHEROS = {"endesaAgregada": 364_063_305, "quixote.txt": 2_390_862}


def correcto(ruta):
    return ruta.is_file() and ruta.stat().st_size == FICHEROS[ruta.name]


def extraer(zf, pendientes):
    """Copia de un zip abierto los ficheros pendientes; entra en los zips que contenga."""
    for info in zf.infolist():
        nombre = Path(info.filename).name
        if info.is_dir() or info.filename.startswith("__MACOSX/") or nombre.startswith("._"):
            continue
        if nombre in pendientes and info.file_size == FICHEROS[nombre]:
            print(f"  extrayendo {nombre} ({info.file_size / 1e6:.1f} MB)…")
            with zf.open(info) as origen, open(DATOS / nombre, "wb") as destino:
                shutil.copyfileobj(origen, destino, 1 << 20)
            pendientes.discard(nombre)
        elif nombre.lower().endswith(".zip"):
            with zf.open(info) as interno:
                extraer(zipfile.ZipFile(io.BytesIO(interno.read())), pendientes)
        if not pendientes:
            return


def main(rutas):
    DATOS.mkdir(exist_ok=True)
    for carpeta in ("apps", "salida"):
        (DATOS / carpeta).mkdir(exist_ok=True)

    pendientes = {n for n in FICHEROS if not correcto(DATOS / n)}
    for ruta in map(Path, rutas):
        if not pendientes:
            break
        if not ruta.exists():
            sys.exit(f"No existe: {ruta}")
        print(f"Leyendo {ruta}")
        if zipfile.is_zipfile(ruta):
            with zipfile.ZipFile(ruta) as zf:
                extraer(zf, pendientes)
        elif ruta.name in pendientes and ruta.stat().st_size == FICHEROS[ruta.name]:
            print(f"  copiando {ruta.name}…")
            shutil.copyfile(ruta, DATOS / ruta.name)
            pendientes.discard(ruta.name)

    print()
    for nombre in FICHEROS:
        estado = "correcto" if correcto(DATOS / nombre) else "FALTA o tamaño incorrecto"
        print(f"  datos/{nombre}: {estado}")
    if pendientes:
        sys.exit("\nFaltan ficheros: revisa que has descargado el zip completo de Enseñanza Virtual.")
    print("\nDatos listos en", DATOS)


if __name__ == "__main__":
    if len(sys.argv) < 2 and not all(correcto(DATOS / n) for n in FICHEROS):
        sys.exit(__doc__)
    main(sys.argv[1:])
