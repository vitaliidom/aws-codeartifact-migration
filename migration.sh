#!/bin/bash

# Конфігурація вихідного репозиторію
SOURCE_DOMAIN=""
SOURCE_REPO=""
SOURCE_REGION="us-east-1"
# AWS profile для вихідного репозиторію
SOURCE_PROFILE=""
SOURCE_ACCOUNT_ID=""

# Конфігурація цільового репозиторію
TARGET_DOMAIN=""
TARGET_REPO=""
TARGET_REGION="us-east-1"
# AWS profile для цільового репозиторію
TARGET_PROFILE=""
TARGET_ACCOUNT_ID=""

# Робоча директорія
WORK_DIR="./codeartifact-migration"
PACKAGES_DIR="$WORK_DIR/packages"
LOG_FILE="$WORK_DIR/migration.log"

# Кольори для виводу
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Створення робочої директорії
mkdir -p "$WORK_DIR"
mkdir -p "$PACKAGES_DIR"
touch "$LOG_FILE"
echo "$(date): Початок міграції" > "$LOG_FILE"

echo -e "${GREEN}=== Міграція CodeArtifact npm пакетів ===${NC}"

# Функція логування
log() {
    echo "$(date): $1" >> "$LOG_FILE"
    echo -e "$1"
}

# 1. Отримання списку пакетів з вихідного репозиторію
log "${YELLOW}Крок 1: Отримання списку пакетів...${NC}"
aws codeartifact list-packages \
    --domain "$SOURCE_DOMAIN" \
    --repository "$SOURCE_REPO" \
    --region "$SOURCE_REGION" \
    --profile "$SOURCE_PROFILE" \
    --format npm \
    --output json > "$WORK_DIR/packages-list.json"

if [ $? -ne 0 ]; then
    log "${RED}Помилка при отриманні списку пакетів${NC}"
    exit 1
fi

# Парсинг списку пакетів
PACKAGE_COUNT=$(jq -r '.packages | length' "$WORK_DIR/packages-list.json")
log "${GREEN}Знайдено $PACKAGE_COUNT пакетів${NC}"

# 2. Отримання токенів авторизації
log "${YELLOW}Крок 2: Отримання токенів авторизації...${NC}"

SOURCE_TOKEN=$(aws codeartifact get-authorization-token \
    --domain "$SOURCE_DOMAIN" \
    --region "$SOURCE_REGION" \
    --profile "$SOURCE_PROFILE" \
    --query authorizationToken \
    --output text)

TARGET_TOKEN=$(aws codeartifact get-authorization-token \
    --domain "$TARGET_DOMAIN" \
    --region "$TARGET_REGION" \
    --profile "$TARGET_PROFILE" \
    --query authorizationToken \
    --output text)

SOURCE_REGISTRY="https://$SOURCE_DOMAIN-$SOURCE_ACCOUNT_ID.d.codeartifact.$SOURCE_REGION.amazonaws.com/npm/$SOURCE_REPO/"
TARGET_REGISTRY="https://$TARGET_DOMAIN-$TARGET_ACCOUNT_ID.d.codeartifact.$TARGET_REGION.amazonaws.com/npm/$TARGET_REPO/"

# 3. Обробка кожного пакету
log "${YELLOW}Крок 3: Копіювання пакетів...${NC}"

SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

for i in $(seq 0 $((PACKAGE_COUNT - 1))); do
    PACKAGE=$(jq -r ".packages[$i].package" "$WORK_DIR/packages-list.json")

    log "${YELLOW}Обробка пакету: $PACKAGE${NC}"

    # Отримання всіх версій пакету
    aws codeartifact list-package-versions \
        --domain "$SOURCE_DOMAIN" \
        --repository "$SOURCE_REPO" \
        --region "$SOURCE_REGION" \
        --profile "$SOURCE_PROFILE" \
        --format npm \
        --package "$PACKAGE" \
        --output json > "$WORK_DIR/versions-$i.json"

    VERSION_COUNT=$(jq -r '.versions | length' "$WORK_DIR/versions-$i.json")
    log "  Знайдено $VERSION_COUNT версій"

    # Обробка кожної версії
    for j in $(seq 0 $((VERSION_COUNT - 1))); do
        VERSION=$(jq -r ".versions[$j].version" "$WORK_DIR/versions-$i.json")
        PACKAGE_VERSION="$PACKAGE@$VERSION"

        # Перевірка чи вже існує пакет в цільовому репозиторії
        if aws codeartifact describe-package-version \
            --domain "$TARGET_DOMAIN" \
            --repository "$TARGET_REPO" \
            --region "$TARGET_REGION" \
            --profile "$TARGET_PROFILE" \
            --format npm \
            --package "$PACKAGE" \
            --package-version "$VERSION" \
            --output json > /dev/null 2>&1; then
            log "  ${YELLOW}⊘ $PACKAGE_VERSION вже існує, пропускаємо${NC}"
            ((SKIP_COUNT++))
            continue
        fi

        log "  Копіювання $PACKAGE_VERSION..."

        # Створення тимчасової директорії для пакету
        TEMP_DIR="$PACKAGES_DIR/temp-$-$i-$j"
        mkdir -p "$TEMP_DIR"

        # Створення .npmrc для завантаження з вихідного репозиторію
        cat > "$TEMP_DIR/.npmrc" << EOF
registry=$SOURCE_REGISTRY
//$SOURCE_DOMAIN-$SOURCE_ACCOUNT_ID.d.codeartifact.$SOURCE_REGION.amazonaws.com/npm/$SOURCE_REPO/:_authToken=$SOURCE_TOKEN
EOF

        # Завантаження пакету
        if (cd "$TEMP_DIR" && npm pack "$PACKAGE_VERSION") >> "$LOG_FILE" 2>&1; then
            TARBALL=$(ls "$TEMP_DIR"/*.tgz 2>/dev/null | head -n 1)

            if [ -z "$TARBALL" ]; then
                log "  ${RED}✗ Не знайдено tarball для $PACKAGE_VERSION${NC}"
                ((FAIL_COUNT++))
                rm -rf "$TEMP_DIR"
                continue
            fi

            # Створення .npmrc для публікації в цільовий репозиторій
            cat > "$TEMP_DIR/.npmrc" << EOF
registry=$TARGET_REGISTRY
//$TARGET_DOMAIN-$TARGET_ACCOUNT_ID.d.codeartifact.$TARGET_REGION.amazonaws.com/npm/$TARGET_REPO/:_authToken=$TARGET_TOKEN
EOF

            # Публікація в цільовий репозиторій
            TARBALL_NAME=$(basename "$TARBALL")
            if (cd "$TEMP_DIR" && npm publish "$TARBALL_NAME" --registry "$TARGET_REGISTRY") >> "$LOG_FILE" 2>&1; then
                log "  ${GREEN}✓ Успішно скопійовано $PACKAGE_VERSION${NC}"
                ((SUCCESS_COUNT++))
            else
                log "  ${RED}✗ Помилка публікації $PACKAGE_VERSION${NC}"
                ((FAIL_COUNT++))
            fi
        else
            log "  ${RED}✗ Помилка завантаження $PACKAGE_VERSION${NC}"
            ((FAIL_COUNT++))
        fi

        # Очищення
        rm -rf "$TEMP_DIR"
    done
done

# 4. Звіт
log "${GREEN}=== Міграція завершена ===${NC}"
log "Успішно скопійовано: $SUCCESS_COUNT версій пакетів"
log "Пропущено (вже існують): $SKIP_COUNT версій пакетів"
log "Помилок: $FAIL_COUNT"
log "Детальний лог: $LOG_FILE"

echo ""
echo -e "${GREEN}Міграція завершена!${NC}"
echo -e "Успішно: ${GREEN}$SUCCESS_COUNT${NC}"
echo -e "Пропущено: ${YELLOW}$SKIP_COUNT${NC}"
echo -e "Помилок: ${RED}$FAIL_COUNT${NC}"
echo -e "Лог файл: $LOG_FILE"
