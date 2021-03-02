FROM alpine:3.13
LABEL maintainer "Jonathan Gazeley"

RUN apk add --no-cache postfix rsyslog supervisor \
    && /usr/bin/newaliases

COPY . /

EXPOSE 25

ENTRYPOINT [ "/tx-smtp-relay.sh" ]
