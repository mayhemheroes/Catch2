FROM fuzzers/libfuzzer:12.0 as builder

RUN apt-get update
RUN apt install -y build-essential wget git clang cmake  automake autotools-dev  libtool zlib1g zlib1g-dev libexif-dev 
ADD . /Catch2
WORKDIR /Catch2
RUN mkdir ./build
WORKDIR /Catch2/build
RUN cmake -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ ..
RUN make
RUN make install
WORKDIR /Catch2/fuzzing
RUN ./build_fuzzers.sh

FROM fuzzers/libfuzzer:12.0
COPY --from=builder Catch2/build-fuzzers/fuzzing/fuzz_XmlWriter /
COPY --from=builder /usr/local/lib/* /usr/local/lib/

ENTRYPOINT []
CMD  ["/fuzz_XmlWriter"]
