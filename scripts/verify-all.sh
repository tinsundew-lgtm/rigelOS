#!/usr/bin/env bash
# Rigel — все быстрые проверки проекта (без сборки ISO).
#
#   bash scripts/verify-all.sh
#
# Проверяет: синтаксис всех скриптов, корректность профиля archiso и логику
# установщика (расчёт разделов, категории приложений, параметры для chroot).
# Занимает пару секунд и не требует Arch Linux.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

echo "=== 1. Синтаксис всех скриптов (bash -n) ==="
while IFS= read -r f; do
    case "$(head -c 2 "$f" 2>/dev/null)" in '#!') : ;; *) continue ;; esac
    if bash -n "$f" 2>/dev/null; then
        printf '  [ok]   %s\n' "${f#$ROOT/}"
    else
        printf '  [FAIL] %s\n' "${f#$ROOT/}"
        bash -n "$f" 2>&1 | sed 's/^/         /'
        FAIL=1
    fi
done < <(find "$ROOT" -type f \
            \( -name '*.sh' -o -name 'rigel-install' -o -name 'rigel-welcome' -o -name 'rigel-live-setup' \) \
            -not -path '*/out/*' -not -path '*/work/*' | sort)

echo
echo "=== 2. Проверка профиля archiso ==="
bash "$ROOT/scripts/check-profile.sh" || FAIL=1

echo
echo "=== 3. Логические тесты установщика ==="
if [ -f "$ROOT/installer/tests/logic-test.sh" ]; then
    bash "$ROOT/installer/tests/logic-test.sh" || FAIL=1
else
    echo "  [предупр] нет installer/tests/logic-test.sh"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "ИТОГ: все проверки пройдены."
else
    echo "ИТОГ: есть ошибки — см. вывод выше."
fi
exit "$FAIL"
