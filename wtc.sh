#!/bin/env sh

if [ -z "$XDG_RUNTIME_DIR" ];
then TMPDIR="/tmp/wtc"
else TMPDIR="$XDG_RUNTIME_DIR/wtc"
fi

if [ -z "$XDG_CACHE_HOME" ];
then CCHDIR="$HOME/.cache/wtc"
else CCHDIR="$XDG_CACHE_HOME/wtc"
fi

SEARCH_RESULTS="$CCHDIR/words"
RESPONSE="$TMPDIR/resp"

HTML_DEFAULT="elinks -no-numbering -no-references -dump -dump-color-mode 1"
HTML_READER="${WTC_HTML_READER:-$HTML_DEFAULT}"
CACHE="${WTC_CACHE:-false}"

die() {
    echo "$*" 1>&2
    exit 1
}

search() {
    search_base="${php_base}&list=prefixsearch&pslimit=${search_limit}&pssearch="
    search_url="${search_base}$*"
    code=$(curl -w "%{http_code}" -o "$TMPDIR/request" -L -s "$search_url")
    if [ "$code" -eq 200 ]; then
        jq -r '.query.prefixsearch|map(.title)|@tsv' "$TMPDIR/request" \
            | sed 's/\t/\n/g' > "$SEARCH_RESULTS"
    fi
    rm -f "$TMPDIR/request"
    echo "$code"
}

html() {
    html_base="${rest_base}/page/html/"
    html_url="${html_base}$*"
    curl -L -w "%{http_code}" -s "$html_url" -o "$RESPONSE"
}

mkdir -p "$TMPDIR" || die "Could not create tmp dir at $TMPDIR"
mkdir -p "$CCHDIR" || die "Could not create cache dir at $CCHDIR"

wikilang=$(echo $LANG | cut -c-2)
[ "$LANG" = "C" -o "$LANG" = "POSIX" ] && wikilang=en
search_limit="10"
search="false"
hint=""

OPTIND=1
while getopts h:sl:L: flag; do
    case "$flag" in
        h) hint=$OPTARG;;
        L) wikilang=$OPTARG;;
        l) search_limit=$OPTARG;;
        s) search=true;;
        [?]) die "invalid flag -- $OPTARG"
    esac
done
shift $((OPTIND-1))

query_word="$*"

domain="https://$wikilang.wiktionary.org"
rest_base="${domain}/api/rest_v1"
php_base="${domain}/w/api.php?action=query&format=json"

if [ -n "$hint" ]; then
    if [ ! -r "$SEARCH_RESULTS" ]; then
        die "no previously searched words"
    elif ! [ "$hint" -ge 0 ] 2> /dev/null; then
        die "hint number not a positive integer -- $hint"
    else
        res_count="$(wc -l < "$SEARCH_RESULTS")"
        if [ "$hint" -gt "$res_count" ]; then
            die "hint number larger than number of results -- $hint>$res_count"
        fi
    fi

    word="$(sed "${hint}q;d" "$SEARCH_RESULTS")"
    if [ -n "$word" ]; then
        query_word="$word"
    else
        die "hint numbering failed"
    fi
fi

[ -z "$query_word" ] && die "no query word specifed"

query_uri="$(printf '"%s"' "$query_word" | jq -r @uri)"

if [ "$search" = "false" ] || [ -n "$hint" ]; then
    page="$CCHDIR/$wikilang/$query_uri"
    if [ -r "$page" ]; then
        found=true;
    else
        code=$(html "$query_uri")
        if [ "$code" -eq 200 ]; then
            found=true;
            mkdir -p "$(dirname "$page")"
            [ "$CACHE" = "true" ] && cp "$RESPONSE" "$page"
        elif [ "$code" -eq 404 ]; then
            found=false;
        else
            die "lookup failed -- http code $code."
        fi
    fi
fi

if [ "$found" = "true" ]; then
    $HTML_READER "$RESPONSE" | grep -v "Link: " | less -r
else
    code=$(search "$query_uri")
    if [ "$code" -ne 200 ]; then
        die "Search failed: http code $code."
    fi
    if [ -n "$(head -n1 $SEARCH_RESULTS)" ]; then
        nl -w 2 -s "]  $(printf "\033[0;34m")" "$SEARCH_RESULTS" \
            | sed -e 's/^/\x1B[0;2m[/' 
    else
        printf 'No results found for "%s"\n' "$query_word"
    fi
fi

rm -rf "$TMPDIR"
