FROM alpine:3.19

RUN apk --no-cache add curl ca-certificates bash netcat-openbsd

COPY webhook.sh /webhook.sh
RUN chmod +x /webhook.sh

ENTRYPOINT ["/bin/bash", "/webhook.sh"]
