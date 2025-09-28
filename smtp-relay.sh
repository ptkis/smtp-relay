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

    # Wire policy service into recipient restrictions
    postconf "smtpd_recipient_restrictions = check_policy_service inet:127.0.0.1:10040, permit_mynetworks, reject_unauth_destination" || exit 1
fi

# http://www.postfix.org/COMPATIBILITY_README.html#smtputf8_enable
postconf 'smtputf8_enable = no' || exit 1

# This makes sure the message id is set. If this is set to no dkim=fail will happen.
postconf 'always_add_missing_headers = yes' || exit 1

# Log to stdout
postconf 'maillog_file = /dev/stdout' || exit 1

# Start postfix
postfix start-fg
