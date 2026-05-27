FROM alpine:3.19
RUN apk add --no-cache ca-certificates
ARG FRP_VERSION=0.61.0
ADD https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz /tmp/
RUN cd /tmp && tar xzf frp_${FRP_VERSION}_linux_amd64.tar.gz \
    && mv frp_${FRP_VERSION}_linux_amd64/frps /usr/local/bin/ \
    && rm -rf /tmp/frp*
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 10000
CMD ["/entrypoint.sh"]
