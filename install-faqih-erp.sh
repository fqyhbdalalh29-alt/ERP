#!/usr/bin/env bash
set -euo pipefail

# FAQIH ERP one-file installer for a private GitHub repository.
# Installs Odoo 20 source + PostgreSQL with Docker.
PROJECT_DIR="${FAQIH_DIR:-$PWD/faqih-erp}"
ODOO_REPO="https://github.com/odoo/odoo.git"
ODOO_BRANCH="20.0"
OWNER_LOGIN="owner"
OWNER_PASSWORD="FaqihOwner#2026!R7mQ"
MASTER_PASSWORD="FaqihMaster#2026!K9xP"
DB_PASSWORD="FaqihDb#2026!T4vN"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker غير مثبت. ثبّت Docker ثم أعد تشغيل الملف."
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose غير متاح. ثبّت Docker Compose ثم أعد تشغيل الملف."
  exit 1
fi

mkdir -p "$PROJECT_DIR/custom-addons" "$PROJECT_DIR/deploy"
cd "$PROJECT_DIR"

if [ ! -d odoo/.git ]; then
  git clone --depth 1 --branch "$ODOO_BRANCH" "$ODOO_REPO" odoo
fi

cat > .env <<ENV
POSTGRES_DB=postgres
POSTGRES_USER=odoo
POSTGRES_PASSWORD=$DB_PASSWORD
ODOO_PORT=8069
ODOO_MASTER_PASSWORD=$MASTER_PASSWORD
ENV

cat > Dockerfile <<'DOCKERFILE'
FROM python:3.12-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc git curl ca-certificates gettext-base \
    libpq-dev libxml2-dev libxslt1-dev libldap2-dev libsasl2-dev \
    libjpeg62-turbo-dev libffi-dev libssl-dev libopenjp2-7-dev \
    libfreetype6-dev libwebp-dev zlib1g-dev libtiff-dev node-less npm \
    fonts-noto-core && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/odoo
COPY odoo/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && pip install --no-cache-dir -r requirements.txt
COPY odoo/ .
COPY odoo.conf.template /opt/odoo/odoo.conf.template
COPY entrypoint.sh /opt/odoo/entrypoint.sh
RUN useradd --create-home --home-dir /var/lib/odoo --shell /bin/bash odoo && \
    mkdir -p /var/lib/odoo/custom-addons && chown -R odoo:odoo /opt/odoo /var/lib/odoo
USER odoo
EXPOSE 8069
ENTRYPOINT ["/opt/odoo/entrypoint.sh"]
DOCKERFILE

cat > odoo.conf.template <<'CONF'
[options]
admin_passwd = ${ODOO_MASTER_PASSWORD}
db_host = db
db_port = 5432
db_user = ${POSTGRES_USER}
db_password = ${POSTGRES_PASSWORD}
addons_path = /opt/odoo/addons,/var/lib/odoo/custom-addons
data_dir = /var/lib/odoo
proxy_mode = True
list_db = True
CONF

cat > entrypoint.sh <<'ENTRYPOINT'
#!/usr/bin/env bash
set -euo pipefail
: "${ODOO_MASTER_PASSWORD:?ODOO_MASTER_PASSWORD is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
envsubst < /opt/odoo/odoo.conf.template > /tmp/odoo.conf
exec python3 /opt/odoo/odoo-bin --config=/tmp/odoo.conf "$@"
ENTRYPOINT
chmod +x entrypoint.sh

cat > docker-compose.yml <<'COMPOSE'
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
  odoo:
    build: .
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    env_file: .env
    ports:
      - "${ODOO_PORT}:8069"
    volumes:
      - odoo-data:/var/lib/odoo
      - ./custom-addons:/var/lib/odoo/custom-addons
    command: ["--without-demo=all"]
volumes:
  db-data:
  odoo-data:
COMPOSE

cat > OWNER-CREDENTIALS.txt <<CREDS
FAQIH ERP — بيانات الدخول الأولية

Master password: $MASTER_PASSWORD
Owner username:  $OWNER_LOGIN
Owner password:  $OWNER_PASSWORD

عند أول فتح للرابط http://SERVER_IP:8069:
1. أدخل Master password في خانة Master Password.
2. اسم قاعدة البيانات: faqih_erp
3. البريد/اسم الدخول: $OWNER_LOGIN
4. كلمة مرور المالك: $OWNER_PASSWORD
5. اختر اللغة العربية ثم أنشئ قاعدة البيانات.

تحذير: غيّر كلمة المرور بعد أول دخول، ولا ترفع هذا الملف أو ملف .env إلى مستودع عام.
CREDS

cat > custom-addons/README.md <<'ADDONS'
# FAQIH ERP custom addons
ضع هنا وحدات FAQIH المخصصة مستقبلاً. مصدر Odoo القياسي لا يحتوي وحدات FAQIH الخاصة حتى الآن.
ADDONS

cat > .gitignore <<'IGNORE'
.env
OWNER-CREDENTIALS.txt
*.log
backups/
filestore/
IGNORE

cat > README-FIRST.txt <<'INFO'
1. اجعل مستودع GitHub خاصاً.
2. ارفع هذا الملف فقط وشغّله على خادم Linux عليه Docker:
   bash install-faqih-erp.sh
3. سيُنشئ المجلد faqih-erp ويشغل Odoo على المنفذ 8069.
4. بيانات الدخول موجودة في faqih-erp/OWNER-CREDENTIALS.txt بعد التشغيل.
5. افتح http://SERVER_IP:8069 وأنشئ قاعدة البيانات باستخدام بيانات المالك.

هذا المثبت يجهز Odoo 20 القياسي فقط. وحدات FAQIH المخصصة مثل اعتماد طلبات الفروع، حدود الموظفين، الطباعة متعددة الأقسام، وتقارير الصناديق تحتاج تطويراً لاحقاً داخل custom-addons.
INFO

# Prevent accidental exposure in the generated project metadata.
chmod 600 .env OWNER-CREDENTIALS.txt

echo "تم تجهيز FAQIH ERP في: $PROJECT_DIR"
echo "الرابط: http://SERVER_IP:8069"
echo "Owner username: $OWNER_LOGIN"
echo "Owner password: $OWNER_PASSWORD"
echo "Master password: $MASTER_PASSWORD"
echo "غيّر كلمات المرور بعد أول دخول، واجعل مستودع GitHub خاصاً."
docker compose up -d --build
