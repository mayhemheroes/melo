FROM ghcr.io/evanrichter/cargo-fuzz as builder

ADD . /melo
WORKDIR /melo/fuzz
RUN cargo +nightly fuzz build 

# WORKDIR /melo
# RUN cargo build 

FROM debian:bookworm
COPY --from=builder /melo/fuzz/target/x86_64-unknown-linux-gnu/release/melo-fuzzer /
# COPY --from=builder /melo/target/debug/melo /
COPY --from=builder /melo/pieces /pieces/