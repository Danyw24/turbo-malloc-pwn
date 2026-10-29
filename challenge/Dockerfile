FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90 AS builder

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install build dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

# Build readflag
WORKDIR /build
COPY readflag.c .
COPY turbo-malloc.c .
RUN gcc -o readflag -static readflag.c
RUN gcc -o turbo-malloc -pedantic -Wall -Werror -no-pie -g turbo-malloc.c

FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90 AS runtime

# Install runtime dependencies
RUN apt-get update \
    && apt-get install -y sudo socat \
    && rm -rf /var/lib/apt/lists/*

# Challenge & flag files
COPY --from=builder --chown=root:root /build/readflag /readflag
COPY --from=builder --chown=root:root /build/turbo-malloc /app/turbo-malloc
RUN chmod +s /readflag
COPY --chown=root:root run.sh /app/
RUN chmod +x /app/run.sh /app/turbo-malloc
WORKDIR /app
CMD ["/app/run.sh"]
