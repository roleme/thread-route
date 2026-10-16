FROM alpine:3.20

RUN apk add --no-cache iproute2 ndisc6 socat

COPY thread-route.sh /usr/local/bin/thread-route.sh

ENTRYPOINT ["/usr/local/bin/thread-route.sh"]
