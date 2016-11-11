#!/bin/sh
set -eo pipefail

TIME=$(date +"%s%N")

##
## CONFIG
##

DEBUG=${DEBUG:-false}
RANCHER_API="http://rancher-metadata.rancher.internal/latest"

###
### HTTP Utils
###

error_text () {
    : ${1?"usage: error_text HTTP_RETURN_CODE"}

    case "${1}" in
        200) echo "OK";;
        400) echo "Bad Request";;
        404) echo "Not Found";;
        405) echo "Method Not Allowed";;
        500) echo "Internal Server Error";;
        *) echo "";;
    esac
}

send () {
    while IFS="" read -r line; do
        [ "${DEBUG}" = "true" ] && printf "> %s\n" "${line}" 1>&2
        printf '%s\r\n' "${line}"
    done
}

log () {
    echo "$@" 1>&2
}

reply () {
    local statusc=${HTTP_RETURN:-200}
    local content=${CONTENT_TYPE:-"text/plain"}

    ### HTTP Reply
    # HTTP initial line
    printf "HTTP/1.0 %d %s\n" "${statusc}" "$(error_text ${statusc})" | send
    # HTTP Headers
    echo "Content-Type: ${content}" | send
    # Separator
    echo "" | send
    # HTTP Body
    send # Read reply body

    ### Logging
    duration=$(printf "(%s-%s)/1000000\n" $(date +"%s%N") "${TIME}" | bc)
    log "= $(date +"%d/%m/%y %H:%M:%S") - ${method} ${uri} - ${statusc} $(error_text ${statusc}) - Took ${duration} ms"

    exit 0
}

http_error () {
    : ${1?"usage: http_error HTTP_RETURN_CODE [REASON]"}

    local tmpl
    if [ -z "${2}" ]; then
        tmpl='{
    error: %d,
    text: "%s"
}'
    else
        tmpl='{
    error: %d,
    text: "%s",
    reason: "%s"
}'
    fi

    HTTP_RETURN=${1}
    CONTENT_TYPE="text/json"
    shift

    printf "${tmpl}\n" "${HTTP_RETURN}" \
                       "$(error_text ${HTTP_RETURN})" \
                       "$@" | reply
}

internal_error () {
    status=${?}
    trap - EXIT
    if [ "${status}" != 0 ]; then
        http_error 500 $@
    fi
    exit 1
}

##
## API Logic
##

index () {

    CONTENT_TYPE="text/json"
    local tmpl='{
    "hosts": %d,
    "stacks": %d,
    "services": %d,
    "containers": %d
}'


    host=$(curl -sSL ${RANCHER_API}/hosts | wc -l) \
        || internal_error curl_error
    stacks=$(curl -sSL ${RANCHER_API}/stacks | wc -l) \
        || internal_error curl_error
    srv=$(curl -sSL ${RANCHER_API}/containers | wc -l) \
        || internal_error curl_error
    ctn=$(curl -sSL ${RANCHER_API}/services | wc -l) \
        || internal_error curl_error

    printf "${tmpl}\n" ${host} ${stacks} ${srv} ${ctn} | reply
}

status () {
    CONTENT_TYPE="text/json"
    printf '{
    "status": "ok"
}\n' | reply
}

##
## MAIN
##

main () {

    ### HTTP Request Header
    # Fetch HTTP initial line
    read -r method uri version
    [ "${DEBUG}" = "true" ] \
        && log "< ${method} ${uri} $(echo ${version} | tr -d '\r')"
    # Verify HTTP initial line
    test -n "${method}" && test -n "${uri}" && test -n "${version}" \
      || http_error 400
    # Only accept HTTP GET request
    [ "${method}" = "GET" ] || http_error 405
    # Ignore HTTP Headers (required for a complete request)
    while read -r line; do
        line=$(echo $line | tr -d '\r')
        [ -z "$line" ] && break
    done
    # Body is never read as we only accept HTTP GET

    ### Routing
    case ${uri} in
        /)           index;;
        # /hosts)      index;;
        # /stacks)     index;;
        # /services)   index;;
        # /containers) index;;
        /status)     status;;
        *)           http_error 404;;
    esac
}

trap internal_error EXIT
main
