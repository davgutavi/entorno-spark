# syntax=docker/dockerfile:1.7
# ============================================================
#  Imagen única del bloque de Spark: la usan jupyter (driver),
#  spark-master y los workers (executors). Así driver y
#  executors tienen la misma versión de Python y de PySpark.
#
#  Multiarquitectura (linux/amd64 y linux/arm64): las dos
#  imágenes base lo son, y no se fija `platform`.
# ============================================================

ARG PYTHON_IMAGE=python:3.12.15-slim-trixie
ARG JAVA_IMAGE=eclipse-temurin:21.0.12_8-jre-noble

# Java 21 (LTS) desde la imagen oficial de Temurin
FROM ${JAVA_IMAGE} AS java

FROM ${PYTHON_IMAGE}

ENV JAVA_HOME=/opt/java/openjdk
COPY --from=java /opt/java/openjdk ${JAVA_HOME}

# procps: `ps`, que usan los scripts de Spark
RUN apt-get update \
 && apt-get install -y --no-install-recommends procps \
 && rm -rf /var/lib/apt/lists/*

# PySpark trae los JARs de Spark y bin/spark-class, spark-submit…
COPY requirements.txt /tmp/requirements.txt
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt \
 && rm /tmp/requirements.txt

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH=/opt/venv/bin:${JAVA_HOME}/bin:${PATH} \
    SPARK_HOME=/opt/venv/lib/python3.12/site-packages/pyspark \
    SPARK_CONF_DIR=/opt/spark/conf \
    PYSPARK_PYTHON=python3

# Los terminales de JupyterLab abren bash como login shell y /etc/profile
# reescribe el PATH: sin esto no encontrarían spark-submit ni el Python del venv
RUN echo 'export PATH=/opt/venv/bin:${JAVA_HOME}/bin:${PATH}' > /etc/profile.d/spark.sh

# Conector de Kafka para Spark 4.2 / Scala 2.13 y las dependencias que
# PySpark no trae ya en $SPARK_HOME/jars. Se descargan aquí para que en
# clase no haga falta `--packages` ni conexión a internet.
ARG MAVEN=https://repo1.maven.org/maven2
ADD --chmod=644 --checksum=sha256:64539c45e5d39f7ddb747312c239f38f5208d08c1a0ddf7d70beb2fbd9373705 \
    ${MAVEN}/org/apache/spark/spark-sql-kafka-0-10_2.13/4.2.0/spark-sql-kafka-0-10_2.13-4.2.0.jar ${SPARK_HOME}/jars/
ADD --chmod=644 --checksum=sha256:641c7947afc8aa1189e433b7c2d305293993c8691bc1c2062d6d4f513b12518c \
    ${MAVEN}/org/apache/spark/spark-token-provider-kafka-0-10_2.13/4.2.0/spark-token-provider-kafka-0-10_2.13-4.2.0.jar ${SPARK_HOME}/jars/
ADD --chmod=644 --checksum=sha256:014b4ef36884478a932641818b080c36a8f8e2e92dc771e800c9d2694f4f83d8 \
    ${MAVEN}/org/apache/kafka/kafka-clients/3.9.2/kafka-clients-3.9.2.jar ${SPARK_HOME}/jars/
ADD --chmod=644 --checksum=sha256:f77a5060d6936a9144023584232f9de3f2248f1abfe156e9d31795f18770674f \
    ${MAVEN}/org/apache/commons/commons-pool2/2.13.1/commons-pool2-2.13.1.jar ${SPARK_HOME}/jars/

COPY conf/ ${SPARK_CONF_DIR}/

# Usuario no root con UID 1000: en Linux, lo que se escribe en ./datos
# queda a nombre del usuario del host (normalmente también UID 1000).
# Con otro UID: docker compose build --build-arg UID=$(id -u) --build-arg GID=$(id -g)
ARG UID=1000
ARG GID=1000
RUN groupadd --gid ${GID} alumno \
 && useradd --create-home --uid ${UID} --gid ${GID} --shell /bin/bash alumno \
 && mkdir -p /home/alumno/work /datos \
 && chown alumno:alumno /home/alumno/work /datos

USER alumno
ENV SHELL=/bin/bash
WORKDIR /home/alumno/work
