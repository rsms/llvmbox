FROM alpine:3.14

WORKDIR /llvm-box

RUN apk add --no-cache bash curl gcc g++ make musl-dev cmake ninja python3 \
  linux-headers tzdata musl-locales

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8

ENV LLVMBOX_BUILD_DIR=/build

RUN mkdir /build

ADD config.sh .
ADD 010-llvm-source.sh .
ADD 011-zlib.sh .
ADD 012-llvm-host-alpine.sh .
