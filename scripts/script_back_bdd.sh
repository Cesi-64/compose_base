
#!/bin/bash

# Configuration
CONTAINER_NAME=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
BACKUP_DIR=""
DATE=$(date +%Y%m%d_%H%M%S)

# Créer le dossier de sauvegarde s'il n'existe pas
mkdir -p $BACKUP_DIR

# Détecter quel outil de dump est disponible et où
DUMP_TOOL=""

# Tester différentes possibilités
if docker exec $CONTAINER_NAME which mysqldump >/dev/null 2>&1; then
    DUMP_TOOL="mysqldump"
elif docker exec $CONTAINER_NAME which mariadb-dump >/dev/null 2>&1; then
    DUMP_TOOL="mariadb-dump"
elif docker exec $CONTAINER_NAME test -f /usr/bin/mariadb-dump >/dev/null 2>&1; then
    DUMP_TOOL="/usr/bin/mariadb-dump"
elif docker exec $CONTAINER_NAME test -f /usr/local/bin/mariadb-dump >/dev/null 2>&1; then
    DUMP_TOOL="/usr/local/bin/mariadb-dump"
elif docker exec $CONTAINER_NAME test -f /usr/bin/mysqldump >/dev/null 2>&1; then
    DUMP_TOOL="/usr/bin/mysqldump"
else
    echo "Aucun outil de dump trouvé dans le conteneur"
    exit 1
fi

echo "Utilisation de : $DUMP_TOOL"

# Sauvegarde
docker exec $CONTAINER_NAME $DUMP_TOOL -u$DB_USER -p$DB_PASSWORD $DB_NAME > $BACKUP_DIR/backup_${DB_NAME}_${DATE}.sql

# Vérifier si la sauvegarde a réussi
if [ $? -eq 0 ] && [ -s $BACKUP_DIR/backup_${DB_NAME}_${DATE}.sql ]; then
    # Compression
    gzip $BACKUP_DIR/backup_${DB_NAME}_${DATE}.sql
    
    # Nettoyage 7 jours glissants
    find $BACKUP_DIR -name "backup_${DB_NAME}_*.sql.gz" -type f -mtime +7 -delete
    
    echo "Sauvegarde terminée : backup_${DB_NAME}_${DATE}.sql.gz"
else
    echo "Erreur lors de la sauvegarde"
    rm -f $BACKUP_DIR/backup_${DB_NAME}_${DATE}.sql
    exit 1
fi
