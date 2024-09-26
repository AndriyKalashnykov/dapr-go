FROM alpine:3.20.1 AS runtime
ARG TARGETPLATFORM
RUN echo "Building for $TARGETPLATFORM"
COPY main /main
CMD ["/bin/sh", "-c", "./main"]
ENTRYPOINT [ "./main" ]