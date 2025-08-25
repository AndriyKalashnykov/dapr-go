FROM alpine:3.22.1 as runtime
ARG TARGETPLATFORM
RUN echo "Building for $TARGETPLATFORM"
COPY main /main
CMD ["/bin/sh", "-c", "./main"]
ENTRYPOINT [ "./main" ]