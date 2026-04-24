FROM docker.io/arm64v8/debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install OpenRC and required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    openrc \
    wpasupplicant \
    openssh-server \
    iproute2 \
    procps \
    util-linux \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Prevent OpenRC from ever being removed by apt
RUN apt-mark hold openrc

# Run the command from the OpenRC warning
RUN for file in /etc/rc0.d/K*; do s=$(basename $(readlink "$file")); /etc/init.d/"$s" stop 2>/dev/null || true; done

# Create /sbin/init symlink to openrc-init
RUN ln -sf /sbin/openrc-init /sbin/init

COPY overlay/ /

RUN find /etc/systemd -type l -delete 2>/dev/null || true && \
    rm -rf /etc/systemd /usr/lib/systemd

RUN chmod +x /usr/local/bin/poweroff /usr/local/bin/reboot && \
    chmod u+s /bin/su
