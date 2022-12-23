FROM ghcr.io/evanrichter/cargo-fuzz as builder

ADD . /a/b/melo
WORKDIR /a
RUN mkdir libs && cd libs && git clone https://github.com/mistodon/sashimi.git

WORKDIR /a/b/melo/fuzz
RUN cargo +nightly fuzz build 

FROM debian:bookworm
COPY --from=builder /a/b/melo/fuzz/target/x86_64-unknown-linux-gnu/release/melo-fuzzer /