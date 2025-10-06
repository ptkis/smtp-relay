#!/bin/sh

SMTP_RELAY_HOST=${SMTP_RELAY_HOST?Missing env var SMTP_RELAY_HOST}
SMTP_RELAY_MYHOSTNAME=${SMTP_RELAY_MYHOSTNAME?Missing env var SMTP_RELAY_MYHOSTNAME}
SMTP_RELAY_USERNAME=${SMTP_RELAY_USERNAME?Missing env var SMTP_RELAY_USERNAME}
SMTP_RELAY_PASSWORD=${SMTP_RELAY_PASSWORD?Missing env var SMTP_RELAY_PASSWORD}
SMTP_RELAY_MYNETWORKS=${SMTP_RELAY_MYNETWORKS?Missing env var SMTP_RELAY_MYNETWORKS}
SMTP_RELAY_WRAPPERMODE=${SMTP_RELAY_WRAPPERMODE?Missing env var SMTP_RELAY_WRAPPERMODE}
SMTP_TLS_SECURITY_LEVEL=${SMTP_TLS_SECURITY_LEVEL?Missing env var SMTP_TLS_SECURITY_LEVEL}
# Message Size Limit
SMTP_MESSAGE_SIZE_LIMIT=${SMTP_MESSAGE_SIZE_LIMIT?Missing env var SMTP_MESSAGE_SIZE_LIMIT}

# Optional recipient blocking
BLOCKED_RECIPIENT_EMAILS=${BLOCKED_RECIPIENT_EMAILS:-}
BLOCKED_RECIPIENT_DOMAINS=${BLOCKED_RECIPIENT_DOMAINS:-}

# Optional rate limits (per hour)
# Limit messages per hour per sender address (MAIL FROM)
RATE_LIMIT_SENDER_PER_HOUR=${RATE_LIMIT_SENDER_PER_HOUR:-}
# Limit total messages per hour across the whole instance
RATE_LIMIT_GLOBAL_PER_HOUR=${RATE_LIMIT_GLOBAL_PER_HOUR:-}


# handle sasl
mkdir -p /etc/postfix/sasl
echo "${SMTP_RELAY_HOST} ${SMTP_RELAY_USERNAME}:${SMTP_RELAY_PASSWORD}" > /etc/postfix/sasl/sasl_passwd || exit 1
postmap /etc/postfix/sasl/sasl_passwd || exit 1

postconf 'smtp_sasl_auth_enable = yes' || exit 1
postconf 'smtp_sasl_password_maps = lmdb:/etc/postfix/sasl/sasl_passwd' || exit 1
postconf 'smtp_sasl_security_options =' || exit 1

# These are required.
postconf "relayhost = ${SMTP_RELAY_HOST}" || exit 1
postconf "myhostname = ${SMTP_RELAY_MYHOSTNAME}" || exit 1
postconf "mynetworks = ${SMTP_RELAY_MYNETWORKS}" || exit 1
postconf "smtp_tls_wrappermode = ${SMTP_RELAY_WRAPPERMODE}" || exit 1
postconf "smtp_tls_security_level = ${SMTP_TLS_SECURITY_LEVEL}" || exit 1
# Message Size Limit
postconf "message_size_limit = ${SMTP_MESSAGE_SIZE_LIMIT}" || exit 1

# Configure recipient blocking if requested
HAVE_BLOCKED_RECIPIENTS=0
if [ -n "${BLOCKED_RECIPIENT_EMAILS}" ] || [ -n "${BLOCKED_RECIPIENT_DOMAINS}" ]; then
    HAVE_BLOCKED_RECIPIENTS=1
    RECIPIENT_ACCESS_MAP=/etc/postfix/recipient_access
    : > "${RECIPIENT_ACCESS_MAP}" || exit 1

    IFS=','

    # Blocked recipient email addresses
    for email in ${BLOCKED_RECIPIENT_EMAILS}; do
        email=$(printf "%s" "${email}" | tr -d '[:space:]')
        [ -n "${email}" ] || continue
        printf "%s REJECT 5.7.1 Recipient address is blocked\n" "${email}" >> "${RECIPIENT_ACCESS_MAP}" || exit 1
    done

    # Blocked recipient domains (also match subdomains)
    for domain in ${BLOCKED_RECIPIENT_DOMAINS}; do
        domain=$(printf "%s" "${domain}" | tr -d '[:space:]')
        [ -n "${domain}" ] || continue
        printf "%s REJECT 5.7.1 Recipient domain is blocked\n" "${domain}" >> "${RECIPIENT_ACCESS_MAP}" || exit 1
        case "${domain}" in
            .*) : ;;
            *) printf ".%s REJECT 5.7.1 Recipient domain is blocked\n" "${domain}" >> "${RECIPIENT_ACCESS_MAP}" || exit 1 ;;
        esac
    done

    unset IFS

    postmap "${RECIPIENT_ACCESS_MAP}" || exit 1
fi

# Track whether postfwd is enabled
ENABLE_POSTFWD=0

# Configure postfwd for rate limiting if requested
if [ -n "${RATE_LIMIT_SENDER_PER_HOUR}" ] || [ -n "${RATE_LIMIT_GLOBAL_PER_HOUR}" ]; then
    mkdir -p /etc/postfix /var/lib/postfwd || exit 1
    POSTFWD_RULES_FILE=/etc/postfix/postfwd.cf
    : > "${POSTFWD_RULES_FILE}" || exit 1

    # Per-sender hourly rate limit
    if [ -n "${RATE_LIMIT_SENDER_PER_HOUR}" ]; then
        printf "%s\n" "id=rate_sender; action=rate(sender/${RATE_LIMIT_SENDER_PER_HOUR}/3600/450 4.7.1 Rate limit exceeded for sender $$sender)" >> "${POSTFWD_RULES_FILE}" || exit 1
    fi

    # Global hourly rate limit (single shared bucket)
    if [ -n "${RATE_LIMIT_GLOBAL_PER_HOUR}" ]; then
        printf "%s\n" "id=rate_global; action=rate(global/${RATE_LIMIT_GLOBAL_PER_HOUR}/3600/450 4.7.1 Global hourly rate limit exceeded)" >> "${POSTFWD_RULES_FILE}" || exit 1
    fi

    # Start postfwd policy daemon
    postfwd --daemon --interface 127.0.0.1 --port 10040 \
        --file "${POSTFWD_RULES_FILE}" \
        --logfile /dev/stdout \
        --cache 10000 \
        --save_rates /var/lib/postfwd/rates.db || exit 1

    ENABLE_POSTFWD=1
fi

# Build and apply recipient restrictions if needed
if [ "${ENABLE_POSTFWD}" -eq 1 ] || [ "${HAVE_BLOCKED_RECIPIENTS}" -eq 1 ]; then
    RESTRICTIONS=""
    if [ "${ENABLE_POSTFWD}" -eq 1 ]; then
        RESTRICTIONS="check_policy_service inet:127.0.0.1:10040"
    fi
    if [ "${HAVE_BLOCKED_RECIPIENTS}" -eq 1 ]; then
        if [ -n "${RESTRICTIONS}" ]; then
            RESTRICTIONS="${RESTRICTIONS}, "
        fi
        RESTRICTIONS="${RESTRICTIONS}check_recipient_access lmdb:/etc/postfix/recipient_access"
    fi
    RESTRICTIONS="${RESTRICTIONS}, permit_mynetworks, reject_unauth_destination"
    postconf "smtpd_recipient_restrictions = ${RESTRICTIONS}" || exit 1
fi

# http://www.postfix.org/COMPATIBILITY_README.html#smtputf8_enable
postconf 'smtputf8_enable = no' || exit 1

# This makes sure the message id is set. If this is set to no dkim=fail will happen.
postconf 'always_add_missing_headers = yes' || exit 1

# Log to stdout
postconf 'maillog_file = /dev/stdout' || exit 1

# Start postfix
postfix start-fg
