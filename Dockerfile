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
# Install required packages
# -----------------------------
RUN apk add --no-cache \
        bash \
        unzip \
        tini \
        curl \
        libc6-compat \
        libgcc

# -----------------------------
# Create config/pairing directory
# -----------------------------
RUN mkdir -p "$CONFIG_DIR"

# -----------------------------
# Add ADB keys and androidtv-connect script
# -----------------------------
RUN mkdir -m 0750 /root/.android && \
    echo "$INSECURE_SHARED_ADB_KEY" > /root/.android/adbkey && \
    echo "$INSECURE_SHARED_ADB_KEY_PUB" > /root/.android/adbkey.pub && \
    chmod 600 /root/.android/adbkey /root/.android/adbkey.pub

# -----------------------------
# Install yq (lightweight YAML parser)
# -----------------------------
RUN curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# -----------------------------
# Install Android Platform-Tools (ADB)
# -----------------------------
RUN curl -L https://dl.google.com/android/repository/platform-tools-latest-linux.zip -o $ANDROID_HOME/platform-tools-latest-linux.zip && \
    unzip -o $ANDROID_HOME/platform-tools-latest-linux.zip -d $ANDROID_HOME/ \
    && mv $ANDROID_HOME/platform-tools/* $ANDROID_HOME/ \
    && rm -rf $ANDROID_HOME/platform-tools $ANDROID_HOME/platform-tools-latest-linux.zip

# -----------------------------
# Add the androidtv-connect.sh script
# -----------------------------
ADD files/androidtv-connect.sh /usr/local/bin/androidtv-connect.sh
RUN chmod +x /usr/local/bin/androidtv-connect.sh

# -----------------------------
# Expose default ADB port
# -----------------------------
EXPOSE 5037

# -----------------------------
# Use tini as init system
# -----------------------------
ENTRYPOINT ["tini", "--", "/usr/local/bin/androidtv-connect.sh"]
