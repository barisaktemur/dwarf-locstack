#!/bin/bash

-() { exit 1; }
usage() { printf 'usage: %s target profile dep_html dep_js\n' "$0"; -; }

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" ||-

(($# >= 4)) || usage

TARGET=$1; shift
PROFILE=$1; shift
DEP_HTML=$1; shift
DEP_JS=$1; shift

case "$PROFILE" in
release)
    awk_script="
        /^<script defer src/ {
            print \"<script type=\\\"module\\\">\"
            while (getline line < \"$DEP_JS\") {
                print line
            }
            print \"</script>\"
            next
        }
        { print }
    "
    ;;
*)
    awk_script='{ print }'
    ;;
esac

awk "$awk_script" "$DEP_HTML" \
    | sed \
        -e "s/GIT_REVISION/$(git describe --match='' --always --dirty)/" \
        -e "s/CURRENT_TIME/$(date -u -Iminutes)/" \
    >"$TARGET" ||-
