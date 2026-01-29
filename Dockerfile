# -----------------------------
# Main build
# -----------------------------
FROM alpine:latest

# -----------------------------
# Environment setup
# -----------------------------
ENV ANDROID_HOME=/opt/platform-tools
ENV PATH=$PATH:/opt/platform-tools
ENV CONFIG_DIR=/opt/androidtv-connect

WORKDIR $ANDROID_HOME

# -----------------------------
# Add the androidtv-connect.sh script
# -----------------------------
ADD files/androidtv-connect.sh /usr/local/bin/androidtv-connect.sh

# -----------------------------
# Install packages, setup directories, keys, and install tools
# -----------------------------
RUN apk add --no-cache \
        bash \
        unzip \
        tini \
        curl \
        libc6-compat \
        libgcc && \
    mkdir -p "$CONFIG_DIR" && \
    curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && \
    curl -L https://dl.google.com/android/repository/platform-tools-latest-linux.zip -o $ANDROID_HOME/platform-tools-latest-linux.zip && \
    unzip -o $ANDROID_HOME/platform-tools-latest-linux.zip -d $ANDROID_HOME/ && \
    mv $ANDROID_HOME/platform-tools/* $ANDROID_HOME/ && \
    rm -rf $ANDROID_HOME/platform-tools $ANDROID_HOME/platform-tools-latest-linux.zip && \
    chmod +x /usr/local/bin/androidtv-connect.sh

# -----------------------------
# Add ADB keys using BuildKit secrets
# -----------------------------
RUN --mount=type=secret,id=insecure_shared_adb_key \
    --mount=type=secret,id=insecure_shared_adb_key_pub \
    mkdir -m 0750 /root/.android && \
    cat /run/secrets/insecure_shared_adb_key > /root/.android/adbkey && \
    cat /run/secrets/insecure_shared_adb_key_pub > /root/.android/adbkey.pub && \
    chmod 600 /root/.android/adbkey /root/.android/adbkey.pub

# -----------------------------
# Expose default ADB port
# -----------------------------
EXPOSE 5037

# -----------------------------
# Use tini as init system
# -----------------------------
ENTRYPOINT ["tini", "--", "/usr/local/bin/androidtv-connect.sh"]
