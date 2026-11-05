FROM postgres:13

# docker-compose.yml ne fournit pas de mot de passe pour ce service
ENV POSTGRES_HOST_AUTH_METHOD=trust

# DuckDB convertit les Parquet en CSV. Il est installe dans un environnement
# virtuel, car l'image Debian refuse pip au niveau systeme (PEP 668).
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates python3 python3-venv wget && \
    rm -rf /var/lib/apt/lists/* && \
    python3 -m venv /opt/duckdb && \
    /opt/duckdb/bin/pip install --no-cache-dir duckdb==2.0.0

# Docker l'execute automatiquement au premier demarrage du conteneur
COPY postgres-init.sh /docker-entrypoint-initdb.d/postgres-init.sh
RUN chmod +x /docker-entrypoint-initdb.d/postgres-init.sh
