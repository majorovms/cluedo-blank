#!/usr/bin/env bash
# Выкладывает web/ на VPS и поднимает лёгкий http-сервер (python3 http.server под systemd).
# Использование:  ./deploy.sh [user@host]      (SSH_PORT=48213 ./deploy.sh — если ssh не на 22)
#                 WEB_PORT=8080 ./deploy.sh    — если порт 80 на сервере занят
set -euo pipefail
HOST="${1:-user@your-vps}"
SSH_PORT="${SSH_PORT:-22}"
WEB_PORT="${WEB_PORT:-80}"
DIR=/var/www/cluedo-blank
cd "$(dirname "$0")"

echo "→ Копирую web/ на $HOST:$DIR"
tar -C web -cf - . | ssh -p "$SSH_PORT" "$HOST" "mkdir -p $DIR && tar -C $DIR -xf - && chmod -R a+rX $DIR"

echo "→ Настраиваю сервис cluedo-blank (порт $WEB_PORT)"
ssh -p "$SSH_PORT" "$HOST" "WEB_PORT=$WEB_PORT DIR=$DIR bash -s" <<'REMOTE'
set -e
UNIT=/etc/systemd/system/cluedo-blank.service
if ss -ltnH "sport = :$WEB_PORT" | grep -q . && ! systemctl is-active --quiet cluedo-blank; then
  echo "!! Порт $WEB_PORT уже занят:"; ss -ltnp "sport = :$WEB_PORT"; echo "Запустите с другим портом: WEB_PORT=8080 ./deploy.sh"; exit 1
fi
cat > "$UNIT" <<UNITEOF
[Unit]
Description=Cluedo blank static page
After=network.target

[Service]
ExecStart=/usr/bin/python3 -m http.server $WEB_PORT --bind 0.0.0.0 --directory $DIR
Restart=always
DynamicUser=yes
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNITEOF
systemctl daemon-reload
systemctl enable --quiet cluedo-blank
systemctl restart cluedo-blank
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then ufw allow "$WEB_PORT/tcp" >/dev/null; fi
sleep 1
curl -s -o /dev/null -w "Проверка на сервере: HTTP %{http_code}\n" "http://127.0.0.1:$WEB_PORT/"
REMOTE

IP="${HOST#*@}"
SUFFIX=""; [ "$WEB_PORT" != 80 ] && SUFFIX=":$WEB_PORT"
echo "✓ Готово: http://$IP$SUFFIX/"
