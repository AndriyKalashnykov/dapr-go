FROM alpine:3.22.1 as runtime
COPY main /main
CMD ["/bin/sh", "-c", "./main"]
ENTRYPOINT [ "./main" ]