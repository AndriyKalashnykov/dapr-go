FROM alpine:3.20.1 as runtime
COPY main /main
CMD ["/bin/sh", "-c", "./main"]
ENTRYPOINT [ "./main" ]