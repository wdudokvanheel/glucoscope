FROM fedora:41

ARG BINARY_PATH=target/release/glucoscope

COPY ${BINARY_PATH} /usr/local/bin/glucoscope

RUN chmod +x /usr/local/bin/glucoscope

ENTRYPOINT ["/usr/local/bin/glucoscope"]
