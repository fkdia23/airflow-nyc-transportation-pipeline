FROM postgres:13-alpine

ENV POSTGRES_HOST_AUTH_METHOD=trust

# Copier le script d'initialisation
# Docker l'exécutera automatiquement au premier démarrage du container
COPY postgres-init.sh /docker-entrypoint-initdb.d/postgres-init.sh

# Assurer que le script est exécutable
RUN chmod +x /docker-entrypoint-initdb.d/postgres-init.sh && \
    apk add --no-cache wget unzip