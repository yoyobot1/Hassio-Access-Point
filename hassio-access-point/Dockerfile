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

COPY hostapd.conf dnsmasq.conf /
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
