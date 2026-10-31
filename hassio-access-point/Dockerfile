ARG BUILD_FROM
FROM $BUILD_FROM

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV LANG=C.UTF-8

RUN apk add --no-cache \
        iw \
        hostapd \
        networkmanager-cli \
        dnsmasq \
        iptables

COPY hostapd.conf dnsmasq.conf net-utils.sh /
COPY run.sh /
RUN chmod a+x /run.sh

HEALTHCHECK --interval=60s --timeout=5s --start-period=60s --retries=3 \
    CMD pidof hostapd > /dev/null || exit 1

CMD [ "/run.sh" ]
