#!/bin/sh

set -e

create()
{
    rm -f /tmp/zzuf-zero-$$
    dd if=/dev/zero of=/tmp/zzuf-zero-$$ bs=1024 count=32 2>/dev/null
    rm -f /tmp/zzuf-random-$$
    dd if=/dev/urandom of=/tmp/zzuf-random-$$ bs=1024 count=32 2>/dev/null
    rm -f /tmp/zzuf-text-$$
    strings </dev/urandom | dd bs=1024 count=32 of=/tmp/zzuf-text-$$ 2>/dev/null
    echo "" >> /tmp/zzuf-text-$$ # Make sure we have a newline at EOF
}

check()
{
    ZZOPTS="$1"
    CMD="$2"
    ALIAS="$3"
    CHECK="$4"
    echo -n " $(echo "$ALIAS .............." | cut -b1-18) "
    MD5="$(eval "$ZZUF -m $ZZOPTS $CMD" 2>/dev/null | cut -f2 -d' ')"
    if [ -n "$CHECK" ]; then
        REFMD5="$CHECK"
    fi
    if [ -z "$REFMD5" ]; then
        REFMD5="$MD5"
        echo "$MD5"
    else
        TESTED=$(($TESTED + 1))
        if [ "$MD5" != "$REFMD5" ]; then
            FAILED=$(($FAILED + 1))
            echo "$MD5 FAILED"
        else
            echo 'ok'
        fi
    fi
}

cleanup() {
    if [ "$FAILED" = 0 ]; then
        rm -f /tmp/zzuf-zero-$$
        rm -f /tmp/zzuf-random-$$
        rm -f /tmp/zzuf-text-$$
        echo "*** temporary files removed ***"
    else
        echo "*** files preserved ***"
        echo " /tmp/zzuf-zero-$$"
        echo " /tmp/zzuf-random-$$"
        echo " /tmp/zzuf-text-$$"
    fi
}

trap "echo ''; echo '*** ABORTED ***'; cleanup; exit 0" 1 2 15

seed=$((0+0$1))
ZZUF="$(dirname "$0")/../src/zzuf"
FDCAT="$(dirname "$0")/fdcat"
STREAMCAT="$(dirname "$0")/streamcat"
if [ ! -f "$FDCAT" -o ! -f "$STREAMCAT" ]; then
  echo "error: test/fdcat or test/streamcat are missing"
  exit 1
fi
if file /bin/cat | grep -q 'statically linked'; then
  STATIC_CAT=1
fi
if file /bin/dd | grep -q 'statically linked'; then
  STATIC_DD=1
fi
FAILED=0
TESTED=0

echo "*** running zzuf test suite ***"
echo "*** creating test files ***"
create
echo "*** using seed $seed ***"

for r in 0.0 0.00001 0.001 0.1 10.0; do
    for type in zero text random; do
        file=/tmp/zzuf-$type-$$
        ZZOPTS="-s $seed -r $r"
        case $file in
          *text*) ZZOPTS="$ZZOPTS -P '\n'" ;;
        esac
        echo "*** file $file, ratio $r ***"
        REFMD5=""
        if [ $r = 0.0 -a $type = zero ]; then
            check="bb7df04e1b0a2570657527a7e108ae23"
            echo "*** should be $check ***"
            check "$ZZOPTS" "< $file" "zzuf" "$check"
        else
            check "$ZZOPTS" "< $file" "zzuf"
        fi
        check "$ZZOPTS" "$FDCAT $file" "fdcat"
        check "$ZZOPTS" "$STREAMCAT $file" "streamcat"
        if [ "$STATIC_CAT" = "" ]; then
            check "$ZZOPTS" "cat $file" "cat"
            check "$ZZOPTS" "-i cat < $file" "|cat"
        fi
        if [ "$STATIC_DD" = "" ]; then
            check "$ZZOPTS" "dd bs=65536 if=$file" "dd(bs=65536)"
            check "$ZZOPTS" "dd bs=1111 if=$file" "dd(bs=1111)"
            check "$ZZOPTS" "dd bs=1024 if=$file" "dd(bs=1024)"
            check "$ZZOPTS" "dd bs=1 if=$file" "dd(bs=1)"
        fi
        case $file in
          *text*)
            # We don't include grep or sed when the input is not text, because
            # they put a newline at the end of their input if it was not there
            # initially. (Linux sed doesn't, but OS X sed does.)
            check "$ZZOPTS" "head -- -n 9999 $file" "head -n 9999"
            check "$ZZOPTS" "tail -- -n 9999 $file" "tail -n 9999"
            check "$ZZOPTS" "tail -- -n +1 $file" "tail -n +1"
            check "$ZZOPTS" "grep -- -a '' $file" "grep -a ''"
            check "$ZZOPTS" "sed -- -e n $file" "sed -e n"
            #check "$ZZOPTS" "cut -- -b1- $file" "cut -b1-"
            check "$ZZOPTS" "-i head -- -n 9999 < $file" "|head -n 9999"
            check "$ZZOPTS" "-i tail -- -n 9999 < $file" "|tail -n 9999"
            check "$ZZOPTS" "-i tail -- -n +1 < $file" "|tail -n +1"
            check "$ZZOPTS" "-i grep -- -a '' < $file" "|grep -a ''"
            check "$ZZOPTS" "-i sed -- -e n < $file" "|sed -e n"
            #check "$ZZOPTS" "-i cut -- -b1- < $file" "|cut -b1-"
            ;;
        esac
    done
done

if [ "$FAILED" != 0 ]; then
    echo "*** $FAILED tests failed out of $TESTED ***"
    cleanup
    exit 1
fi
echo "*** all $TESTED tests OK ***"

cleanup
exit 0

