# tx-smtp-relay

This image provides an SMTP relay host for emails from within a Kubernetes cluster.

Configure this container to use an upstream authenticated SMTP relay like SendGrid or your ISP's mail server, and provide an
open relay service to your cluster. This means you don't have to configure all of your containerised services with email auth secrets.
 
## Config

This image supports the following enironment variables. All are **required**.


| Variable                   | Use                                                                 | Example                      |
|----------------------------|---------------------------------------------------------------------|------------------------------|
| `TX_SMTP_RELAY_HOST`       | Hostname of upstream SMTP relay server                              | `[smtp.sendgrid.net]:587`    |
| `TX_SMTP_RELAY_USERNAME`   | Username for upstream SMTP relay server                             | `apikey`                     |
| `TX_SMTP_RELAY_PASSWORD`   | Password for upstream SMTP relay server                             | `pAsSwOrD`                   |
| `TX_SMTP_RELAY_MYHOSTNAME` | Hostname of this SMTP relay                                         | `tx-smtp-relay.yourhost.com` |
| `TX_SMTP_RELAY_MYNETWORKS` | Comma-separated list of local networks that can use this SMTP relay | `127.0.0.0/8,10.0.0.0/8`     |

# Quickstart
Run on docker
```
docker run --rm -it -p 2525:25 \
	-e TX_SMTP_RELAY_HOST="[smtp.sendgrid.net]:587" \
	-e TX_SMTP_RELAY_MYHOSTNAME=tx-smtp-relay.yourhost.com \
	-e TX_SMTP_RELAY_USERNAME=username \
	-e TX_SMTP_RELAY_PASSWORD=password \
	-e TX_SMTP_RELAY_MYNETWORKS=127.0.0.0/8,10.0.0.0/8 \
	djjudas21/tx-smtp-relay

```
Send a test message
<pre>
<b>telnet localhost 2525</b>
220 tx-smtp-relay.yourhost.com ESMTP Postfix
<b>helo localhost</b>
250 tx-smtp-relay.yourhost.com
<b>mail from: noreply@yourhost.com</b>
250 2.1.0 Ok
<b>rcpt to: chris@applariat.com</b>
250 2.1.5 Ok
<b>data</b>
354 End data with <CR><LF>.<CR><LF>
<b>Subject: What?</b>
<b>My hovercraft is full of eels.</b>
<b>.</b>
250 2.0.0 Ok: queued as 982FF53C
<b>quit</b>
221 2.0.0 Bye
Connection closed by foreign host
</pre>
