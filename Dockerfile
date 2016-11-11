FROM alpine:3.4

RUN apk add --no-cache curl coreutils bc
ADD api.sh /api.sh

EXPOSE 4242
ENTRYPOINT [ "nc", "-lkp", "4242", "-e" ]
CMD [ "/api.sh" ]
