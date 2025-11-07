#!/bin/bash

# Configuration - ADAPTEZ CES VALEURS
BACKUP_DIR=""
CONTAINER_NAME=""  
DB_NAME=""               
DB_USER=""
DB_PASSWORD=""

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE} Script de restauration MariaDB${NC}"
echo "===================================="

# 1. Vérifier que le container existe et fonctionne
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED} Le container '$CONTAINER_NAME' n'est pas en cours d'exécution${NC}"
    echo -e "${YELLOW} Vérifiez le nom du container avec: docker ps${NC}"
    exit 1
fi

# 2. Vérifier le dossier de sauvegarde
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED} Dossier de sauvegarde '$BACKUP_DIR' introuvable${NC}"
    exit 1
fi

# 3. Lister les sauvegardes disponibles
echo -e "\n${BLUE} Sauvegardes disponibles :${NC}"
find $BACKUP_DIR -name "*.sql" -o -name "*.sql.gz" 2>/dev/null | sort -r | while read file; do
    size=$(ls -lh "$file" | awk '{print $5}')
    date=$(ls -l "$file" | awk '{print $6, $7, $8}')
    echo -e "  ${CYAN}$(basename "$file")${NC} - ${YELLOW}$size${NC} - $date"
done

# Vérifier qu'il y a des fichiers
if [ -z "$(find $BACKUP_DIR -name "*.sql" -o -name "*.sql.gz" 2>/dev/null)" ]; then
    echo -e "${RED} Aucun fichier de sauvegarde trouvé dans $BACKUP_DIR${NC}"
    exit 1
fi

# 4. Menu de sélection du fichier
echo -e "\n${YELLOW} Sélectionnez le fichier à restaurer :${NC}"
BACKUP_FILES=()
while IFS= read -r -d '' file; do
    BACKUP_FILES+=("$file")
done < <(find $BACKUP_DIR -name "*.sql" -o -name "*.sql.gz" -print0 2>/dev/null | sort -zr)

BACKUP_FILES+=("Annuler")

select BACKUP_FILE in "${BACKUP_FILES[@]}"; do
    case $BACKUP_FILE in
        "Annuler")
            echo -e "${RED}❌ Restauration annulée${NC}"
            exit 0
            ;;
        *.sql|*.sql.gz)
            if [ -f "$BACKUP_FILE" ]; then
                echo -e "${GREEN} Fichier sélectionné : $(basename $BACKUP_FILE)${NC}"
                break
            else
                echo -e "${RED} Fichier invalide${NC}"
            fi
            ;;
        *)
            echo -e "${RED} Sélection invalide${NC}"
            ;;
    esac
done

# 5. Confirmation de sécurité
echo -e "\n${RED}  ATTENTION DANGER ${NC}"
echo -e "${RED}Cette opération va ÉCRASER COMPLÈTEMENT la base de données actuelle !${NC}"
echo -e "${YELLOW}Base de données : $DB_NAME${NC}"
echo -e "${YELLOW}Container : $CONTAINER_NAME${NC}"
echo -e "${YELLOW}Fichier de restauration : $(basename $BACKUP_FILE)${NC}"
echo ""
echo -e "${RED}Toutes les données actuelles seront PERDUES !${NC}"
echo ""
echo -n "Tapez 'CONFIRMER' en majuscules pour continuer : "
read CONFIRM

if [ "$CONFIRM" != "CONFIRMER" ]; then
    echo -e "${RED} Restauration annulée${NC}"
    exit 0
fi

# 6. Option de sauvegarde de sécurité
echo -e "\n${YELLOW} Voulez-vous faire une sauvegarde de sécurité avant la restauration ? (Y/n) :${NC}"
read -r BACKUP_CONFIRM

if [[ ! $BACKUP_CONFIRM =~ ^[Nn]$ ]]; then
    echo -e "${BLUE} Création d'une sauvegarde de sécurité...${NC}"
    SAFETY_BACKUP="$BACKUP_DIR/safety_backup_$(date +%Y%m%d_%H%M%S).sql"
    
    # Détecter l'outil de dump
    DUMP_TOOL=""
    if docker exec $CONTAINER_NAME which mariadb-dump >/dev/null 2>&1; then
        DUMP_TOOL="mariadb-dump"
    elif docker exec $CONTAINER_NAME test -f /usr/bin/mariadb-dump >/dev/null 2>&1; then
        DUMP_TOOL="/usr/bin/mariadb-dump"
    else
        echo -e "${YELLOW}  mariadb-dump non trouvé, sauvegarde ignorée${NC}"
    fi
    
    if [ -n "$DUMP_TOOL" ]; then
        docker exec $CONTAINER_NAME $DUMP_TOOL -u$DB_USER -p$DB_PASSWORD $DB_NAME > "$SAFETY_BACKUP"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Sauvegarde de sécurité créée : $(basename $SAFETY_BACKUP)${NC}"
        else
            echo -e "${RED}❌ Échec de la sauvegarde de sécurité${NC}"
            exit 1
        fi
    fi
fi

# 7. Détecter l'outil de restauration
echo -e "\n${BLUE}🔧 Détection de l'outil de restauration...${NC}"
MYSQL_TOOL=""
if docker exec $CONTAINER_NAME which mariadb >/dev/null 2>&1; then
    MYSQL_TOOL="mariadb"
elif docker exec $CONTAINER_NAME test -f /usr/bin/mariadb >/dev/null 2>&1; then
    MYSQL_TOOL="/usr/bin/mariadb"
elif docker exec $CONTAINER_NAME which mysql >/dev/null 2>&1; then
    MYSQL_TOOL="mysql"
elif docker exec $CONTAINER_NAME test -f /usr/bin/mysql >/dev/null 2>&1; then
    MYSQL_TOOL="/usr/bin/mysql"
else
    echo -e "${RED} Client MariaDB/MySQL non trouvé dans le container${NC}"
    exit 1
fi

echo -e "${GREEN} Utilisation de : $MYSQL_TOOL${NC}"

# 8. Restauration
echo -e "\n${BLUE} Restauration en cours...${NC}"
echo -e "${YELLOW} Cela peut prendre du temps selon la taille de la base...${NC}"

# Adapter selon le format du fichier
if [[ "$BACKUP_FILE" == *.gz ]]; then
    echo -e "${CYAN} Décompression et restauration...${NC}"
    gunzip -c "$BACKUP_FILE" | docker exec -i $CONTAINER_NAME $MYSQL_TOOL -h localhost -u$DB_USER -p$DB_PASSWORD $DB_NAME
else
    echo -e "${CYAN} Restauration directe...${NC}"
    cat "$BACKUP_FILE" | docker exec -i $CONTAINER_NAME $MYSQL_TOOL -h localhost -u$DB_USER -p$DB_PASSWORD $DB_NAME
fi

# 9. Vérification du résultat
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN} RESTAURATION RÉUSSIE !${NC}"
    echo -e "${GREEN} La base de données '$DB_NAME' a été restaurée avec succès${NC}"
    echo -e "${BLUE} Fichier utilisé : $(basename $BACKUP_FILE)${NC}"
    
    # Test de connexion pour vérifier
    echo -e "\n${BLUE}🔍 Vérification de la base restaurée...${NC}"
    TABLES_COUNT=$(docker exec $CONTAINER_NAME $MYSQL_TOOL -h localhost -u$DB_USER -p$DB_PASSWORD $DB_NAME -e "SHOW TABLES;" 2>/dev/null | wc -l)
    if [ $TABLES_COUNT -gt 1 ]; then
        echo -e "${GREEN} Base de données opérationnelle ($((TABLES_COUNT-1)) tables trouvées)${NC}"
    else
        echo -e "${YELLOW}  Base de données restaurée mais semble vide${NC}"
    fi
else
    echo -e "\n${RED} ERREUR LORS DE LA RESTAURATION${NC}"
    echo -e "${RED}La restauration a échoué !${NC}"
    if [ -f "$SAFETY_BACKUP" ]; then
        echo -e "${YELLOW}💡 Vous pouvez restaurer la sauvegarde de sécurité : $(basename $SAFETY_BACKUP)${NC}"
    fi
    exit 1
fi

echo -e "\n${CYAN} Restauration terminée${NC}"